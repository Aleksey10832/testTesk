# Мини-CRM «Объекты и задачи»

React + TypeScript (Vite) + Supabase (Postgres, Auth, RLS).
Руководитель (постановщик) ставит задачи по объектам, исполнители берут их в работу и сдают на проверку.

## Запуск

### 1. База (Supabase)
1. Создайте проект на supabase.com (бесплатный тариф подходит).
2. **Authentication → Providers → Email:** выключите **«Allow new users to sign up»** (открытая регистрация должна быть отключена).
3. Выполните в **SQL Editor** по порядку содержимое файлов
   (или `supabase db push`, если используете Supabase CLI):
   - `supabase/migrations/20261106000001_schema.sql`
   - `supabase/migrations/20261106000002_rls_and_grants.sql`
   - `supabase/seed.sql` — тестовые пользователи, 3 объекта, 6 задач в разных статусах
4. (Необязательно) `supabase/tests/rls_checks.sql` — набор проверок защиты, выполняется в транзакции с откатом.

### 2. Фронтенд
```bash
cp .env.example .env     # впишите Project URL и anon public key (Settings → API)
npm install
npm run dev              # http://localhost:5173
npm run build            # сборка (tsc + vite)
```
Деплой на Vercel/Netlify: в переменных окружения задайте `VITE_SUPABASE_URL` и `VITE_SUPABASE_ANON_KEY`;
для Vercel уже есть `vercel.json` (SPA-маршрутизация).

## Тестовые пользователи (пароль у всех `Test1234!`)
| Email | Роль |
|---|---|
| manager1@example.com, manager2@example.com | постановщик |
| executor1@example.com, executor2@example.com | исполнитель |

Новый пользователь: Authentication → Users → Add user (получит роль «исполнитель»).
Сделать постановщиком: `update public.profiles set role = 'manager' where email = '...';`

## Как устроена защита (кратко)
- **RLS включён на всех таблицах**, плюс отдельный слой `GRANT` по колонкам: у клиентов нет права менять `tasks.status`, роль в `profiles`, писать в `task_history`.
- **Статус меняется только функцией `change_task_status`** (`security definer`): она проверяет роль, назначение, допустимость перехода по таблице из ТЗ, обязательный комментарий при возврате на доработку и в той же транзакции пишет историю.
- **История** доступна только на чтение; запись — только из триггера и этой функции.
- Роль берётся из таблицы `profiles` (а не из данных, которые пользователь может править сам).
- Во фронтенде и репозитории только `anon`-ключ (он публичный по дизайну). `service_role` нигде не используется; `.env` в `.gitignore`.

## Структура
```
supabase/migrations/   схема, триггеры, RPC, RLS и права
supabase/seed.sql      тестовые данные
supabase/tests/        SQL-проверки защиты
src/lib/status.ts      подписи статусов и логика показа кнопок (зеркало правил базы)
src/pages/             экраны: вход, объекты, объект, задача, «Мои задачи»
EXPLANATION.md         объяснение для руководителя-непрограммиста
DECISIONS.md           решения, допущения, что не сделано
```
