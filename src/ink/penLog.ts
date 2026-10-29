// Pen diagnostics (Settings › Handwriting): a log of what the pen and the hand send to Pen mode, to find
// out why a stroke sometimes does not come out. Off by default; kept on this device only, in memory.
import { useSyncExternalStore } from 'react';

const KEY = 'pen.debug';
const KEEP = 400;

let on = (() => {
  try {
    return localStorage.getItem(KEY) === '1';
  } catch {
    return false;
  }
})();
let lines: string[] = [];
let version = 0;
const listeners = new Set<() => void>();
const changed = () => {
  version++;
  listeners.forEach((l) => l());
};

export function penLogOn(): boolean {
  return on;
}

const onListeners = new Set<() => void>();

/** Whether diagnostics are on (re-renders only when that changes, not on every logged event). */
export function usePenLogOn(): boolean {
  return useSyncExternalStore(
    (cb) => {
      onListeners.add(cb);
      return () => onListeners.delete(cb);
    },
    () => on,
  );
}

export function setPenLog(value: boolean): void {
  on = value;
  onListeners.forEach((l) => l());
  try {
    if (value) localStorage.setItem(KEY, '1');
    else localStorage.removeItem(KEY);
  } catch {
    // on for this session only
  }
  if (!value) lines = [];
  changed();
}

const start = performance.now();

/** One line of the log (only while diagnostics are on). */
export function penLog(what: string): void {
  if (!on) return;
  lines.push(`${((performance.now() - start) / 1000).toFixed(3)} ${what}`);
  if (lines.length > KEEP) lines = lines.slice(-KEEP);
  changed();
}

export function penLogText(): string {
  return [`Pen diagnostics · ${navigator.userAgent}`, ...lines].join('\n');
}

export function clearPenLog(): void {
  lines = [];
  changed();
}

/** Re-renders on every new line; returns the log and whether it is on. */
export function usePenLog(): { on: boolean; lines: string[] } {
  useSyncExternalStore(
    (cb) => {
      listeners.add(cb);
      return () => listeners.delete(cb);
    },
    () => version,
  );
  return { on, lines };
}

/**
 * Listens to everything the pen and the hand do on the sheet, before Pen mode handles it (capture phase),
 * so the log shows events the app ignored or never got. Returns the cleanup.
 */
export function watchSheet(host: HTMLElement): () => void {
  const pt = (e: PointerEvent) =>
    `${e.type} ${e.pointerType}#${e.pointerId}${e.isPrimary ? '' : ' (not primary)'} at ${Math.round(e.offsetX)},${Math.round(e.offsetY)} buttons=${e.buttons} pressure=${e.pressure.toFixed(2)} on ${describe(e.target)}`;
  let moves = 0;
  const onPointer = (e: PointerEvent) => {
    if (e.type === 'pointermove') {
      if (e.buttons) moves++;
      return;
    }
    if (e.type === 'pointerdown') moves = 0;
    penLog(pt(e) + (e.type === 'pointerup' || e.type === 'pointercancel' ? ` after ${moves} moves` : ''));
  };
  const onTouch = (e: TouchEvent) => {
    const all = Array.from(e.touches) as Array<Touch & { touchType?: string }>;
    const pens = all.filter((t) => t.touchType === 'stylus').length;
    penLog(`${e.type} touches=${all.length} (pen ${pens}, hand ${all.length - pens}) cancelable=${e.cancelable} prevented=${e.defaultPrevented}`);
  };
  const types = ['pointerdown', 'pointermove', 'pointerup', 'pointercancel', 'gotpointercapture', 'lostpointercapture'] as const;
  types.forEach((t) => host.addEventListener(t, onPointer, true));
  // Touches are logged once they have passed through Pen mode's own handler (window, bubbling), so
  // `prevented` tells whether it kept them from scrolling.
  const touches = ['touchstart', 'touchend', 'touchcancel'] as const;
  const onWindowTouch = (e: TouchEvent) => e.target instanceof Node && host.contains(e.target) && onTouch(e);
  touches.forEach((t) => window.addEventListener(t, onWindowTouch, { passive: true }));
  const onScroll = () => penLog(`page scrolled to ${Math.round(scrollY)}`);
  window.addEventListener('scroll', onScroll, { passive: true });
  // The whole page too: a stroke that never reached the sheet either landed on something else, or never
  // reached the page at all (held back by the system).
  const outside = (e: Event) => !(e.target instanceof Node && host.contains(e.target));
  const onPagePointer = (e: PointerEvent) => outside(e) && e.type !== 'pointermove' && penLog(`OUTSIDE THE SHEET: ${pt(e)}`);
  const onPageTouch = (e: TouchEvent) => outside(e) && penLog(`OUTSIDE THE SHEET: ${e.type} on ${describe(e.target)} touches=${e.touches.length}`);
  const onPageOther = (e: Event) => penLog(`page: ${e.type}${e.target instanceof Element ? ` on ${describe(e.target)}` : ''}`);
  const pageTypes = ['pointerdown', 'pointerup', 'pointercancel'] as const;
  pageTypes.forEach((t) => window.addEventListener(t, onPagePointer, true));
  touches.forEach((t) => window.addEventListener(t, onPageTouch, { capture: true, passive: true }));
  const others = ['gesturestart', 'gestureend', 'focusin', 'contextmenu', 'blur', 'visibilitychange'] as const;
  others.forEach((t) => window.addEventListener(t, onPageOther, true));
  return () => {
    pageTypes.forEach((t) => window.removeEventListener(t, onPagePointer, true));
    touches.forEach((t) => window.removeEventListener(t, onPageTouch, true));
    others.forEach((t) => window.removeEventListener(t, onPageOther, true));
    types.forEach((t) => host.removeEventListener(t, onPointer, true));
    touches.forEach((t) => window.removeEventListener(t, onWindowTouch));
    window.removeEventListener('scroll', onScroll);
  };
}

function describe(t: EventTarget | null): string {
  if (!(t instanceof Element)) return '?';
  const cls = typeof t.className === 'string' ? t.className : (t.getAttribute('class') ?? '');
  return `${t.tagName.toLowerCase()}${cls ? '.' + cls.trim().split(/\s+/).join('.') : ''}`;
}
