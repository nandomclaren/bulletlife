// Minimal history router for the spike: real URLs so the system back gesture
// and scroll restoration can be tested in the installed app.
import { useSyncExternalStore } from 'react';

const base = import.meta.env.BASE_URL.replace(/\/$/, '');

function currentPath() {
  const p = location.pathname.startsWith(base) ? location.pathname.slice(base.length) : location.pathname;
  return p || '/';
}

const listeners = new Set<() => void>();
window.addEventListener('popstate', () => listeners.forEach((l) => l()));

export function navigate(path: string) {
  history.replaceState({ ...history.state, scrollY: window.scrollY }, '');
  history.pushState({ scrollY: 0 }, '', base + path);
  listeners.forEach((l) => l());
  window.scrollTo(0, 0);
}

export function usePath() {
  return useSyncExternalStore(
    (cb) => {
      listeners.add(cb);
      return () => listeners.delete(cb);
    },
    currentPath,
  );
}

// Restore our own saved scroll after the page for the popped route renders.
export function restoreScroll() {
  const y = (history.state as { scrollY?: number } | null)?.scrollY ?? 0;
  requestAnimationFrame(() => window.scrollTo(0, y));
}

if ('scrollRestoration' in history) history.scrollRestoration = 'manual';
