-- =====================================================================
-- Тестовые данные. Выполнить в SQL Editor Supabase (роль postgres) ПОСЛЕ миграций.
-- Пароль у всех пользователей: Test1234!
--   manager1@example.com, manager2@example.com   — постановщики
--   executor1@example.com, executor2@example.com — исполнители
-- Пользователи создаются напрямую в auth.users (открытая регистрация отключена).
-- Роль передаётся через raw_app_meta_data — триггер создаёт профиль.
-- =====================================================================

do $$
declare u record;
begin
  for u in select * from (values
    ('11111111-1111-1111-1111-111111111111'::uuid, 'manager1@example.com',  'Анна Соколова (постановщик)',  'manager'),
    ('22222222-2222-2222-2222-222222222222'::uuid, 'manager2@example.com',  'Пётр Орлов (постановщик)',     'manager'),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, 'executor1@example.com', 'Сергей Ким (исполнитель)',     'executor'),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid, 'executor2@example.com', 'Ольга Лебедева (исполнитель)', 'executor')
  ) as t(id, email, full_name, role)
  loop
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change)
    values (
      '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email,
      extensions.crypt('Test1234!', extensions.gen_salt('bf')), now(),
      jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email'), 'role', u.role),
      jsonb_build_object('full_name', u.full_name), now(), now(), '', '', '', '')
    on conflict (id) do nothing;

    insert into auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), u.id,
            jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
            'email', u.id::text, now(), now(), now())
    on conflict do nothing;
  end loop;
end $$;

-- Объекты
insert into public.objects (id, name, address, created_by) values
  ('d0000000-0000-0000-0000-000000000001', 'ЖК «Северный», корпус 2', 'г. Москва, ул. Северная, 12', '11111111-1111-1111-1111-111111111111'),
  ('d0000000-0000-0000-0000-000000000002', 'Склад на Промышленной',   'г. Химки, Промышленная, 5',   '11111111-1111-1111-1111-111111111111'),
  ('d0000000-0000-0000-0000-000000000003', 'Коттедж в Одинцово',      'г. Одинцово, СНТ «Берёзки», уч. 14', '22222222-2222-2222-2222-222222222222');

-- Задачи в разных статусах (триггер сам добавит в историю запись «— → Новая»)
insert into public.tasks (id, title, description, object_id, assignee_id, status, author_id) values
  ('c0000000-0000-0000-0000-000000000001', 'Заказать арматуру',
     'Арматура А500С, 12 мм, 4 тонны. Согласовать поставку с закупками.',
     'd0000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'new',
     '11111111-1111-1111-1111-111111111111'),
  ('c0000000-0000-0000-0000-000000000002', 'Залить фундамент секции Б',
     'Бетон В25, контроль температуры, образцы на испытание.',
     'd0000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'in_progress',
     '11111111-1111-1111-1111-111111111111'),
  ('c0000000-0000-0000-0000-000000000003', 'Принять бетон по акту',
     'Сверить объём и марку бетона с накладной.',
     'd0000000-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'review',
     '22222222-2222-2222-2222-222222222222'),
  ('c0000000-0000-0000-0000-000000000004', 'Смонтировать вентиляцию',
     'Приточно-вытяжная система в складском зале по проекту ОВ-3.',
     'd0000000-0000-0000-0000-000000000002', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'rework',
     '11111111-1111-1111-1111-111111111111'),
  ('c0000000-0000-0000-0000-000000000005', 'Составить смету кровли',
     'Смета по материалам и работам, сравнить два варианта утеплителя.',
     'd0000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'accepted',
     '11111111-1111-1111-1111-111111111111'),
  ('c0000000-0000-0000-0000-000000000006', 'Подготовить участок',
     'Расчистка, геодезическая разбивка, временное ограждение.',
     'd0000000-0000-0000-0000-000000000003', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'in_progress',
     '22222222-2222-2222-2222-222222222222');

-- Дальнейшая история (с разнесёнными по времени записями; в обход RPC — это владелец базы)
insert into public.task_history (task_id, changed_by, from_status, to_status, comment, created_at) values
  ('c0000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'new', 'in_progress', null, now() + interval '1 minute'),
  ('c0000000-0000-0000-0000-000000000003', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'new', 'in_progress', null, now() + interval '1 minute'),
  ('c0000000-0000-0000-0000-000000000003', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'in_progress', 'review', 'Накладная и акт приложены.', now() + interval '2 minutes'),
  ('c0000000-0000-0000-0000-000000000004', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'new', 'in_progress', null, now() + interval '1 minute'),
  ('c0000000-0000-0000-0000-000000000004', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'in_progress', 'review', 'Смонтировано, жду проверки.', now() + interval '2 minutes'),
  ('c0000000-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', 'review', 'rework', 'Не закреплены воздуховоды в осях 3–5, переделать.', now() + interval '3 minutes'),
  ('c0000000-0000-0000-0000-000000000005', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'new', 'in_progress', null, now() + interval '1 minute'),
  ('c0000000-0000-0000-0000-000000000005', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'in_progress', 'review', 'Смета готова.', now() + interval '2 minutes'),
  ('c0000000-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111', 'review', 'accepted', null, now() + interval '3 minutes'),
  ('c0000000-0000-0000-0000-000000000006', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'new', 'in_progress', null, now() + interval '1 minute');
