import type { ReactNode } from 'react';
import { NavLink } from 'react-router-dom';
import { useAuth } from '../auth/AuthContext';

export default function Layout({ children }: { children: ReactNode }) {
  const { profile, signOut } = useAuth();
  if (!profile) return null;

  return (
    <>
      <header className="topbar">
        <nav>
          <NavLink to="/" end>Объекты</NavLink>
          {profile.role === 'executor' && <NavLink to="/my-tasks">Мои задачи</NavLink>}
        </nav>
        <div className="user">
          <span>
            {profile.full_name || profile.email}
            <small className="muted"> · {profile.role === 'manager' ? 'постановщик' : 'исполнитель'}</small>
          </span>
          <button className="link" onClick={() => void signOut()}>Выйти</button>
        </div>
      </header>
      <main className="container">{children}</main>
    </>
  );
}
