// Mac keyboard shortcuts (CLAUDE.md 5.1, Phase 5). event.code, so they work on
// any keyboard layout; ⌃⌘ keeps clear of Safari and macOS text shortcuts.
import { useEffect } from 'react';
import { todayIso, type Weekday } from '../dates';
import type { Settings } from '../data/types';
import { togglePanel } from '../open/panelStore';
import { navigate } from '../router';
import { openSearch } from '../search/store';
import { activeLevels, finestLevel, getAnchor, pathFor, setAnchor, stepKey, type Level } from './nav';

const LEVEL_OF: Record<string, Level> = { day: 'day', week: 'week', month: 'month', year: 'year' };

export function useShortcuts(path: string, settings: Settings | undefined) {
  useEffect(() => {
    if (!settings) return;
    const firstDay = settings.firstDayOfWeek as Weekday;
    const onKey = (e: KeyboardEvent) => {
      // ⌘K: search, from anywhere.
      if (e.code === 'KeyK' && (e.metaKey || e.ctrlKey) && !e.altKey && !e.shiftKey) {
        e.preventDefault();
        return openSearch();
      }
      if (!(e.ctrlKey && e.metaKey) || e.altKey || e.shiftKey) return;
      const m = path.match(/^\/(day|week|month|year)\/([^/]+)$/);
      const level = m ? LEVEL_OF[m[1]] : null;
      const levels = activeLevels(settings);
      switch (e.code) {
        case 'KeyT': // ⌃⌘T: today, on the finest active log
          e.preventDefault();
          setAnchor(todayIso());
          return navigate(pathFor(finestLevel(settings), todayIso(), firstDay));
        case 'KeyO': // ⌃⌘O: Open items
          e.preventDefault();
          return togglePanel();
        case 'ArrowUp': // ⌃⌘↑ / ⌃⌘↓: up or down a level, at the anchor date
        case 'ArrowDown': {
          if (!level) return;
          const next = levels[levels.indexOf(level) + (e.code === 'ArrowUp' ? -1 : 1)];
          e.preventDefault();
          if (next) navigate(pathFor(next, getAnchor(), firstDay));
          return;
        }
        case 'ArrowLeft': // ⌃⌘← / ⌃⌘→: previous or next period
        case 'ArrowRight':
          if (!level || !m) return;
          e.preventDefault();
          return navigate(`/${level}/${stepKey(level, m[2], e.code === 'ArrowLeft' ? -1 : 1, firstDay)}`);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [path, settings]);
}
