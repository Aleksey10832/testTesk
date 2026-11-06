import { Navigate, Route, Routes } from 'react-router-dom';
import { useAuth } from './auth/AuthContext';
import Layout from './components/Layout';
import LoginPage from './pages/LoginPage';
import ObjectsPage from './pages/ObjectsPage';
import ObjectDetailPage from './pages/ObjectDetailPage';
import TaskDetailPage from './pages/TaskDetailPage';
import MyTasksPage from './pages/MyTasksPage';

export default function App() {
  const { session, profile, loading, signOut } = useAuth();

  if (loading) return <p className="center muted">Загрузка…</p>;
  if (!session) return <LoginPage />;

  if (!profile) {
    return (
      <div className="center">
        <h2>Профиль не найден</h2>
        <p className="muted">Для этой учётной записи нет профиля. Обратитесь к администратору.</p>
        <button onClick={() => void signOut()}>Выйти</button>
      </div>
    );
  }

  return (
    <Layout>
      <Routes>
        <Route path="/" element={<ObjectsPage />} />
        <Route path="/objects/:id" element={<ObjectDetailPage />} />
        <Route path="/tasks/:id" element={<TaskDetailPage />} />
        <Route
          path="/my-tasks"
          element={profile.role === 'executor' ? <MyTasksPage /> : <Navigate to="/" replace />}
        />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </Layout>
  );
}
