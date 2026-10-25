// Flowing two-page spread: the page's lines fill the left column down to the
// bottom of the screen, go on in the right one, and when both are full the
// notebook turns to the next two pages. The editor root is a multi-column box
// of fixed height; the extra columns overflow to the right, the editor area
// clips them, and we show one pair at a time by sliding the box sideways. Narrow screens get the usual single page.
import { useLayoutEffect, useState, type RefObject } from 'react';
import { t } from '../i18n/en';
import { useSplit } from './splitStore';

const WIDE = '(min-width: 1000px)';
/** Room kept under the columns for the page turner. */
const BELOW = 64;

export interface Spread {
  /** Spread shown (0 = pages 1–2) and how many there are; pages = 0 when not flowing. */
  spread: number;
  pages: number;
  turn: (to: number) => void;
}

export function useSpreadFlow(area: RefObject<HTMLElement | null>, enabled: boolean): Spread {
  const split = useSplit();
  const on = enabled && split.spread;
  const [state, setState] = useState({ spread: 0, pages: 0 });
  const [turn, setTurn] = useState<(to: number) => void>(() => () => {});

  useLayoutEffect(() => {
    const host = area.current;
    if (!on || !host) return;
    let frame = 0;
    let editor: HTMLElement | null = null;
    let current = 0;
    const flowing = () => document.documentElement.classList.contains('spread-flow') && matchMedia(WIDE).matches;
    /** Width of one spread: two columns plus the gaps on both sides of the second. */
    const step = (el: HTMLElement) => el.clientWidth + parseFloat(getComputedStyle(el).columnGap || '0');
    const show = (to: number) => {
      if (!editor || !flowing()) return;
      const count = Math.max(1, Math.ceil(editor.scrollWidth / step(editor) - 0.01));
      current = Math.min(Math.max(0, to), count - 1);
      editor.style.transform = current ? `translateX(${-current * step(editor)}px)` : '';
      host.scrollLeft = 0;
      setState((s) => (s.spread === current && s.pages === count * 2 ? s : { spread: current, pages: count * 2 }));
    };
    /** The spread holding the caret, so typing past the bottom of the right page turns the page. */
    const caretSpread = () => {
      const sel = document.getSelection();
      if (!editor || !sel?.rangeCount || !editor.contains(sel.anchorNode)) return null;
      const range = sel.getRangeAt(0).cloneRange();
      range.collapse(true);
      let rect = range.getClientRects()[0];
      if (!rect) {
        const node = sel.anchorNode instanceof Element ? sel.anchorNode : sel.anchorNode?.parentElement;
        rect = node?.closest('.line')?.getBoundingClientRect() ?? (undefined as unknown as DOMRect);
      }
      if (!rect) return null;
      const x = rect.left - editor.getBoundingClientRect().left;
      return Math.floor(x / step(editor));
    };
    const layout = () => {
      frame = 0;
      editor = host.querySelector<HTMLElement>('.editor');
      if (!editor) return;
      if (!flowing()) {
        editor.style.height = '';
        editor.style.transform = '';
        setState((s) => (s.pages === 0 ? s : { spread: 0, pages: 0 }));
        return;
      }
      const top = editor.getBoundingClientRect().top + window.scrollY;
      editor.style.height = `${Math.max(240, window.innerHeight - top - BELOW)}px`;
      show(caretSpread() ?? current);
    };
    const schedule = () => {
      if (!frame) frame = requestAnimationFrame(layout);
    };
    const onSelection = () => {
      const to = caretSpread();
      if (to !== null && to !== current) show(to);
    };
    // The browser may scroll the clipping area by itself to bring the caret into view; undo that and turn instead.
    const onScroll = () => {
      if (host.scrollLeft && flowing()) show(caretSpread() ?? current);
    };
    layout();
    setTurn(() => (to: number) => show(to));
    const mo = new MutationObserver(schedule);
    mo.observe(host, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ['class'] });
    const ro = new ResizeObserver(schedule);
    ro.observe(document.documentElement);
    window.addEventListener('resize', schedule);
    document.addEventListener('selectionchange', onSelection);
    host.addEventListener('scroll', onScroll, true);
    return () => {
      cancelAnimationFrame(frame);
      mo.disconnect();
      ro.disconnect();
      window.removeEventListener('resize', schedule);
      document.removeEventListener('selectionchange', onSelection);
      host.removeEventListener('scroll', onScroll, true);
      if (editor) {
        editor.style.height = '';
        editor.style.transform = '';
      }
      setState({ spread: 0, pages: 0 });
    };
  }, [on, area]);

  return { ...state, turn };
}

/** "‹ Pages 3–4 of 6 ›" under a flowing spread; only when there is more than one pair of pages. */
export function SpreadTurner({ spread, pages, turn }: Spread) {
  if (pages <= 2) return null;
  const last = pages / 2 - 1;
  return (
    <nav className="spread-turner" aria-label={t.split.turner}>
      <button className="icon-btn-quiet" aria-label={t.split.prevPages} disabled={spread === 0} onClick={() => turn(spread - 1)}>
        ‹
      </button>
      <span className="spread-count">{t.split.pagesOf(spread * 2 + 1, spread * 2 + 2, pages)}</span>
      <button className="icon-btn-quiet" aria-label={t.split.nextPages} disabled={spread === last} onClick={() => turn(spread + 1)}>
        ›
      </button>
    </nav>
  );
}
