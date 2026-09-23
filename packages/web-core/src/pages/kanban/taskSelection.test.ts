import { describe, expect, it } from 'vitest';
import type { Task } from 'shared/types';
import {
  pruneSelection,
  selectAll,
  selectedTasks,
  toggleSelection,
} from './taskSelection';

function makeTask(id: string): Task {
  return {
    id,
    project_id: 'project',
    title: `task ${id}`,
    description: '',
    status: 'todo',
    parent_workspace_id: null,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
  };
}

const tasks = [makeTask('a'), makeTask('b'), makeTask('c')];

describe('toggleSelection', () => {
  it('adds an id that is not selected and removes one that is', () => {
    expect(toggleSelection([], 'a')).toEqual(['a']);
    expect(toggleSelection(['a'], 'a')).toEqual([]);
    expect(toggleSelection(['a'], 'b')).toEqual(['a', 'b']);
  });
});

describe('selectAll', () => {
  it('selects every task, and clears once they are all selected', () => {
    expect(selectAll([], tasks)).toEqual(['a', 'b', 'c']);
    expect(selectAll(['a'], tasks)).toEqual(['a', 'b', 'c']);
    expect(selectAll(['a', 'b', 'c'], tasks)).toEqual([]);
  });

  it('does nothing for an empty board', () => {
    expect(selectAll(['a'], [])).toEqual([]);
  });
});

describe('selectedTasks', () => {
  it('returns the selected tasks in board order', () => {
    expect(selectedTasks(tasks, ['c', 'a']).map((task) => task.id)).toEqual([
      'a',
      'c',
    ]);
  });

  it('ignores ids that are not on the board', () => {
    expect(selectedTasks(tasks, ['zzz'])).toEqual([]);
  });
});

describe('pruneSelection', () => {
  it('drops ids whose task disappeared', () => {
    expect(pruneSelection(['a', 'gone'], tasks)).toEqual(['a']);
  });

  it('keeps the selection intact when every task still exists', () => {
    expect(pruneSelection(['a', 'b'], tasks)).toEqual(['a', 'b']);
  });
});
