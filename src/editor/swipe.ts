// Swipe on an entry (iPhone) marks it > (migrate) or < (schedule), CLAUDE.md 6.
// Touch Events, not Pointer Events: inside editable text iOS Safari takes
// the gesture over and cancels pointers, while a touchmove we cancel early
// stays ours. Touch only: on the Mac a two-finger swipe belongs to the
// browser's back/forward, so marks go through the menu and shortcuts.
import type { Mark } from '../data/openItems';
import { t } from '../i18n/en';

const DECIDE = 10; // px before deciding between a swipe and a scroll
const ARM = 64; // px to commit the mark on release
const MAX = 110;

export interface SwipeHandlers {
  /** Only entries with states can be marked (tasks; events with Event states on). */
  canSwipe: (lineId: string) => boolean;
  /** The line's state: swiping toward the mark it already has takes it back to open. */
  current: (lineId: string) => string | undefined;
  commit: (lineId: string, mark: Mark) => void;
  /** Settings › Reverse swipe directions. */
  reverse: () => boolean;
}

interface Swipe {
  id: string;
  el: HTMLElement;
  touch: number;
  x: number;
  y: number;
  engaged: boolean;
  dx: number;
  mark?: Mark;
  reveal?: HTMLElement;
}

export function attachSwipe(root: HTMLElement, h: SwipeHandlers): () => void {
  let s: Swipe | null = null;

  const markFor = (dx: number): Mark => (dx > 0 !== h.reverse() ? 'migrated' : 'scheduled');
  const find = (e: TouchEvent) => (s ? [...e.changedTouches].find((tt) => tt.identifier === s!.touch) : undefined);

  const reset = (animate: boolean) => {
    if (!s) return;
    const { el, reveal } = s;
    el.classList.remove('swiping', 'armed');
    if (animate) el.classList.add('swipe-return');
    el.style.removeProperty('--swipe');
    window.setTimeout(
      () => {
        el.classList.remove('swipe-return');
        reveal?.remove();
      },
      animate ? 180 : 0,
    );
    s = null;
  };

  const onStart = (e: TouchEvent) => {
    if (s || e.touches.length !== 1) return reset(false);
    const target = e.target as Element;
    const el = target.closest?.<HTMLElement>('.line');
    if (!el || !root.contains(el) || target.closest('.chevron, .due, .sort-btn, button')) return;
    const id = el.dataset.id;
    if (!id || !h.canSwipe(id)) return;
    const tt = e.changedTouches[0];
    s = { id, el, touch: tt.identifier, x: tt.clientX, y: tt.clientY, engaged: false, dx: 0 };
  };

  const onMove = (e: TouchEvent) => {
    const tt = find(e);
    if (!s || !tt) return;
    const dx = tt.clientX - s.x;
    const dy = tt.clientY - s.y;
    if (!s.engaged) {
      if (Math.abs(dy) > DECIDE && Math.abs(dy) >= Math.abs(dx)) return reset(false); // a scroll
      // Claim a mostly horizontal move right away, before Safari decides what it is.
      if (Math.abs(dx) > Math.abs(dy) && e.cancelable) e.preventDefault();
      if (Math.abs(dx) < DECIDE) return;
      s.engaged = true;
      s.el.classList.add('swiping');
    }
    if (e.cancelable) e.preventDefault();
    s.dx = dx;
    const mark = markFor(dx);
    if (mark !== s.mark) {
      s.mark = mark;
      s.reveal?.remove();
      s.reveal = reveal(mark, dx > 0, h.current(s.id) === mark);
      s.el.append(s.reveal);
    }
    s.el.style.setProperty('--swipe', `${Math.sign(dx) * Math.min(MAX, Math.abs(dx))}px`);
    s.el.classList.toggle('armed', Math.abs(dx) >= ARM);
  };

  const onEnd = (e: TouchEvent) => {
    if (!s || !find(e)) return;
    const { id, engaged, mark, dx } = s;
    if (engaged && e.cancelable) e.preventDefault(); // no tap, no caret after a swipe
    reset(engaged);
    if (engaged && mark && Math.abs(dx) >= ARM) h.commit(id, mark);
  };

  const onCancel = () => reset(true);

  root.addEventListener('touchstart', onStart, { passive: true });
  root.addEventListener('touchmove', onMove, { passive: false });
  root.addEventListener('touchend', onEnd, { passive: false });
  root.addEventListener('touchcancel', onCancel);
  return () => {
    reset(false);
    root.removeEventListener('touchstart', onStart);
    root.removeEventListener('touchmove', onMove);
    root.removeEventListener('touchend', onEnd);
    root.removeEventListener('touchcancel', onCancel);
  };
}

/** What a release would do, behind the line: the glyph and "Migrate" / "Schedule" (or back to open). */
function reveal(mark: Mark, fromLeft: boolean, undoing: boolean): HTMLElement {
  const el = document.createElement('span');
  el.className = `swipe-reveal ${fromLeft ? 'from-left' : 'from-right'}`;
  el.contentEditable = 'false';
  el.setAttribute('aria-hidden', 'true');
  const glyph = document.createElement('b');
  glyph.textContent = mark === 'migrated' ? '>' : '<';
  const label = document.createElement('span');
  label.textContent = undoing ? t.open.unmarked : t.menu.states[mark];
  el.append(glyph, label);
  return el;
}
