// Where a page lives: the main pane (the window, with real history) or the
// second pane of the split view (its own path, anchor date and scroll). Pages
// navigate through usePane(), so a page opened beside the main one moves on
// its own and never changes the main page.
import { createContext, useContext } from 'react';
import { todayIso } from '../dates';
import { navigate, replace } from '../router';
import { anchorWithin, flash, getAnchor, goUp, setAnchor, takeFrom } from './nav';

export interface Pane {
  secondary: boolean;
  navigate: (path: string) => void;
  replace: (path: string) => void;
  /** Goes up a level; the destination scrolls to (and flashes) where we came from. */
  goUp: (path: string, fromId: string) => void;
  takeFrom: () => string | null;
  setAnchor: (iso: string) => void;
  getAnchor: () => string;
  anchorWithin: (start: string, end: string) => string;
  flash: (id: string) => void;
  /** Index and Settings "Back". */
  back: () => void;
}

export const mainPane: Pane = {
  secondary: false,
  navigate,
  replace,
  goUp,
  takeFrom,
  setAnchor,
  getAnchor,
  anchorWithin,
  flash,
  back: () => (history.length > 1 ? history.back() : navigate('/')),
};

export const PaneContext = createContext<Pane>(mainPane);
export const usePane = () => useContext(PaneContext);

/** A second pane: navigation is a path in memory, scrolling happens inside `root`. */
export function makeSecondaryPane(go: (path: string) => void, root: () => HTMLElement | null, startAnchor: string): Pane {
  let anchor = startAnchor;
  let from: string | null = null;
  const history: string[] = [];
  let current = '';
  const pane: Pane = {
    secondary: true,
    navigate: (path) => {
      if (current) history.push(current);
      current = path;
      go(path);
      root()?.scrollTo(0, 0);
    },
    replace: (path) => {
      current = path;
      go(path);
    },
    goUp: (path, fromId) => {
      from = fromId;
      pane.navigate(path);
    },
    takeFrom: () => {
      const f = from;
      from = null;
      return f;
    },
    setAnchor: (iso) => {
      anchor = iso;
    },
    getAnchor: () => anchor,
    anchorWithin: (start, end) => {
      if (anchor >= start && anchor <= end) return anchor;
      const today = todayIso();
      anchor = today >= start && today <= end ? today : start;
      return anchor;
    },
    flash: (id) =>
      window.setTimeout(() => {
        const el = root()?.querySelector<HTMLElement>(`#${CSS.escape(id)}`);
        if (!el) return;
        el.scrollIntoView({ block: 'center' });
        el.classList.add('flash');
        window.setTimeout(() => el.classList.remove('flash'), 1200);
      }, 60),
    back: () => {
      const prev = history.pop();
      if (prev) {
        current = prev;
        go(prev);
      }
    },
  };
  return pane;
}
