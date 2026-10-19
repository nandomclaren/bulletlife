import { useEffect, useState } from 'react';
import { openItems, openToday, type OpenItem } from '../data/openItems';
import { useAllEntries, useSettings } from '../data/repo';
import type { Entry } from '../data/types';
import { todayIso } from '../dates';

/** Today's date, refreshed when the day changes while the app is open. */
export function useToday(): string {
  const [today, setToday] = useState(todayIso);
  useEffect(() => {
    const tick = () => setToday(todayIso());
    const id = window.setInterval(tick, 60_000);
    document.addEventListener('visibilitychange', tick);
    return () => {
      window.clearInterval(id);
      document.removeEventListener('visibilitychange', tick);
    };
  }, []);
  return today;
}

export function useOpenItems(filter: 'all' | 'today' = 'all'): { items: OpenItem[]; entries: Entry[] } | undefined {
  const entries = useAllEntries();
  const settings = useSettings();
  const today = useToday();
  if (!entries) return undefined;
  return { items: filter === 'today' ? openToday(entries, settings, today) : openItems(entries, settings, today), entries };
}
