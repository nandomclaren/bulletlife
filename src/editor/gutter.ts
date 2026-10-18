// Taps on the bullet and chevron, shared by both editors. Both render the
// same line DOM: div.line[data-id] > span.gutter[contenteditable=false] + div.line-text.
// The gutter must never move the caret or toggle the iOS keyboard.

const TAP_TOLERANCE = 10;

export interface GutterHandlers {
  bullet: (lineId: string) => void;
  chevron: (lineId: string) => void;
}

export function attachGutter(root: HTMLElement, handlers: GutterHandlers): () => void {
  let start: { el: Element; x: number; y: number } | null = null;

  const target = (e: Event) => (e.target as Element | null)?.closest?.('.bullet, .chevron') ?? null;

  const onPointerDown = (e: PointerEvent) => {
    const el = target(e);
    start = el ? { el, x: e.clientX, y: e.clientY } : null;
  };
  const onPointerUp = (e: PointerEvent) => {
    const el = target(e);
    if (!start || el !== start.el || Math.hypot(e.clientX - start.x, e.clientY - start.y) > TAP_TOLERANCE) {
      start = null;
      return;
    }
    start = null;
    const id = el.closest<HTMLElement>('.line')?.dataset.id;
    if (!id) return;
    if (el.classList.contains('bullet')) handlers.bullet(id);
    else handlers.chevron(id);
  };
  // Keep focus and caret where they are.
  const swallow = (e: Event) => {
    if (target(e)) e.preventDefault();
  };

  root.addEventListener('pointerdown', onPointerDown);
  root.addEventListener('pointerup', onPointerUp);
  root.addEventListener('mousedown', swallow);
  root.addEventListener('touchend', swallow);
  root.addEventListener('click', swallow);
  return () => {
    root.removeEventListener('pointerdown', onPointerDown);
    root.removeEventListener('pointerup', onPointerUp);
    root.removeEventListener('mousedown', swallow);
    root.removeEventListener('touchend', swallow);
    root.removeEventListener('click', swallow);
  };
}
