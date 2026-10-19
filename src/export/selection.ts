// The last selection made in an editor, kept as whole lines (with collapsed
// children). Stored on every change because tapping "…" on iOS clears the
// native selection before the menu can read it (CLAUDE.md 7).
import { useSyncExternalStore } from 'react';
import type { Line } from '../editor/lines';

let current: Line[] | null = null;
const listeners = new Set<() => void>();
const emit = () => listeners.forEach((l) => l());

export function setSelection(lines: Line[] | null) {
  if (current === lines || (!current && !lines)) return;
  current = lines && lines.length ? lines : null;
  emit();
}

export function getSelection(): Line[] | null {
  return current;
}

export function useStoredSelection(): Line[] | null {
  return useSyncExternalStore(
    (cb) => {
      listeners.add(cb);
      return () => listeners.delete(cb);
    },
    () => current,
  );
}
