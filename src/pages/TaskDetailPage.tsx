import { useCallback, useEffect, useState, type FormEvent } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { useAuth } from '../auth/AuthContext';
import StatusBadge from '../components/StatusBadge';
import {
  availableActions,
  formatDate,
  friendlyError,
  personName,
  STATUS_LABEL,
  type StatusAction,
} from '../lib/status';
import { supabase } from '../lib/supabase';
import type { HistoryItem, TaskWithRefs } from '../lib/types';

interface Executor {
  id: string;
  full_name: string;
  email: string;
}

export default function TaskDetailPage() {
  const { id = '' } = useParams();
  const { profile } = useAuth();
  const navigate = useNavigate();
  const isManager = profile?.role === 'manager';

  const [task, setTask] = useState<TaskWithRefs | null | undefined>(undefined);
  const [history, setHistory] = useState<HistoryItem[]>([]);
  const [executors, setExecutors] = useState<Executor[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [comment, setComment] = useState('');
  const [busy, setBusy] = useState(false);

  const [editing, setEditing] = useState(false);
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [assignee, setAssignee] = useState('');

  const load = useCallback(async () => {
    const t = await supabase
      .from('tasks')
      .select(
        '*, object:objects(id, name), assignee:profiles!tasks_assignee_id_fkey(full_name, email), author:profiles!tasks_author_id_fkey(full_name, email)',
      )
      .eq('id', id)
      .maybeSingle();
    if (t.error) {
      setError(friendlyError(t.error));
      setTask(null);
      return;
    }
    setTask(t.data as unknown as TaskWithRefs | null);
    if (!t.data) return;

    const h = await supabase
      .from('task_history')
      .select('id, task_id, from_status, to_status, comment, created_at, changer:profiles!task_history_changed_by_fkey(full_name, email)')
      .eq('task_id', id)
      .order('created_at', { ascending: true })
      .order('id', { ascending: true });
    if (h.error) setError(friendlyError(h.error));
    else setHistory(h.data as unknown as HistoryItem[]);
  }, [id]);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    if (!isManager) return;
    void supabase
      .from('profiles')
      .select('id, full_name, email')
      .eq('role', 'executor')
      .order('full_name')
      .then(({ data }) => setExecutors((data as Executor[] | null) ?? []));
  }, [isManager]);

  async function runAction(action: StatusAction) {
    setBusy(true);
    setError(null);
    // Допустимость перехода окончательно проверяет база; интерфейс лишь не показывает лишние кнопки.
    const { error } = await supabase.rpc('change_task_status', {
      p_task_id: id,
      p_to: action.to,
      p_comment: comment.trim() || null,
    });
    setBusy(false);
    if (error) return setError(friendlyError(error));
    setComment('');
    await load();
  }

  async function onSaveEdit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    const { error } = await supabase
      .from('tasks')
      .update({ title: title.trim(), description: description.trim(), assignee_id: assignee })
      .eq('id', id);
    if (error) return setError(friendlyError(error));
    setEditing(false);
    await load();
  }

  async function onDelete() {
    if (!task || !confirm('Удалить задачу вместе с её историей?')) return;
    const { error } = await supabase.from('tasks').delete().eq('id', id);
    if (error) return setError(friendlyError(error));
    navigate(`/objects/${task.object_id}`);
  }

  if (task === undefined) return <p className="muted">Загрузка…</p>;
  if (task === null || !profile) {
    return (
      <>
        <p className="error">{error ?? 'Задача не найдена или у вас нет к ней доступа.'}</p>
        <Link to="/">← К объектам</Link>
      </>
    );
  }

  const actions = availableActions(task, profile);

  return (
    <>
      <p>
        {profile.role === 'executor' ? <Link to="/my-tasks">← Мои задачи</Link> : null}{' '}
        {task.object && <Link to={`/objects/${task.object.id}`}>Объект: {task.object.name}</Link>}
      </p>

      {editing ? (
        <form className="card stack" onSubmit={(e) => void onSaveEdit(e)}>
          <input value={title} onChange={(e) => setTitle(e.target.value)} required />
          <textarea rows={4} value={description} onChange={(e) => setDescription(e.target.value)} />
          <select value={assignee} onChange={(e) => setAssignee(e.target.value)} required>
            {executors.map((x) => (
              <option key={x.id} value={x.id}>{x.full_name || x.email}</option>
            ))}
          </select>
          <div className="actions">
            <button className="primary" type="submit">Сохранить</button>
            <button type="button" onClick={() => setEditing(false)}>Отмена</button>
          </div>
        </form>
      ) : (
        <div className="card">
          <div className="head">
            <h1>{task.title}</h1>
            <StatusBadge status={task.status} />
          </div>
          <p className="pre">{task.description || <span className="muted">Описание не указано</span>}</p>
          <dl className="meta">
            <dt>Объект</dt><dd>{task.object?.name ?? '—'}</dd>
            <dt>Исполнитель</dt><dd>{personName(task.assignee)}</dd>
            <dt>Автор</dt><dd>{personName(task.author)}</dd>
            <dt>Создана</dt><dd>{formatDate(task.created_at)}</dd>
          </dl>
          {isManager && (
            <div className="actions">
              <button
                onClick={() => {
                  setTitle(task.title);
                  setDescription(task.description);
                  setAssignee(task.assignee_id);
                  setEditing(true);
                }}
              >
                Изменить
              </button>
              <button className="danger" onClick={() => void onDelete()}>Удалить</button>
            </div>
          )}
        </div>
      )}

      {error && <p className="error">{error}</p>}

      {actions.length > 0 && (
        <div className="card stack">
          <h3>Действия</h3>
          <textarea
            rows={2}
            placeholder={
              actions.some((a) => a.commentRequired)
                ? 'Комментарий (обязателен при возврате на доработку)'
                : 'Комментарий (необязательно)'
            }
            value={comment}
            onChange={(e) => setComment(e.target.value)}
          />
          <div className="actions">
            {actions.map((a) => (
              <button
                key={a.to}
                className={a.tone === 'default' ? undefined : a.tone}
                disabled={busy || (a.commentRequired && !comment.trim())}
                onClick={() => void runAction(a)}
              >
                {a.label}
              </button>
            ))}
          </div>
        </div>
      )}

      <h2>История</h2>
      <ol className="history">
        {history.map((h) => (
          <li key={h.id}>
            <div>
              <strong>{h.from_status ? STATUS_LABEL[h.from_status] : '—'}</strong>
              {' → '}
              <strong>{STATUS_LABEL[h.to_status]}</strong>
            </div>
            <div className="muted">
              {personName(h.changer)} · {formatDate(h.created_at)}
            </div>
            {h.comment && <div className="comment pre">{h.comment}</div>}
          </li>
        ))}
      </ol>
    </>
  );
}
