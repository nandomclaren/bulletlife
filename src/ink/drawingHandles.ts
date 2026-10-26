// Drawings in Type mode: tap to select, then drag to move (up or down among
// the lines of the page, and sideways) or drag the corner to resize. One
// drawing at a time; moving stays within the same page.

export interface DrawingView {
  /** Width in Type mode, px. */
  w: number;
  /** Offset from the start of the text column, px. */
  x: number;
}

interface Callbacks {
  /** Move the drawing's line so it comes before line `before` (an index in the page; the end = line count). */
  move: (id: string, before: number) => void;
  view: (id: string, view: DrawingView) => void;
  remove: (id: string) => void;
}

const MIN_W = 60;

export function attachDrawingHandles(root: HTMLElement, cb: Callbacks): () => void {
  let selected: HTMLElement | null = null;
  let indicator: HTMLElement | null = null;

  const select = (el: HTMLElement | null) => {
    selected?.classList.remove('selected');
    selected = el;
    el?.classList.add('selected');
  };

  const lines = () =>
    Array.from(root.children).filter((c): c is HTMLElement => c instanceof HTMLElement && c.classList.contains('line') && !c.classList.contains('is-hidden'));

  /** The gap between lines nearest to y: returns the index (in the page) of the line it comes before. */
  const gapAt = (y: number): { before: number; y: number } => {
    const all = Array.from(root.children) as HTMLElement[];
    const visible = lines();
    for (const el of visible) {
      const r = el.getBoundingClientRect();
      if (y < r.top + r.height / 2) return { before: all.indexOf(el), y: r.top };
    }
    const last = visible[visible.length - 1];
    return { before: all.length, y: last ? last.getBoundingClientRect().bottom : root.getBoundingClientRect().top };
  };

  const onDown = (e: PointerEvent) => {
    const el = (e.target as Element).closest<HTMLElement>('.line-ink.is-drawing');
    if (!el || !root.contains(el)) {
      if (selected && !(e.target as Element).closest('.line-ink')) select(null);
      return;
    }
    e.preventDefault();
    e.stopPropagation();
    // A finger first selects (so a swipe over a drawing still scrolls the page); mouse and pen can drag at once.
    if (el !== selected) {
      select(el);
      if (e.pointerType === 'touch') return;
    }
    const line = el.closest<HTMLElement>('.line');
    const id = line?.dataset.id;
    if (!line || !id) return;
    if ((e.target as Element).closest('.ink-delete')) {
      select(null);
      cb.remove(id);
      return;
    }
    const resizing = !!(e.target as Element).closest('.ink-handle');
    const pad = parseFloat(getComputedStyle(line).paddingLeft) || 0;
    const avail = line.clientWidth - pad;
    const startW = el.offsetWidth;
    const startX = parseFloat(el.style.marginLeft) || 0;
    const x0 = e.clientX;
    const y0 = e.clientY;
    let w = startW;
    let x = startX;
    let gap: { before: number; y: number } | null = null;
    el.setPointerCapture(e.pointerId);

    const onMove = (ev: PointerEvent) => {
      const dx = ev.clientX - x0;
      const dy = ev.clientY - y0;
      if (resizing) {
        w = Math.round(Math.min(Math.max(MIN_W, startW + dx), avail - startX));
        el.style.width = `${w}px`;
        return;
      }
      x = Math.round(Math.min(Math.max(0, startX + dx), Math.max(0, avail - startW)));
      el.style.marginLeft = `${x}px`;
      el.style.transform = `translateY(${dy}px)`;
      gap = Math.abs(dy) > 16 ? gapAt(ev.clientY) : null;
      if (gap) {
        indicator ??= document.body.appendChild(Object.assign(document.createElement('div'), { className: 'ink-drop' }));
        const r = root.getBoundingClientRect();
        Object.assign(indicator.style, { top: `${gap.y - 1}px`, left: `${r.left + pad}px`, width: `${r.width - pad}px` });
      } else {
        indicator?.remove();
        indicator = null;
      }
    };
    const onUp = () => {
      el.removeEventListener('pointermove', onMove);
      el.removeEventListener('pointerup', onUp);
      el.removeEventListener('pointercancel', onUp);
      el.style.transform = '';
      indicator?.remove();
      indicator = null;
      if (w !== startW || x !== startX) cb.view(id, { w, x });
      if (gap) {
        const index = Array.prototype.indexOf.call(root.children, line);
        if (gap.before !== index && gap.before !== index + 1) cb.move(id, gap.before);
      }
    };
    el.addEventListener('pointermove', onMove);
    el.addEventListener('pointerup', onUp);
    el.addEventListener('pointercancel', onUp);
  };

  const onKey = (e: KeyboardEvent) => {
    if (!selected) return;
    if (e.key === 'Escape') select(null);
    else if (e.key === 'Backspace' || e.key === 'Delete') {
      // The selected drawing goes, not the text where the caret happens to be.
      e.preventDefault();
      e.stopPropagation();
      const id = selected.closest<HTMLElement>('.line')?.dataset.id;
      select(null);
      if (id) cb.remove(id);
    }
  };
  document.addEventListener('pointerdown', onDown, true);
  document.addEventListener('keydown', onKey, true);
  return () => {
    document.removeEventListener('pointerdown', onDown, true);
    document.removeEventListener('keydown', onKey, true);
    indicator?.remove();
  };
}
