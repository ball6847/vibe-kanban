import type { Task, TaskStatus } from 'shared/types';

export interface TaskFilters {
  text: string;
  status: TaskStatus | 'all';
}

export const EMPTY_TASK_FILTERS: TaskFilters = { text: '', status: 'all' };

function matchesText(task: Task, text: string): boolean {
  const needle = text.trim().toLowerCase();
  if (!needle) {
    return true;
  }

  return `${task.title}\n${task.description ?? ''}`
    .toLowerCase()
    .includes(needle);
}

/**
 * The board's filter: free text over a task's title and description, plus an
 * explicit status. Kept pure so the matching rules are unit tested rather than
 * inferred from the rendered cards.
 */
export function matchesTaskFilters(task: Task, filters: TaskFilters): boolean {
  if (filters.status !== 'all' && task.status !== filters.status) {
    return false;
  }

  return matchesText(task, filters.text);
}

export function filterTasks(tasks: Task[], filters: TaskFilters): Task[] {
  return tasks.filter((task) => matchesTaskFilters(task, filters));
}

export function isFiltering(filters: TaskFilters): boolean {
  return filters.text.trim().length > 0 || filters.status !== 'all';
}
