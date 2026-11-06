export type Role = 'manager' | 'executor';
export type TaskStatus = 'new' | 'in_progress' | 'review' | 'rework' | 'accepted';

export interface Profile {
  id: string;
  email: string;
  full_name: string;
  role: Role;
}

export interface SiteObject {
  id: string;
  name: string;
  address: string;
  created_at: string;
}

export interface PersonRef {
  full_name: string;
  email: string;
}

export interface Task {
  id: string;
  title: string;
  description: string;
  object_id: string;
  assignee_id: string;
  status: TaskStatus;
  author_id: string;
  created_at: string;
  updated_at: string;
}

export interface TaskWithRefs extends Task {
  assignee: PersonRef | null;
  author: PersonRef | null;
  object: { id: string; name: string } | null;
}

export interface HistoryItem {
  id: number;
  task_id: string;
  from_status: TaskStatus | null;
  to_status: TaskStatus;
  comment: string | null;
  created_at: string;
  changer: PersonRef | null;
}
