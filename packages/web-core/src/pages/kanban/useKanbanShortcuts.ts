import { useEffect } from 'react';

export type KanbanShortcutAction = 'close-panel' | 'new-task' | 'focus-filter';

interface ShortcutEvent {
  key: string;
  altKey?: boolean;
  ctrlKey?: boolean;
  metaKey?: boolean;
  target?: EventTarget | null;
}

/** Typing in a field or editor means the keystroke belongs to that field. */
export function isTypingTarget(
  target: EventTarget | null | undefined
): boolean {
  const element = target as HTMLElement | null;
  if (!element || typeof element.tagName !== 'string') {
    return false;
  }

  if (element.isContentEditable) {
    return true;
  }

  return ['INPUT', 'TEXTAREA', 'SELECT'].includes(element.tagName);
}

/**
 * Pure key mapping, so the board's shortcuts are unit tested instead of only observed
 * in a browser. Modified keystrokes are left to the browser and the single-letter
 * shortcuts are ignored while the user is typing.
 */
export function resolveKanbanShortcut(
  event: ShortcutEvent
): KanbanShortcutAction | null {
  if (event.altKey || event.ctrlKey || event.metaKey) {
    return null;
  }

  if (event.key === 'Escape') {
    return 'close-panel';
  }

  if (isTypingTarget(event.target)) {
    return null;
  }

  if (event.key === 'c' || event.key === 'C') {
    return 'new-task';
  }

  if (event.key === '/') {
    return 'focus-filter';
  }

  return null;
}

export interface KanbanShortcutHandlers {
  onClosePanel: () => void;
  onFocusNewTask: () => void;
  onFocusFilter: () => void;
}

/** Board-level shortcuts: Escape closes the task panel, `c` starts a task, `/` filters. */
export function useKanbanShortcuts(handlers: KanbanShortcutHandlers): void {
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const action = resolveKanbanShortcut(event);
      if (!action) {
        return;
      }

      if (action === 'close-panel') {
        handlers.onClosePanel();
        return;
      }

      event.preventDefault();
      if (action === 'new-task') {
        handlers.onFocusNewTask();
      } else {
        handlers.onFocusFilter();
      }
    };

    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [handlers]);
}
