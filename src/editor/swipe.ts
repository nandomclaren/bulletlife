// Swipe on an entry (iPhone) marks it > (migrate) or < (schedule), CLAUDE.md 6.
// While swiping, the mark and its suggested destination are revealed behind
// the line (read-only). Touch only: on the Mac a two-finger swipe belongs to
// the browser's back/forward, so marks go through the menu and shortcuts.
import type { Mark } from '../data/openItems';
import { t } from '../i18n/en';

const DECIDE = 10; // px before deciding between a swipe and a scroll
const ARM = 72; // px to commit the mark on release
const MAX = 120;

export interface SwipeHandlers {
  /** Only entries with states can be marked (tasks; events with Event states on). */
  canSwipe: (lineId: string) => boolean;
  /** The state a swipe would set: the mark, or 'open' when the line already has it. */
  current: (lineId: string) => string | undefined;
  destination: (lineId: string, mark: Mark) => string;
  commit: (lineId: string, mark: Mark) => void;
  /** Settings › Reverse swipe directions. */
  reverse: () => boolean;
}

export function attachSwipe(root: HTMLElement, h: SwipeHandlers): () => void {
  let s: { id: string; el: HTMLElement; x: number; y: number; engaged: boolean; mark?: Mark; reveal?: HTMLElement; pointer: number } | null = null;

  const markFor = (dx: number): Mark => (dx > 0 !== h.reverse() ? 'migrated' : 'scheduled');

  const reset = (animate: boolean) => {
    if (!s) return;
    const { el, reveal } = s;
    el.classList.remove('swiping', 'armed');
    if (animate) el.classList.add('swipe-return');
    el.style.removeProperty('--swipe');
    window.setTimeout(() => {
      el.classList.remove('swipe-return');
      reveal?.remove();
    }, animate ? 180 : 0);
    s = null;
  };

  const onDown = (e: PointerEvent) => {
    if (e.pointerType !== 'touch' || s) return;
    const el = (e.target as Element | null)?.closest<HTMLElement>('.line');
    if (!el || !root.contains(el) || (e.target as Element).closest('.chevron')) return;
    const id = el.dataset.id;
    if (!id || !h.canSwipe(id)) return;
    s = { id, el, x: e.clientX, y: e.clientY, engaged: false, pointer: e.pointerId };
  };

  const onMove = (e: PointerEvent) => {
    if (!s || e.pointerId !== s.pointer) return;
    const dx = e.clientX - s.x;
    const dy = e.clientY - s.y;
    if (!s.engaged) {
      if (Math.abs(dy) > DECIDE && Math.abs(dy) > Math.abs(dx)) return reset(false);
      if (Math.abs(dx) < DECIDE || Math.abs(dx) < Math.abs(dy) * 1.5) return;
      s.engaged = true;
      s.el.classList.add('swiping');
      // Leave no caret or selection behind on the line being swiped.
      document.getSelection()?.removeAllRanges();
    }
    const mark = markFor(dx);
    if (mark !== s.mark) {
      s.mark = mark;
      s.reveal?.remove();
      s.reveal = reveal(s.id, mark, dx > 0, h);
      s.el.append(s.reveal);
    }
    const shown = Math.sign(dx) * Math.min(MAX, Math.abs(dx));
    s.el.style.setProperty('--swipe', `${shown}px`);
    s.el.classList.toggle('armed', Math.abs(dx) >= ARM);
  };

  const onUp = (e: PointerEvent) => {
    if (!s || e.pointerId !== s.pointer) return;
    const { id, engaged, mark } = s;
    const armed = engaged && Math.abs(e.clientX - s.x) >= ARM;
    reset(engaged);
    if (armed && mark) h.commit(id, mark);
  };

  const onCancel = () => reset(true);

  root.addEventListener('pointerdown', onDown);
  root.addEventListener('pointermove', onMove);
  root.addEventListener('pointerup', onUp);
  root.addEventListener('pointercancel', onCancel);
  return () => {
    reset(false);
    root.removeEventListener('pointerdown', onDown);
    root.removeEventListener('pointermove', onMove);
    root.removeEventListener('pointerup', onUp);
    root.removeEventListener('pointercancel', onCancel);
  };
}

function reveal(id: string, mark: Mark, fromLeft: boolean, h: SwipeHandlers): HTMLElement {
  const el = document.createElement('span');
  el.className = `swipe-reveal ${fromLeft ? 'from-left' : 'from-right'}`;
  el.contentEditable = 'false';
  el.setAttribute('aria-hidden', 'true');
  const glyph = document.createElement('b');
  glyph.textContent = mark === 'migrated' ? '>' : '<';
  const label = document.createElement('span');
  // Swiping a line that already carries this mark takes it back to open.
  label.textContent = h.current(id) === mark ? t.open.unmarked : h.destination(id, mark);
  el.append(glyph, label);
  return el;
}
