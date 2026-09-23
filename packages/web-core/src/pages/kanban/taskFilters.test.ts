import { describe, expect, it } from 'vitest';
import type { Task } from 'shared/types';
import {
  EMPTY_TASK_FILTERS,
  filterTasks,
  isFiltering,
  matchesTaskFilters,
} from './taskFilters';

function makeTask(
  id: string,
  title: string,
  description = '',
  status: Task['status'] = 'todo'
): Task {
  return {
    id,
    project_id: 'project',
    title,
    description,
    status,
    parent_workspace_id: null,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
  };
}

const tasks = [
  makeTask('t1', 'Add filters to the board', 'text search'),
  makeTask('t2', 'Fix the rail highlight', '', 'inprogress'),
  makeTask('t3', 'Restore the task panel', 'detail view', 'inreview'),
];

describe('filterTasks', () => {
  it('returns everything when nothing is filtered', () => {
    expect(filterTasks(tasks, EMPTY_TASK_FILTERS).map((t) => t.id)).toEqual([
      't1',
      't2',
      't3',
    ]);
  });

  it('matches the title case-insensitively and ignores padding', () => {
    expect(
      filterTasks(tasks, { ...EMPTY_TASK_FILTERS, text: '  RAIL ' }).map(
        (t) => t.id
      )
    ).toEqual(['t2']);
  });

  it('matches the description', () => {
    expect(
      filterTasks(tasks, { ...EMPTY_TASK_FILTERS, text: 'detail view' }).map(
        (t) => t.id
      )
    ).toEqual(['t3']);
  });

  it('filters by status', () => {
    expect(
      filterTasks(tasks, { text: '', status: 'inprogress' }).map((t) => t.id)
    ).toEqual(['t2']);
  });

  it('applies text and status together', () => {
    expect(
      filterTasks(tasks, { text: 'task', status: 'inreview' }).map((t) => t.id)
    ).toEqual(['t3']);
  });

  it('returns nothing when no task matches', () => {
    expect(filterTasks(tasks, { ...EMPTY_TASK_FILTERS, text: 'nope' })).toEqual(
      []
    );
  });
});

describe('matchesTaskFilters', () => {
  it('does not match a task whose description is null', () => {
    const bare = makeTask('t4', 'bare', null as unknown as string);
    expect(
      matchesTaskFilters(bare, { ...EMPTY_TASK_FILTERS, text: 'bare' })
    ).toBe(true);
    expect(
      matchesTaskFilters(bare, { ...EMPTY_TASK_FILTERS, text: 'missing' })
    ).toBe(false);
  });
});

describe('isFiltering', () => {
  it('is false for blank text and the all status', () => {
    expect(isFiltering(EMPTY_TASK_FILTERS)).toBe(false);
    expect(isFiltering({ text: '   ', status: 'all' })).toBe(false);
    expect(isFiltering({ text: 'x', status: 'all' })).toBe(true);
    expect(isFiltering({ text: '', status: 'done' })).toBe(true);
  });
});
