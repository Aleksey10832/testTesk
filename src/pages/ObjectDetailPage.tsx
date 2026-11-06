import { useCallback, useEffect, useState, type FormEvent } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { useAuth } from '../auth/AuthContext';
import StatusBadge from '../components/StatusBadge';
import { friendlyError, personName } from '../lib/status';
import { supabase } from '../lib/supabase';
import type { PersonRef, SiteObject, Task } from '../lib/types';

type TaskRow = Task & { assignee: PersonRef | null };
interface Executor {
  id: string;
  full_name: string;
  email: string;
}

export default function ObjectDetailPage() {
  const { id = '' } = useParams();
  const { profile } = useAuth();
  const navigate = useNavigate();
  const isManager = profile?.role === 'manager';

  const [obj, setObj] = useState<SiteObject | null | undefined>(undefined); // undefined — грузится
  const [tasks, setTasks] = useState<TaskRow[]>([]);
  const [executors, setExecutors] = useState<Executor[]>([]);
  const [error, setError] = useState<string | null>(null);

  const [editing, setEditing] = useState(false);
  const [name, setName] = useState('');
  const [address, setAddress] = useState('');

  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [assignee, setAssignee] = useState('');

  const load = useCallback(async () => {
    const o = await supabase.from('objects').select('id, name, address, created_at').eq('id', id).maybeSingle();
    if (o.error) {
      setError(friendlyError(o.error));
      setObj(null);
      return;
    }
    setObj(o.data as SiteObject | null);
    if (!o.data) return;

    const t = await supabase
      .from('tasks')
      .select('*, assignee:profiles!tasks_assignee_id_fkey(full_name, email)')
      .eq('object_id', id)
      .order('created_at', { ascending: false });
    if (t.error) setError(friendlyError(t.error));
    else setTasks(t.data as unknown as TaskRow[]);
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

  async function onSaveObject(e: FormEvent) {
    e.preventDefault();
    setError(null);
    const { error } = await supabase.from('objects').update({ name: name.trim(), address: address.trim() }).eq('id', id);
    if (error) return setError(friendlyError(error));
    setEditing(false);
    await load();
  }

  async function onDeleteObject() {
    if (!confirm('Удалить объект? Это возможно только если на нём нет задач.')) return;
    const { error } = await supabase.from('objects').delete().eq('id', id);
    if (error) return setError(friendlyError(error));
    navigate('/');
  }

  async function onCreateTask(e: FormEvent) {
    e.preventDefault();
    if (!profile) return;
    setError(null);
    const { error } = await supabase.from('tasks').insert({
      title: title.trim(),
      description: description.trim(),
      object_id: id,
      assignee_id: assignee,
      author_id: profile.id,
    });
    if (error) return setError(friendlyError(error));
    setTitle('');
    setDescription('');
    setAssignee('');
    await load();
  }

  if (obj === undefined) return <p className="muted">Загрузка…</p>;
  if (obj === null) {
    return (
      <>
        <p className="error">{error ?? 'Объект не найден или у вас нет к нему доступа.'}</p>
        <Link to="/">← К списку объектов</Link>
      </>
    );
  }

  return (
    <>
      <p><Link to="/">← Объекты</Link></p>

      {editing ? (
        <form className="card inline-form" onSubmit={(e) => void onSaveObject(e)}>
          <input value={name} onChange={(e) => setName(e.target.value)} required />
          <input value={address} onChange={(e) => setAddress(e.target.value)} placeholder="Адрес" />
          <button className="primary" type="submit">Сохранить</button>
          <button type="button" onClick={() => setEditing(false)}>Отмена</button>
        </form>
      ) : (
        <div className="head">
          <div>
            <h1>{obj.name}</h1>
            <p className="muted">{obj.address || 'адрес не указан'}</p>
          </div>
          {isManager && (
            <div className="actions">
              <button
                onClick={() => {
                  setName(obj.name);
                  setAddress(obj.address);
                  setEditing(true);
                }}
              >
                Изменить
              </button>
              <button className="danger" onClick={() => void onDeleteObject()}>Удалить</button>
            </div>
          )}
        </div>
      )}

      {error && <p className="error">{error}</p>}

      <h2>Задачи объекта</h2>
      {tasks.length === 0 ? (
        <p className="muted">На этом объекте пока нет задач.</p>
      ) : (
        <ul className="list">
          {tasks.map((t) => (
            <li key={t.id}>
              <Link to={`/tasks/${t.id}`}>
                <span>
                  <strong>{t.title}</strong>
                  <span className="muted"> — {personName(t.assignee)}</span>
                </span>
                <StatusBadge status={t.status} />
              </Link>
            </li>
          ))}
        </ul>
      )}

      {isManager && (
        <form className="card stack" onSubmit={(e) => void onCreateTask(e)}>
          <h3>Новая задача</h3>
          <input placeholder="Название" value={title} onChange={(e) => setTitle(e.target.value)} required />
          <textarea
            placeholder="Описание"
            rows={3}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
          />
          <select value={assignee} onChange={(e) => setAssignee(e.target.value)} required>
            <option value="">Выберите исполнителя…</option>
            {executors.map((x) => (
              <option key={x.id} value={x.id}>{x.full_name || x.email}</option>
            ))}
          </select>
          <button className="primary" type="submit">Создать задачу</button>
        </form>
      )}
    </>
  );
}
