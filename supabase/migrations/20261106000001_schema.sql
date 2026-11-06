-- =====================================================================
-- Мини-CRM «Объекты и задачи»: схема, триггеры, функция смены статуса
-- =====================================================================

-- ---------- Типы ----------
create type public.user_role   as enum ('manager', 'executor');  -- постановщик / исполнитель
create type public.task_status as enum ('new', 'in_progress', 'review', 'rework', 'accepted');

-- ---------- Таблицы ----------
-- Профиль пользователя. Роль хранится ТОЛЬКО здесь; клиент изменить её не может
-- (нет ни политики UPDATE, ни права UPDATE).
create table public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  email      text not null,
  full_name  text not null default '',
  role       public.user_role not null default 'executor',
  created_at timestamptz not null default now()
);

create table public.objects (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (length(btrim(name)) > 0),
  address    text not null default '',
  created_by uuid references public.profiles (id) default auth.uid(),
  created_at timestamptz not null default now()
);

create table public.tasks (
  id          uuid primary key default gen_random_uuid(),
  title       text not null check (length(btrim(title)) > 0),
  description text not null default '',
  object_id   uuid not null references public.objects (id) on delete restrict,
  assignee_id uuid not null references public.profiles (id) on delete restrict,
  status      public.task_status not null default 'new',
  author_id   uuid not null references public.profiles (id) on delete restrict,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index tasks_object_idx   on public.tasks (object_id);
create index tasks_assignee_idx on public.tasks (assignee_id);

create table public.task_history (
  id          bigint generated always as identity primary key,
  task_id     uuid not null references public.tasks (id) on delete cascade,
  changed_by  uuid not null references public.profiles (id),
  from_status public.task_status,            -- null только для создания задачи
  to_status   public.task_status not null,
  comment     text,
  created_at  timestamptz not null default now()
);
create index task_history_task_idx on public.task_history (task_id, created_at);

-- ---------- Вспомогательные функции для RLS ----------
-- security definer: читают profiles в обход RLS (иначе рекурсия политик).
create function public.app_role() returns public.user_role
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

create function public.is_manager() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select role = 'manager' from public.profiles where id = auth.uid()), false)
$$;

-- ---------- Профиль создаётся автоматически при создании пользователя ----------
-- Роль берётся из raw_app_meta_data (клиент изменить его не может); по умолчанию — исполнитель.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name, role)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    case when new.raw_app_meta_data ->> 'role' = 'manager'
         then 'manager'::public.user_role else 'executor'::public.user_role end
  );
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Триггеры задач ----------
-- Исполнителем может быть только пользователь с ролью «исполнитель»; обновление updated_at.
create function public.tasks_before_write() returns trigger
language plpgsql security definer set search_path = public as $$
declare r public.user_role;
begin
  if tg_op = 'INSERT' or new.assignee_id is distinct from old.assignee_id then
    select role into r from public.profiles where id = new.assignee_id;
    if r is distinct from 'executor' then
      raise exception 'Исполнителем может быть только пользователь с ролью «исполнитель»'
        using errcode = 'check_violation';
    end if;
  end if;
  if tg_op = 'UPDATE' then
    new.updated_at := now();
  end if;
  return new;
end $$;

create trigger tasks_before_write
  before insert or update on public.tasks
  for each row execute function public.tasks_before_write();

-- Создание задачи фиксируется в истории («— → Новая»).
create function public.tasks_after_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.task_history (task_id, changed_by, from_status, to_status)
  values (new.id, new.author_id, null, 'new');
  return new;
end $$;

create trigger tasks_after_insert
  after insert on public.tasks
  for each row execute function public.tasks_after_insert();

-- ---------- Единственный путь смены статуса ----------
-- У клиентов нет права UPDATE на колонку status, поэтому сменить статус можно
-- только этой функцией. Она проверяет роль, назначение, допустимость перехода,
-- обязательный комментарий и пишет историю — всё в одной транзакции.
create function public.change_task_status(
  p_task_id uuid,
  p_to      public.task_status,
  p_comment text default null
) returns public.tasks
language plpgsql security definer set search_path = public as $$
declare
  uid   uuid := auth.uid();
  me    public.user_role;
  t     public.tasks;
  old_status public.task_status;
  clean text := nullif(btrim(coalesce(p_comment, '')), '');
begin
  if uid is null then
    raise exception 'Требуется вход в систему' using errcode = 'insufficient_privilege';
  end if;

  select role into me from public.profiles where id = uid;
  if me is null then
    raise exception 'Профиль пользователя не найден' using errcode = 'insufficient_privilege';
  end if;

  select * into t from public.tasks where id = p_task_id for update;
  -- Исполнитель не должен даже узнавать о существовании чужой задачи.
  if not found or (me = 'executor' and t.assignee_id <> uid) then
    raise exception 'Задача не найдена' using errcode = 'P0002';
  end if;

  if (t.status = 'new'         and p_to = 'in_progress')
  or (t.status = 'in_progress' and p_to = 'review')
  or (t.status = 'rework'      and p_to = 'in_progress') then
    -- только назначенный исполнитель
    if not (me = 'executor' and t.assignee_id = uid) then
      raise exception 'Этот переход может выполнить только назначенный исполнитель'
        using errcode = 'insufficient_privilege';
    end if;

  elsif (t.status = 'review' and p_to = 'accepted')
     or (t.status = 'review' and p_to = 'rework') then
    -- только постановщик
    if me <> 'manager' then
      raise exception 'Этот переход может выполнить только постановщик'
        using errcode = 'insufficient_privilege';
    end if;
    if p_to = 'rework' and clean is null then
      raise exception 'При возврате на доработку комментарий обязателен'
        using errcode = 'check_violation';
    end if;

  else
    raise exception 'Переход из статуса % в статус % запрещён', t.status, p_to
      using errcode = 'check_violation';
  end if;

  old_status := t.status;
  update public.tasks set status = p_to where id = p_task_id returning * into t;

  insert into public.task_history (task_id, changed_by, from_status, to_status, comment)
  values (p_task_id, uid, old_status, p_to, clean);

  return t;
end $$;
