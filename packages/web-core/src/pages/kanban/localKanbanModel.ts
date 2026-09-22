import type { Task, TaskStatus } from 'shared/types';

export const COLUMNS: { status: TaskStatus[]; label: string }[] = [
  { status: ['todo'], label: 'Todo' },
  { status: ['inprogress'], label: 'In Progress' },
  { status: ['inreview'], label: 'In Review' },
  // Cancelled folds into Done: single-user local board has no archive view.
  { status: ['done', 'cancelled'], label: 'Done' },
];

export const COLUMN_ORDER: TaskStatus[] = [
  'todo',
  'inprogress',
  'inreview',
  'done',
];

export const STATUS_LABEL: Record<TaskStatus, string> = {
  todo: 'Todo',
  inprogress: 'In Progress',
  inreview: 'In Review',
  done: 'Done',
  cancelled: 'Done',
};

export function groupTasksByColumn(tasks: Task[]): Map<TaskStatus, Task[]> {
  const map = new Map<TaskStatus, Task[]>();
  for (const task of tasks) {
    const list = map.get(task.status) ?? [];
    list.push(task);
    map.set(task.status, list);
  }
  return map;
}

/** Step a task status forward/backward along COLUMN_ORDER. */
export function stepStatus(
  status: TaskStatus,
  direction: -1 | 1
): TaskStatus | undefined {
  const normalized = status === 'cancelled' ? 'done' : status;
  return COLUMN_ORDER[COLUMN_ORDER.indexOf(normalized) + direction];
}
