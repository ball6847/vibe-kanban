import { describe, expect, it } from 'vitest';
import { isTypingTarget, resolveKanbanShortcut } from './useKanbanShortcuts';

const input = { tagName: 'INPUT' } as unknown as EventTarget;
const div = { tagName: 'DIV' } as unknown as EventTarget;

describe('resolveKanbanShortcut', () => {
  it('maps escape to closing the panel', () => {
    expect(resolveKanbanShortcut({ key: 'Escape' })).toBe('close-panel');
  });

  it('maps c and / to the new-task and filter actions', () => {
    expect(resolveKanbanShortcut({ key: 'c', target: div })).toBe('new-task');
    expect(resolveKanbanShortcut({ key: 'C', target: div })).toBe('new-task');
    expect(resolveKanbanShortcut({ key: '/', target: div })).toBe(
      'focus-filter'
    );
  });

  it('ignores single letters while typing', () => {
    expect(resolveKanbanShortcut({ key: 'c', target: input })).toBeNull();
    expect(resolveKanbanShortcut({ key: '/', target: input })).toBeNull();
    // Escape still closes even from a field.
    expect(resolveKanbanShortcut({ key: 'Escape', target: input })).toBe(
      'close-panel'
    );
  });

  it('leaves modified keystrokes alone', () => {
    expect(
      resolveKanbanShortcut({ key: 'c', ctrlKey: true, target: div })
    ).toBeNull();
    expect(
      resolveKanbanShortcut({ key: 'c', metaKey: true, target: div })
    ).toBeNull();
    expect(
      resolveKanbanShortcut({ key: '/', altKey: true, target: div })
    ).toBeNull();
  });

  it('ignores unrelated keys', () => {
    expect(resolveKanbanShortcut({ key: 'x', target: div })).toBeNull();
  });
});

describe('isTypingTarget', () => {
  it('recognises inputs, textareas, selects and contenteditable', () => {
    expect(isTypingTarget(input)).toBe(true);
    expect(
      isTypingTarget({ tagName: 'TEXTAREA' } as unknown as EventTarget)
    ).toBe(true);
    expect(
      isTypingTarget({ tagName: 'SELECT' } as unknown as EventTarget)
    ).toBe(true);
    expect(
      isTypingTarget({
        tagName: 'DIV',
        isContentEditable: true,
      } as unknown as EventTarget)
    ).toBe(true);
  });

  it('is false for plain elements and missing targets', () => {
    expect(isTypingTarget(div)).toBe(false);
    expect(isTypingTarget(null)).toBe(false);
  });
});
