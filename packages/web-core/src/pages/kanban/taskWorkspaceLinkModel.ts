import type { Workspace } from 'shared/types';

/**
 * Groups workspaces by the task they were started from. Workspaces without a
 * task link (PR-created, plain create-flow) are skipped, and each task's list
 * is newest first so the most recent workspace is the first thing offered.
 */
export function groupWorkspacesByTaskId(
  workspaces: Workspace[]
): Map<string, Workspace[]> {
  const grouped = new Map<string, Workspace[]>();

  for (const workspace of workspaces) {
    const taskId = workspace.task_id;
    if (!taskId) {
      continue;
    }

    const existing = grouped.get(taskId);
    if (existing) {
      existing.push(workspace);
    } else {
      grouped.set(taskId, [workspace]);
    }
  }

  for (const [taskId, list] of grouped) {
    grouped.set(
      taskId,
      [...list].sort(
        (a, b) => Date.parse(b.created_at) - Date.parse(a.created_at)
      )
    );
  }

  return grouped;
}

/** Workspaces linked to one task, newest first (empty when there are none). */
export function workspacesForTask(
  workspaces: Workspace[],
  taskId: string
): Workspace[] {
  return groupWorkspacesByTaskId(workspaces).get(taskId) ?? [];
}
