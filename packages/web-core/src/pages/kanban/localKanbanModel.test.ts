import { describe, it, expect } from 'vitest';
import type { Task } from 'shared/types';
import { COLUMNS, groupTasksByColumn, stepStatus } from './localKanbanModel';

function makeTask(id: string, status: Task['status'], title = id): Task {
  return {
    id,
    project_id: 'project-1',
    title,
    description: null,
    status,
    parent_workspace_id: null,
    created_at: '2026-01-01T00:00:00.000Z',
    updated_at: '2026-01-01T00:00:00.000Z',
  } as Task;
}

describe('localKanbanModel', () => {
  it('exposes exactly four columns with stable labels', () => {
    expect(COLUMNS.map((c) => c.label)).toEqual([
      'Todo',
      'In Progress',
      'In Review',
      'Done',
    ]);
  });

  it('groups tasks by status, preserving order', () => {
    const tasks = [
      makeTask('a', 'todo'),
      makeTask('b', 'inprogress'),
      makeTask('c', 'todo'),
      makeTask('d', 'cancelled'),
    ];
    const grouped = groupTasksByColumn(tasks);
    expect(grouped.get('todo')?.map((t) => t.id)).toEqual(['a', 'c']);
    expect(grouped.get('inprogress')?.map((t) => t.id)).toEqual(['b']);
    expect(grouped.get('cancelled')?.map((t) => t.id)).toEqual(['d']);
    expect(grouped.get('done')).toBeUndefined();
  });

  it('steps statuses forward and backward, stopping at the ends', () => {
    expect(stepStatus('todo', 1)).toBe('inprogress');
    expect(stepStatus('inreview', 1)).toBe('done');
    expect(stepStatus('done', 1)).toBeUndefined();
    expect(stepStatus('todo', -1)).toBeUndefined();
    expect(stepStatus('inprogress', -1)).toBe('todo');
  });

  it('treats cancelled as done when stepping', () => {
    expect(stepStatus('cancelled', -1)).toBe('inreview');
    expect(stepStatus('cancelled', 1)).toBeUndefined();
  });
});
