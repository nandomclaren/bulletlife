// The split view: a second notebook page beside the main one (Mac). Which
// page it shows is remembered on this device.
import { useSyncExternalStore } from 'react';

const KEY = 'split.path';
const read = () => {
  try {
    return localStorage.getItem(KEY) || '/index';
  } catch {
    return '/index';
  }
};

let state = { open: false, path: read() };
const listeners = new Set<() => void>();
const set = (next: typeof state) => {
  state = next;
  listeners.forEach((l) => l());
};

export const toggleSplit = () => set({ ...state, open: !state.open });
export const closeSplit = () => set({ ...state, open: false });
export const setSplitPath = (path: string) => {
  try {
    localStorage.setItem(KEY, path);
  } catch {
    // remembered for this session only
  }
  set({ ...state, path });
};

export function useSplit() {
  return useSyncExternalStore(
    (cb) => {
      listeners.add(cb);
      return () => listeners.delete(cb);
    },
    () => state,
  );
}
