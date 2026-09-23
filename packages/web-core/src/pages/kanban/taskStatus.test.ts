import { describe, expect, it } from 'vitest';
import { canTransitionTaskStatus, isTaskStatusTerminal } from './taskStatus';

describe('canTransitionTaskStatus', () => {
  it('moves a task forward', () => {
    expect(canTransitionTaskStatus('todo', 'inprogress')).toBe(true);
    expect(canTransitionTaskStatus('todo', 'inreview')).toBe(true);
    expect(canTransitionTaskStatus('inprogress', 'inreview')).toBe(true);
    expect(canTransitionTaskStatus('inprogress', 'done')).toBe(true);
    expect(canTransitionTaskStatus('inreview', 'done')).toBe(true);
  });

  it('sends review back for another pass', () => {
    expect(canTransitionTaskStatus('inreview', 'inprogress')).toBe(true);
  });

  it('never walks a task back', () => {
    expect(canTransitionTaskStatus('inprogress', 'todo')).toBe(false);
    expect(canTransitionTaskStatus('inreview', 'todo')).toBe(false);
    expect(canTransitionTaskStatus('done', 'inreview')).toBe(false);
    expect(canTransitionTaskStatus('done', 'done')).toBe(false);
    expect(canTransitionTaskStatus('todo', 'todo')).toBe(false);
  });

  it('treats done and cancelled as terminal', () => {
    expect(canTransitionTaskStatus('todo', 'cancelled')).toBe(true);
    expect(canTransitionTaskStatus('inreview', 'cancelled')).toBe(true);
    expect(canTransitionTaskStatus('cancelled', 'todo')).toBe(false);
    expect(canTransitionTaskStatus('cancelled', 'inprogress')).toBe(false);
    expect(isTaskStatusTerminal('cancelled')).toBe(true);
    expect(isTaskStatusTerminal('done')).toBe(true);
    expect(isTaskStatusTerminal('inprogress')).toBe(false);
  });
});
