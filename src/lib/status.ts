import type { PersonRef, Profile, Task, TaskStatus } from './types';

export const STATUS_LABEL: Record<TaskStatus, string> = {
  new: 'Новая',
  in_progress: 'В работе',
  review: 'На проверке',
  rework: 'На доработке',
  accepted: 'Принята',
};

export interface StatusAction {
  to: TaskStatus;
  label: string;
  commentRequired: boolean;
  tone: 'primary' | 'danger' | 'default';
}

/**
 * Какие кнопки показать пользователю. Это ТОЛЬКО удобство интерфейса:
 * реальные правила проверяет база (функция change_task_status),
 * и они полностью повторяют таблицу переходов из ТЗ.
 */
export function availableActions(
  task: Pick<Task, 'status' | 'assignee_id'>,
  user: Profile,
): StatusAction[] {
  const isAssignee = user.role === 'executor' && task.assignee_id === user.id;
  const isManager = user.role === 'manager';

  switch (task.status) {
    case 'new':
      return isAssignee
        ? [{ to: 'in_progress', label: 'Взять в работу', commentRequired: false, tone: 'primary' }]
        : [];
    case 'in_progress':
      return isAssignee
        ? [{ to: 'review', label: 'Отправить на проверку', commentRequired: false, tone: 'primary' }]
        : [];
    case 'review':
      return isManager
        ? [
            { to: 'accepted', label: 'Принять', commentRequired: false, tone: 'primary' },
            { to: 'rework', label: 'Вернуть на доработку', commentRequired: true, tone: 'danger' },
          ]
        : [];
    case 'rework':
      return isAssignee
        ? [{ to: 'in_progress', label: 'Вернуть в работу', commentRequired: false, tone: 'primary' }]
        : [];
    case 'accepted':
      return [];
  }
}

export function personName(p: PersonRef | null | undefined): string {
  if (!p) return '—';
  return p.full_name || p.email;
}

export function formatDate(iso: string): string {
  return new Date(iso).toLocaleString('ru-RU', { dateStyle: 'short', timeStyle: 'short' });
}

/** Понятное сообщение вместо технических кодов Postgres/PostgREST. */
export function friendlyError(err: { message: string; code?: string }): string {
  if (err.code === '23503') return 'Нельзя удалить: с этой записью связаны другие данные (например, задачи объекта).';
  if (err.code === '42501') return 'Недостаточно прав для этого действия.';
  return err.message;
}
