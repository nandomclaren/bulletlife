// Gestures on the bullet and chevron, shared by every editor. Line DOM:
// div.line[data-id] > span.gutter[contenteditable=false] + div.line-text.
// The gutter must never move the caret or toggle the iOS keyboard.

const TAP_TOLERANCE = 10;
const LONG_PRESS_MS = 500;

export interface GutterHandlers {
  bullet: (lineId: string) => void;
  chevron: (lineId: string) => void;
  /** Long press (iPhone, or click-and-hold) or right click / Ctrl-click (Mac) on the bullet. */
  menu: (lineId: string, anchor: DOMRect) => void;
}

export function attachGutter(root: HTMLElement, handlers: GutterHandlers): () => void {
  let start: { el: Element; x: number; y: number } | null = null;
  let timer = 0;
  let longPressed = false;

  const target = (e: Event) => (e.target as Element | null)?.closest?.('.bullet, .chevron') ?? null;
  const lineId = (el: Element) => el.closest<HTMLElement>('.line')?.dataset.id;
  const cancelTimer = () => window.clearTimeout(timer);

  const openMenu = (el: Element) => {
    const id = lineId(el);
    if (!id) return;
    // Plain lines have no visible bullet: anchor on the line instead.
    const r = el.getBoundingClientRect();
    handlers.menu(id, r.width ? r : el.closest('.line')!.getBoundingClientRect());
  };

  const onPointerDown = (e: PointerEvent) => {
    const el = target(e);
    start = el ? { el, x: e.clientX, y: e.clientY } : null;
    longPressed = false;
    cancelTimer();
    if (el?.classList.contains('bullet') && e.button === 0) {
      timer = window.setTimeout(() => {
        longPressed = true;
        openMenu(el);
      }, LONG_PRESS_MS);
    }
  };
  const onPointerMove = (e: PointerEvent) => {
    if (start && Math.hypot(e.clientX - start.x, e.clientY - start.y) > TAP_TOLERANCE) cancelTimer();
  };
  const onPointerUp = (e: PointerEvent) => {
    cancelTimer();
    const el = target(e);
    const s = start;
    start = null;
    if (longPressed || !s || el !== s.el || Math.hypot(e.clientX - s.x, e.clientY - s.y) > TAP_TOLERANCE) return;
    const id = lineId(el);
    if (!id) return;
    if (el.classList.contains('bullet')) handlers.bullet(id);
    else handlers.chevron(id);
  };
  const onContextMenu = (e: MouseEvent) => {
    const el = (e.target as Element | null)?.closest?.('.gutter');
    if (!el) return;
    e.preventDefault();
    cancelTimer();
    longPressed = true;
    openMenu(el.querySelector('.bullet') ?? el);
  };
  // Keep focus and caret where they are.
  const swallow = (e: Event) => {
    if (target(e)) e.preventDefault();
  };

  root.addEventListener('pointerdown', onPointerDown);
  root.addEventListener('pointermove', onPointerMove);
  root.addEventListener('pointerup', onPointerUp);
  root.addEventListener('pointercancel', cancelTimer);
  root.addEventListener('contextmenu', onContextMenu);
  root.addEventListener('mousedown', swallow);
  root.addEventListener('touchend', swallow);
  root.addEventListener('click', swallow);
  return () => {
    cancelTimer();
    root.removeEventListener('pointerdown', onPointerDown);
    root.removeEventListener('pointermove', onPointerMove);
    root.removeEventListener('pointerup', onPointerUp);
    root.removeEventListener('pointercancel', cancelTimer);
    root.removeEventListener('contextmenu', onContextMenu);
    root.removeEventListener('mousedown', swallow);
    root.removeEventListener('touchend', swallow);
    root.removeEventListener('click', swallow);
  };
}
