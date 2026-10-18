// Minimal history router: real URLs so the system back gesture works in the
// installed app, deep links work, and scroll is restored on back.
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

export function replace(path: string) {
  history.replaceState({ scrollY: 0 }, '', base + path);
  listeners.forEach((l) => l());
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
// Pages load their entries a moment after they appear, so the page may not be
// tall enough yet: keep trying for a short while until the position is reached.
const RESTORE_MS = 800;

export function restoreScroll() {
  const y = (history.state as { scrollY?: number } | null)?.scrollY ?? 0;
  const until = performance.now() + RESTORE_MS;
  let userScrolled = false;
  const stop = () => (userScrolled = true);
  window.addEventListener('wheel', stop, { once: true, passive: true });
  window.addEventListener('touchmove', stop, { once: true, passive: true });
  const attempt = () => {
    if (userScrolled) return;
    window.scrollTo(0, y);
    if (Math.abs(window.scrollY - y) > 1 && performance.now() < until) requestAnimationFrame(attempt);
  };
  requestAnimationFrame(attempt);
}

if ('scrollRestoration' in history) history.scrollRestoration = 'manual';
