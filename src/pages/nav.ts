// Level navigation (CLAUDE.md 5.1): an anchor date, the active levels, and
// the URL of each level for a date. Navigating never writes anything.
import { addDays, addMonths, addWeeks, monthOf, todayIso, weekKey, yearOf, type Weekday } from '../dates';
import type { Settings } from '../data/types';
import { navigate } from '../router';

export type Level = 'year' | 'month' | 'week' | 'day';

let anchor = todayIso();
export const getAnchor = () => anchor;
export const setAnchor = (iso: string) => {
  anchor = iso;
};

/** Keep the anchor if it lies in [start, end]; otherwise today if inside, else start. */
export function anchorWithin(start: string, end: string): string {
  if (anchor >= start && anchor <= end) return anchor;
  const today = todayIso();
  anchor = today >= start && today <= end ? today : start;
  return anchor;
}

export function activeLevels(s: Settings): Level[] {
  const levels: Level[] = ['year'];
  if (s.activeLogs.monthly) levels.push('month');
  if (s.activeLogs.weekly) levels.push('week');
  if (s.activeLogs.daily) levels.push('day');
  return levels;
}

export function finestLevel(s: Settings): Level {
  const l = activeLevels(s);
  return l[l.length - 1];
}

export function pathFor(level: Level, iso: string, firstDay: Weekday): string {
  switch (level) {
    case 'year':
      return `/year/${yearOf(iso)}`;
    case 'month':
      return `/month/${monthOf(iso)}`;
    case 'week':
      return `/week/${weekKey(iso, firstDay)}`;
    case 'day':
      return `/day/${iso}`;
  }
}

/** Key of the neighbouring period at the same level. */
export function stepKey(level: Level, key: string, n: number, firstDay: Weekday): string {
  switch (level) {
    case 'year':
      return String(Number(key) + n);
    case 'month':
      return addMonths(key, n);
    case 'week':
      return addWeeks(key, n, firstDay);
    case 'day':
      return addDays(key, n);
  }
}

/** Goes up a level and asks the destination to scroll to (and flash) where we came from. */
export function goUp(path: string, fromId: string) {
  try {
    sessionStorage.setItem('nav.from', fromId);
  } catch {
    // highlight is a nicety
  }
  navigate(path);
}

export function takeFrom(): string | null {
  try {
    const v = sessionStorage.getItem('nav.from');
    sessionStorage.removeItem('nav.from');
    return v;
  } catch {
    return null;
  }
}

/** Scrolls an element into view and flashes it briefly. */
export function flash(id: string) {
  // After the router's own scroll restoration has run.
  window.setTimeout(() => {
    const el = document.getElementById(id);
    if (!el) return;
    el.scrollIntoView({ block: 'center' });
    el.classList.add('flash');
    window.setTimeout(() => el.classList.remove('flash'), 1200);
  }, 60);
}
