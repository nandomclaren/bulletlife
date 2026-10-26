// Pen mode on this device: whether it is on, and the pen's tool and color.
import { useSyncExternalStore } from 'react';
import type { InkColor } from './ink';

export type PenTool = 'write' | 'draw' | 'erase';

const read = (key: string, fallback: string) => {
  try {
    return localStorage.getItem(key) ?? fallback;
  } catch {
    return fallback;
  }
};
const write = (key: string, value: string) => {
  try {
    localStorage.setItem(key, value);
  } catch {
    // remembered for this session only
  }
};

let state = {
  on: read('pen.mode', 'type') === 'pen',
  tool: read('pen.tool', 'write') as PenTool,
  color: read('pen.color', 'ink') as InkColor,
};
const listeners = new Set<() => void>();
const set = (next: Partial<typeof state>) => {
  state = { ...state, ...next };
  write('pen.mode', state.on ? 'pen' : 'type');
  write('pen.tool', state.tool);
  write('pen.color', state.color);
  listeners.forEach((l) => l());
};

export const setPenMode = (on: boolean) => set({ on });
export const setPenTool = (tool: PenTool) => set({ tool });
export const setPenColor = (color: InkColor) => set({ color });

export function usePen() {
  return useSyncExternalStore(
    (cb) => {
      listeners.add(cb);
      return () => listeners.delete(cb);
    },
    () => state,
  );
}

// Pen mode is for a tablet with a pen: a touch screen big enough to write on (iPad, not iPhone).
// 'pen.force' = '1' in localStorage turns it on anywhere (testing on the Mac).
const TABLET = '(any-pointer: coarse) and (min-width: 700px) and (min-height: 600px)';
const subscribeMedia = (cb: () => void) => {
  const mq = matchMedia(TABLET);
  mq.addEventListener('change', cb);
  return () => mq.removeEventListener('change', cb);
};
export function usePenAvailable() {
  return useSyncExternalStore(subscribeMedia, () => matchMedia(TABLET).matches || read('pen.force', '') === '1');
}
