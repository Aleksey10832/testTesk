-- =====================================================================
-- Права доступа: два независимых слоя — GRANT (какие операции/колонки вообще
-- разрешены) и RLS (какие строки видны). Защита работает на уровне базы,
-- поэтому прямые запросы к REST API Supabase в обход интерфейса её не обходят.
-- =====================================================================

alter table public.profiles     enable row level security;
alter table public.objects      enable row level security;
alter table public.tasks        enable row level security;
alter table public.task_history enable row level security;

-- ---------- Слой 1: GRANT ----------
revoke all on public.profiles, public.objects, public.tasks, public.task_history
  from anon, authenticated;

grant select on public.profiles     to authenticated;          -- менять профиль/роль нельзя
grant select, insert, update, delete on public.objects to authenticated;

grant select, delete on public.tasks to authenticated;
-- status, created_at, updated_at в списках колонок НЕТ: статус меняется только через RPC
grant insert (title, description, object_id, assignee_id, author_id) on public.tasks to authenticated;
grant update (title, description, object_id, assignee_id)           on public.tasks to authenticated;

grant select on public.task_history to authenticated;          -- INSERT/UPDATE/DELETE нет ни у кого
-- (запись в историю делают только триггер и change_task_status — они security definer)

-- ---------- Слой 2: политики RLS ----------
-- profiles: свой профиль; постановщик видит всех; исполнитель видит постановщиков (авторы задач)
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_manager() or role = 'manager');

-- objects: постановщик — всё; исполнитель — только объекты, где у него есть задачи.
-- (подзапрос к tasks сам фильтруется RLS tasks, т.е. видны только его задачи)
create policy objects_select on public.objects for select to authenticated
  using (public.is_manager()
         or exists (select 1 from public.tasks t where t.object_id = objects.id));
create policy objects_insert on public.objects for insert to authenticated
  with check (public.is_manager());
create policy objects_update on public.objects for update to authenticated
  using (public.is_manager()) with check (public.is_manager());
create policy objects_delete on public.objects for delete to authenticated
  using (public.is_manager());

-- tasks
create policy tasks_select on public.tasks for select to authenticated
  using (public.is_manager() or assignee_id = auth.uid());
create policy tasks_insert on public.tasks for insert to authenticated
  with check (public.is_manager() and author_id = auth.uid());
create policy tasks_update on public.tasks for update to authenticated
  using (public.is_manager()) with check (public.is_manager());
create policy tasks_delete on public.tasks for delete to authenticated
  using (public.is_manager());

-- task_history: только чтение, и только истории тех задач, которые пользователь видит
create policy history_select on public.task_history for select to authenticated
  using (exists (select 1 from public.tasks t where t.id = task_history.task_id));

-- ---------- Функции: кто может вызывать ----------
revoke execute on function public.app_role()        from public, anon, authenticated;
revoke execute on function public.is_manager()      from public, anon, authenticated;
revoke execute on function public.change_task_status(uuid, public.task_status, text)
  from public, anon, authenticated;
revoke execute on function public.handle_new_user()     from public, anon, authenticated;
revoke execute on function public.tasks_before_write()  from public, anon, authenticated;
revoke execute on function public.tasks_after_insert()  from public, anon, authenticated;

-- RLS-политики вызывают эти функции от имени пользователя, поэтому authenticated нужен EXECUTE
grant execute on function public.app_role()   to authenticated;
grant execute on function public.is_manager() to authenticated;
grant execute on function public.change_task_status(uuid, public.task_status, text) to authenticated;
