import type { Task } from 'shared/types';

/** Selected task ids, order irrelevant. Pure helpers so the rules are unit tested. */
export function toggleSelection(selected: string[], taskId: string): string[] {
  return selected.includes(taskId)
    ? selected.filter((id) => id !== taskId)
    : [...selected, taskId];
}

export function selectAll(selected: string[], tasks: Task[]): string[] {
  const everySelected =
    tasks.length > 0 && tasks.every((task) => selected.includes(task.id));

  return everySelected ? [] : tasks.map((task) => task.id);
}

/** The selected tasks that still exist, in board order. */
export function selectedTasks(tasks: Task[], selected: string[]): Task[] {
  return tasks.filter((task) => selected.includes(task.id));
}

/** Selections pointing at deleted tasks are dropped, so the bulk bar hides itself. */
export function pruneSelection(selected: string[], tasks: Task[]): string[] {
  return selected.filter((id) => tasks.some((task) => task.id === id));
}
