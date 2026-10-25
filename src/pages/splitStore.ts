// What sits beside the main page on a wide screen (Mac, iPad in landscape):
// - the second page: any page, navigated on its own (remembered on this device);
// - the two-page spread: the period after the main one, like an open notebook.
// Only one at a time: turning one on turns the other off.
import { useSyncExternalStore } from 'react';

const KEY = 'split.path';
const read = () => {
  try {
    return localStorage.getItem(KEY) || '/index';
  } catch {
    return '/index';
  }
};

// The spread is a way of looking at the notebook, so it stays on until turned off.
const SPREAD_KEY = 'split.spread';
const readSpread = () => {
  try {
    return localStorage.getItem(SPREAD_KEY) === '1';
  } catch {
    return false;
  }
};

let state = { open: false, spread: readSpread(), path: read() };
const listeners = new Set<() => void>();
const set = (next: typeof state) => {
  if (next.spread !== state.spread)
    try {
      localStorage.setItem(SPREAD_KEY, next.spread ? '1' : '0');
    } catch {
      // remembered for this session only
    }
  state = next;
  listeners.forEach((l) => l());
};

export const getSplit = () => state;
export const toggleSplit = () => set({ ...state, open: !state.open, spread: false });
export const toggleSpread = () => set({ ...state, spread: !state.spread, open: false });
export const closeSplit = () => set({ ...state, open: false });
export const setSplitPath = (path: string) => {
  try {
    localStorage.setItem(KEY, path);
  } catch {
    // remembered for this session only
  }
  set({ ...state, path });
};

/** Opens the second page at a path (e.g. an open item's page, from the panel). */
export const openSplitAt = (path: string) => {
  setSplitPath(path);
  set({ ...state, open: true, spread: false });
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
