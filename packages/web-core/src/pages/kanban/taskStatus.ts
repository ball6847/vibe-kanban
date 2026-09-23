import type { TaskStatus } from 'shared/types';

const ORDER: TaskStatus[] = ['todo', 'inprogress', 'inreview', 'done'];

/**
 * Mirrors `TaskStatus::can_transition_to` in `crates/db/src/models/task.rs`, which the
 * services use when the execution lifecycle moves a task along. The board applies the
 * same rules to manual moves so the UI cannot put a task somewhere the automation would
 * refuse to follow.
 */
export function canTransitionTaskStatus(
  from: TaskStatus,
  to: TaskStatus
): boolean {
  if (from === to) {
    return false;
  }

  if (to === 'cancelled') {
    return from !== 'cancelled';
  }

  if (from === 'cancelled' || from === 'done') {
    return false;
  }

  // Review can send work back for another pass.
  if (from === 'inreview' && to === 'inprogress') {
    return true;
  }

  return ORDER.indexOf(to) > ORDER.indexOf(from);
}

/** `done` and `cancelled` are the end of the line for automation. */
export function isTaskStatusTerminal(status: TaskStatus): boolean {
  return status === 'done' || status === 'cancelled';
}
