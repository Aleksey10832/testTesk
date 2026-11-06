-- Проверка защиты на уровне базы. Запускать в SQL Editor ПОСЛЕ миграций и seed.sql.
-- Всё выполняется в транзакции с откатом: данные не меняются.
-- Каждый блок падает с ошибкой ASSERT, если защита не сработала.
begin;

-- ===== Исполнитель 1 =====
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}', true);
set local role authenticated;

do $$ begin
  assert (select count(*) from public.tasks) = 3, 'исполнитель 1 должен видеть ровно 3 свои задачи';
  assert (select count(*) from public.objects) = 2, 'исполнитель 1 должен видеть 2 объекта';
  assert (select count(*) from public.tasks where id = 'c0000000-0000-0000-0000-000000000003') = 0, 'чужая задача видна';
end $$;

do $$ declare n int; begin   -- правка чужой задачи: 0 строк
  update public.tasks set title = 'взлом' where id = 'c0000000-0000-0000-0000-000000000003';
  get diagnostics n = row_count;
  assert n = 0, 'исполнитель изменил чужую задачу';
end $$;

do $$ begin   -- прямая смена статуса запрещена даже для своей задачи
  begin
    update public.tasks set status = 'accepted' where id = 'c0000000-0000-0000-0000-000000000001';
    assert false, 'прямой UPDATE статуса прошёл';
  exception when insufficient_privilege then null; end;
end $$;

do $$ begin   -- запись в историю запрещена
  begin
    insert into public.task_history (task_id, changed_by, to_status)
    values ('c0000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'accepted');
    assert false, 'вставка в историю прошла';
  exception when insufficient_privilege then null; end;
end $$;

do $$ begin   -- пропуск статуса: new -> review
  begin
    perform public.change_task_status('c0000000-0000-0000-0000-000000000001', 'review');
    assert false, 'запрещённый переход прошёл';
  exception when check_violation then null; end;
end $$;

do $$ begin   -- чужая задача через RPC
  begin
    perform public.change_task_status('c0000000-0000-0000-0000-000000000003', 'accepted');
    assert false, 'RPC сработал на чужой задаче';
  exception when sqlstate 'P0002' then null; end;
end $$;

do $$ begin   -- допустимый переход
  perform public.change_task_status('c0000000-0000-0000-0000-000000000001', 'in_progress');
  assert (select status from public.tasks where id = 'c0000000-0000-0000-0000-000000000001') = 'in_progress';
end $$;

do $$ begin   -- исполнитель не может принять задачу, даже свою на проверке
  begin
    perform public.change_task_status('c0000000-0000-0000-0000-000000000002', 'accepted');
    assert false, 'исполнитель принял задачу';
  exception when check_violation or insufficient_privilege then null; end;
end $$;

reset role;

-- ===== Постановщик =====
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
set local role authenticated;

do $$ begin
  assert (select count(*) from public.tasks) = 6, 'постановщик должен видеть все задачи';
  begin   -- возврат без комментария
    perform public.change_task_status('c0000000-0000-0000-0000-000000000003', 'rework', '   ');
    assert false, 'возврат без комментария прошёл';
  exception when check_violation then null; end;
  perform public.change_task_status('c0000000-0000-0000-0000-000000000003', 'rework', 'Переделать акт');
  assert (select count(*) from public.task_history where task_id = 'c0000000-0000-0000-0000-000000000003') = 4;
end $$;

do $$ declare n int; begin   -- историю не изменить и не удалить даже постановщику
  begin
    update public.task_history set comment = 'подделка';
    assert false, 'UPDATE истории прошёл';
  exception when insufficient_privilege then null; end;
  begin
    delete from public.task_history;
    assert false, 'DELETE истории прошёл';
  exception when insufficient_privilege then null; end;
end $$;

do $$ begin   -- роль в профиле поменять нельзя
  begin
    update public.profiles set role = 'manager';
    assert false, 'UPDATE profiles прошёл';
  exception when insufficient_privilege then null; end;
end $$;

reset role;

-- ===== Аноним =====
set local role anon;
do $$ begin
  begin
    perform count(*) from public.tasks;
    assert false, 'аноним прочитал задачи';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

rollback;
select 'Все проверки защиты пройдены' as result;
