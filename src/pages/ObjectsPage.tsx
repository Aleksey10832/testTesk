import { useCallback, useEffect, useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '../auth/AuthContext';
import { friendlyError } from '../lib/status';
import { supabase } from '../lib/supabase';
import type { SiteObject } from '../lib/types';

export default function ObjectsPage() {
  const { profile } = useAuth();
  const isManager = profile?.role === 'manager';
  const [objects, setObjects] = useState<SiteObject[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [name, setName] = useState('');
  const [address, setAddress] = useState('');

  const load = useCallback(async () => {
    const { data, error } = await supabase
      .from('objects')
      .select('id, name, address, created_at')
      .order('created_at', { ascending: false });
    if (error) setError(friendlyError(error));
    else setObjects(data as SiteObject[]);
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function onCreate(e: FormEvent) {
    e.preventDefault();
    setError(null);
    const { error } = await supabase.from('objects').insert({ name: name.trim(), address: address.trim() });
    if (error) {
      setError(friendlyError(error));
      return;
    }
    setName('');
    setAddress('');
    await load();
  }

  return (
    <>
      <h1>Объекты</h1>
      {error && <p className="error">{error}</p>}

      {isManager && (
        <form className="card inline-form" onSubmit={(e) => void onCreate(e)}>
          <h3>Новый объект</h3>
          <input placeholder="Название" value={name} onChange={(e) => setName(e.target.value)} required />
          <input placeholder="Адрес" value={address} onChange={(e) => setAddress(e.target.value)} />
          <button className="primary" type="submit">Создать объект</button>
        </form>
      )}

      {objects === null ? (
        <p className="muted">Загрузка…</p>
      ) : objects.length === 0 ? (
        <p className="muted">
          {isManager ? 'Объектов пока нет. Создайте первый выше.' : 'У вас пока нет задач ни на одном объекте.'}
        </p>
      ) : (
        <ul className="list">
          {objects.map((o) => (
            <li key={o.id}>
              <Link to={`/objects/${o.id}`}>
                <strong>{o.name}</strong>
                <span className="muted">{o.address || 'адрес не указан'}</span>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
