// Whether the Open items panel is open, and with which filter. Kept outside
// the router so the panel stays open beside the page while navigating (Mac).
import { useSyncExternalStore } from 'react';

export type PanelFilter = 'all' | 'today';
export interface PanelState {
  open: boolean;
  filter: PanelFilter;
}

let state: PanelState = { open: false, filter: 'all' };
const listeners = new Set<() => void>();
const set = (next: PanelState) => {
  state = next;
  listeners.forEach((l) => l());
};

export const openPanel = (filter: PanelFilter = 'all') => set({ open: true, filter });
export const closePanel = () => set({ ...state, open: false });
export const togglePanel = () => (state.open ? closePanel() : openPanel());
export const setPanelFilter = (filter: PanelFilter) => set({ ...state, filter });

export function usePanel(): PanelState {
  return useSyncExternalStore(
    (cb) => {
      listeners.add(cb);
      return () => listeners.delete(cb);
    },
    () => state,
  );
}
