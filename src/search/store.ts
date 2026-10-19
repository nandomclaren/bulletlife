// Whether the search dialog is open (⌘K or the Index search button).
import { useSyncExternalStore } from 'react';

let open = false;
const listeners = new Set<() => void>();
const set = (v: boolean) => {
  open = v;
  listeners.forEach((l) => l());
};
export const openSearch = () => set(true);
export const closeSearch = () => set(false);
export const useSearchOpen = () =>
  useSyncExternalStore(
    (cb) => {
      listeners.add(cb);
      return () => listeners.delete(cb);
    },
    () => open,
  );
