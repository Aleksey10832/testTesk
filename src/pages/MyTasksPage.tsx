import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '../auth/AuthContext';
import StatusBadge from '../components/StatusBadge';
import { friendlyError } from '../lib/status';
import { supabase } from '../lib/supabase';
import type { TaskStatus, TaskWithRefs } from '../lib/types';

// Сначала то, что требует действия исполнителя
const ORDER: TaskStatus[] = ['rework', 'new', 'in_progress', 'review', 'accepted'];

export default function MyTasksPage() {
  const { profile } = useAuth();
  const [tasks, setTasks] = useState<TaskWithRefs[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!profile) return;
    void supabase
      .from('tasks')
      .select('*, object:objects(id, name)')
      .eq('assignee_id', profile.id)
      .then(({ data, error }) => {
        if (error) setError(friendlyError(error));
        else {
          const list = data as unknown as TaskWithRefs[];
          list.sort((a, b) => ORDER.indexOf(a.status) - ORDER.indexOf(b.status));
          setTasks(list);
        }
      });
  }, [profile]);

  return (
    <>
      <h1>Мои задачи</h1>
      {error && <p className="error">{error}</p>}
      {tasks === null ? (
        <p className="muted">Загрузка…</p>
      ) : tasks.length === 0 ? (
        <p className="muted">Вам пока ничего не назначено.</p>
      ) : (
        <ul className="list">
          {tasks.map((t) => (
            <li key={t.id}>
              <Link to={`/tasks/${t.id}`}>
                <span>
                  <strong>{t.title}</strong>
                  <span className="muted"> — {t.object?.name ?? 'объект'}</span>
                </span>
                <StatusBadge status={t.status} />
              </Link>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
