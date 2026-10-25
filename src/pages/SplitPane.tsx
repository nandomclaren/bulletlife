// Beside the main page on a wide screen: either the second page (a full page
// with its own navigation, editable like any page) or the two-page spread.
// The spread either lets the page's text flow on into a right-hand column
// (html.spread-flow, laid out by useSpreadFlow) or shows the next period as
// the facing page (it navigates the main page).
import { useEffect, useLayoutEffect, useMemo, useRef, type RefObject } from 'react';
import { renderPage } from '../App';
import { useLoadedSettings } from '../data/repo';
import { todayIso, type Weekday } from '../dates';
import { t } from '../i18n/en';
import { usePath } from '../router';
import { stepKey, type Level } from './nav';
import { mainPane, makeSecondaryPane, PaneContext, usePane } from './pane';
import { closeSplit, setSplitPath, toggleSplit, toggleSpread, useSplit } from './splitStore';

/** The period after the one at `path` ('/day/2026-10-19' → '/day/2026-10-20'); null for other pages. */
export function nextPeriodPath(path: string, firstDay: Weekday): string | null {
  const m = path.match(/^\/(day|week|month|year)\/([^/]+)$/);
  return m ? `/${m[1]}/${stepKey(m[1] as Level, m[2], 1, firstDay)}` : null;
}

export function SplitPane() {
  const split = useSplit();
  const settings = useLoadedSettings();
  const mainPath = usePath();
  const root = useRef<HTMLElement>(null);
  const pane = useMemo(() => makeSecondaryPane(setSplitPath, () => root.current, todayIso()), []);
  // The facing page has its own anchor and highlights, but going somewhere from it moves the main page.
  const facing = useMemo(() => {
    const p = makeSecondaryPane(mainPane.navigate, () => root.current, todayIso());
    return { ...p, navigate: mainPane.navigate, goUp: mainPane.goUp, back: mainPane.back };
  }, []);

  const flow = split.spread && settings?.spreadMode === 'flow';
  const spreadPath = split.spread && settings?.spreadMode === 'next' ? nextPeriodPath(mainPath, settings.firstDayOfWeek as Weekday) : null;
  const showing = split.open || !!spreadPath;

  useEffect(() => {
    const html = document.documentElement;
    html.classList.toggle('split-open', showing);
    html.classList.toggle('spread-open', !!spreadPath);
    html.classList.toggle('spread-flow', flow);
    return () => html.classList.remove('split-open', 'spread-open', 'spread-flow');
  }, [showing, spreadPath, flow]);

  if (spreadPath)
    return (
      <aside ref={root} className="split-pane spread" aria-label={t.split.spreadLabel}>
        <PaneContext.Provider value={facing}>{renderPage(spreadPath, settings, facing)}</PaneContext.Provider>
      </aside>
    );
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

const FLOW_MIN_WIDTH = '(min-width: 1000px)';

/**
 * Flowing spread: the editor's lines fill the left column down to the bottom
 * of the screen, then go on in the right one, like a magazine. The column
 * height is the screen's until the text needs more; then both columns grow
 * together, half the text each.
 */
export function useSpreadFlow(area: RefObject<HTMLElement | null>, enabled: boolean) {
  const split = useSplit();
  const on = enabled && split.spread;
  useLayoutEffect(() => {
    const host = area.current;
    if (!on || !host) return;
    let frame = 0;
    let editor: HTMLElement | null = null;
    const layout = () => {
      frame = 0;
      editor = host.querySelector<HTMLElement>('.editor');
      if (!editor) return;
      if (!document.documentElement.classList.contains('spread-flow') || !matchMedia(FLOW_MIN_WIDTH).matches) {
        editor.style.height = '';
        return;
      }
      let total = 0;
      for (const child of Array.from(editor.children) as HTMLElement[]) total += child.offsetHeight;
      const top = editor.getBoundingClientRect().top + window.scrollY;
      const screen = Math.max(240, window.innerHeight - top - 48);
      let height = Math.max(screen, Math.ceil(total / 2) + 8);
      editor.style.height = `${height}px`;
      // Lines never split across columns, so half may not be enough: grow until two columns hold it all.
      for (let i = 0; i < 60 && editor.scrollWidth > editor.clientWidth + 1; i++) editor.style.height = `${(height += 16)}px`;
    };
    const schedule = () => {
      if (!frame) frame = requestAnimationFrame(layout);
    };
    layout();
    const mo = new MutationObserver(schedule);
    mo.observe(host, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ['class'] });
    const ro = new ResizeObserver(schedule);
    ro.observe(document.documentElement);
    window.addEventListener('resize', schedule);
    return () => {
      cancelAnimationFrame(frame);
      mo.disconnect();
      ro.disconnect();
      window.removeEventListener('resize', schedule);
      if (editor) editor.style.height = '';
    };
  }, [on, area]);
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

/** Title-row button for the two-page spread (wide screens only). `flowOnly`: pages with no next period. */
export function SpreadButton({ flowOnly }: { flowOnly?: boolean }) {
  const { secondary } = usePane();
  const split = useSplit();
  const settings = useLoadedSettings();
  if (secondary || (flowOnly && settings?.spreadMode !== 'flow')) return null;
  return (
    <button className="split-btn" aria-label={split.spread ? t.split.spreadClose : t.split.spreadOpen} aria-pressed={split.spread} onClick={toggleSpread}>
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round" aria-hidden>
        <path d="M12 6.5C10 5 6.5 4.5 3 5v13.5c3.5-.5 7 0 9 1.5 2-1.5 5.5-2 9-1.5V5c-3.5-.5-7 0-9 1.5Z" />
        <path d="M12 6.5V20" />
      </svg>
    </button>
  );
}
