import { describe, expect, it } from 'vitest';
import type { Workspace } from 'shared/types';
import {
  groupWorkspacesByTaskId,
  workspacesForTask,
} from './taskWorkspaceLinkModel';

function makeWorkspace(
  id: string,
  taskId: string | null,
  createdAt = '2026-01-01T00:00:00Z'
): Workspace {
  return {
    id,
    task_id: taskId,
    container_ref: null,
    branch: `branch-${id}`,
    setup_completed_at: null,
    created_at: createdAt,
    updated_at: createdAt,
    archived: false,
    pinned: false,
    name: `workspace ${id}`,
    worktree_deleted: false,
  };
}

describe('groupWorkspacesByTaskId', () => {
  it('groups by task and ignores unlinked workspaces', () => {
    const grouped = groupWorkspacesByTaskId([
      makeWorkspace('w1', 't1'),
      makeWorkspace('w2', null),
      makeWorkspace('w3', 't1'),
      makeWorkspace('w4', 't2'),
    ]);

    expect([...grouped.keys()].sort()).toEqual(['t1', 't2']);
    expect(grouped.get('t1')?.map((w) => w.id)).toEqual(['w1', 'w3']);
    expect(grouped.get('t2')?.map((w) => w.id)).toEqual(['w4']);
  });

  it('returns an empty map for no workspaces', () => {
    expect(groupWorkspacesByTaskId([]).size).toBe(0);
  });

  it('orders each task newest first', () => {
    const grouped = groupWorkspacesByTaskId([
      makeWorkspace('old', 't1', '2026-01-01T00:00:00Z'),
      makeWorkspace('new', 't1', '2026-03-01T00:00:00Z'),
      makeWorkspace('middle', 't1', '2026-02-01T00:00:00Z'),
    ]);

    expect(grouped.get('t1')?.map((w) => w.id)).toEqual([
      'new',
      'middle',
      'old',
    ]);
  });
});

describe('workspacesForTask', () => {
  it('returns the linked workspaces for a task', () => {
    const workspaces = [
      makeWorkspace('w1', 't1', '2026-01-01T00:00:00Z'),
      makeWorkspace('w2', 't1', '2026-02-01T00:00:00Z'),
      makeWorkspace('w3', 't2'),
    ];

    expect(workspacesForTask(workspaces, 't1').map((w) => w.id)).toEqual([
      'w2',
      'w1',
    ]);
  });

  it('returns an empty list when the task has no workspace', () => {
    expect(workspacesForTask([makeWorkspace('w1', null)], 't1')).toEqual([]);
  });
});
