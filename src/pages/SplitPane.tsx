// The second page of the split view: a full notebook page beside the main
// one, with its own navigation and scrolling, editable like any page.
import { useEffect, useMemo, useRef } from 'react';
import { renderPage } from '../App';
import { useLoadedSettings } from '../data/repo';
import { todayIso } from '../dates';
import { t } from '../i18n/en';
import { makeSecondaryPane, PaneContext, usePane } from './pane';
import { closeSplit, setSplitPath, toggleSplit, useSplit } from './splitStore';

export function SplitPane() {
  const split = useSplit();
  const settings = useLoadedSettings();
  const root = useRef<HTMLElement>(null);
  const pane = useMemo(() => makeSecondaryPane(setSplitPath, () => root.current, todayIso()), []);

  useEffect(() => {
    const html = document.documentElement;
    html.classList.toggle('split-open', split.open);
    return () => html.classList.remove('split-open');
  }, [split.open]);

  if (!split.open) return null;
  return (
    <aside ref={root} className="split-pane" aria-label={t.split.label}>
      <button className="icon-btn-quiet split-close" aria-label={t.split.close} onClick={closeSplit}>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden>
          <path d="M6 6l12 12M18 6L6 18" />
        </svg>
      </button>
      <PaneContext.Provider value={pane}>{renderPage(split.path, settings, pane)}</PaneContext.Provider>
    </aside>
  );
}

/** Title-row button that opens or closes the second page (wide screens only). */
export function SplitButton() {
  const { secondary } = usePane();
  const split = useSplit();
  if (secondary) return null;
  return (
    <button className="split-btn" aria-label={split.open ? t.split.close : t.split.open} aria-pressed={split.open} onClick={toggleSplit}>
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" aria-hidden>
        <rect x="3" y="4.5" width="18" height="15" rx="2.5" />
        <path d="M12 4.5v15" />
      </svg>
    </button>
  );
}
