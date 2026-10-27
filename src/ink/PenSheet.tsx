// Pen mode: the page as a ruled sheet you write and draw on with the pen.
// Each ruled line is an entry: writing on a line adds to that entry, writing
// below the last line starts a new one. Typed entries sit on the same lines.
// Fingers scroll; only the pen (or a mouse) leaves ink. Bullets of typed
// entries still work: a tap cycles the state, holding opens the states menu.
import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { addInk, addInkLines, eraseInk, markInkState, moveInk, restoreInk, usePageLines, useSettings, type InkSnapshot, type LogRef } from '../data/repo';
import { playDoneFx } from '../editor/doneFx';
import { colorTypes, glyph, hasChildren, hasStates, hiddenMask, newLine, nextState, type Line, type LineState, type LineType } from '../editor/lines';
import { buildGutter, fillText, lineClass } from '../editor/render';
import { t } from '../i18n/en';
import { compact, DEFAULT_SIZE, PEN_SIZES, type Box, hasInk, hasWriting, inkRows, inkSvg, ROW, strokeBox, strokeHit, strokePath, type Stroke } from './ink';
import { lassoed, placeStroke, rowWithin, strokeRow, type LastStroke } from './structure';
import { setPenColor, setPenSize, setPenTool, usePen, type PenTool } from './penStore';
import { transcribePage } from './transcribe';
import type { InkColor } from './ink';

interface Block {
  id: string;
  top: number;
  height: number;
  line: Line;
}

/** Empty ruled lines kept below the last entry, so there is always room to write. */
const SPARE_ROWS = 12;
const ERASER_RADIUS = 10;

export function PenSheet({ log, slot = '', label }: { log: LogRef; slot?: string; label?: string }) {
  const lines = usePageLines(log.id, slot);
  const pen = usePen();
  const sheet = useRef<HTMLDivElement>(null);
  const live = useRef<SVGPathElement>(null);
  /** Strokes the lasso holds (by entry and stroke index), and their box on the page. */
  const [sel, setSel] = useState<{ items: Array<{ id: string; i: number }>; box: Box } | null>(null);
  const selRef = useRef(sel);
  selRef.current = sel;
  const boxEl = useRef<HTMLDivElement>(null);
  const mode = useRef<'ink' | 'lasso' | 'drag'>('ink');
  const dragFrom = useRef({ x: 0, y: 0, dx: 0, dy: 0 });
  const settings = useSettings();
  const [menu, setMenu] = useState<{ id: string; x: number; y: number; state: LineState } | null>(null);
  const blocks = useRef<Block[]>([]);
  const contentEnd = useRef(0);
  const drawing = useRef(false);
  const deferred = useRef<Line[] | null>(null);
  const undo = useRef<InkSnapshot[]>([]);
  const [canUndo, setCanUndo] = useState(false);
  const lastStroke = useRef<(LastStroke & { id: string }) | null>(null);
  const toolRef = useRef(pen);
  toolRef.current = pen;

  /** Rows already drawn, kept between redraws: only lines that changed are drawn again. */
  const rowCache = useRef(new Map<string, { sig: string; el: HTMLElement; height: number }>());

  /**
   * Lays the page out as ruled blocks: one per visible entry, as many lines tall as its text or ink.
   * It runs after every stroke, so it only redraws the lines that changed (redrawing the whole page,
   * every stroke of it, made the pen catch between strokes), and measures new typed lines in one go.
   */
  const build = (ls: Line[]) => {
    const host = sheet.current;
    if (!host) return;
    const colors = colorTypes(ls);
    const hidden = hiddenMask(ls);
    const rows = host.querySelector<HTMLElement>('.pen-rows')!;
    host.querySelectorAll('.pen-pending').forEach((el) => el.remove());
    const width = host.clientWidth;
    const cache = rowCache.current;
    const els: HTMLElement[] = [];
    const fresh: Array<{ l: Line; i: number; row: HTMLElement; typed: boolean }> = [];
    const visible: Line[] = [];
    ls.forEach((l, i) => {
      if (hidden[i]) return;
      visible.push(l);
      const typed = isTyped(l);
      const sig = rowSignature(l, colors[i], hasChildren(ls, i), width, settings.doneMark);
      const hit = cache.get(l.id);
      if (hit && hit.sig === sig) {
        els.push(hit.el);
        return;
      }
      const row = document.createElement('div');
      row.className = 'pen-row';
      row.dataset.id = l.id;
      if (typed) {
        const el = document.createElement('div');
        el.className = `${lineClass(l, { color: colors[i], hasChildren: hasChildren(ls, i), hidden: false })} pen-typed`;
        el.style.setProperty('--indent', String(l.indent));
        const text = document.createElement('div');
        text.className = 'line-text';
        fillText(text, l.text);
        el.append(buildGutter(document, l, l.collapsed), text);
        row.append(el);
      }
      cache.set(l.id, { sig, el: row, height: ROW });
      els.push(row);
      fresh.push({ l, i, row, typed });
    });
    rows.replaceChildren(...els);
    // Measure all new typed lines together (one layout), then size and ink them.
    const typedHeights = fresh.map((f) => (f.typed ? (f.row.firstElementChild as HTMLElement).offsetHeight : 0));
    fresh.forEach(({ l, i, row, typed }, k) => {
      const typedRows = typed ? Math.ceil(typedHeights[k] / ROW - 0.05) : 0;
      const n = Math.max(1, typedRows, inkRows(l.ink));
      row.style.height = `${n * ROW}px`;
      if (hasInk(l.ink)) {
        const color = colors[i] === 'task' || colors[i] === 'event' || colors[i] === 'note' ? colors[i] : undefined;
        const svg = inkSvg(document, l.ink, { width, height: n * ROW, bulletColor: color });
        svg.classList.add('pen-ink');
        row.append(svg);
        if (hasWriting(l.ink) && !typed) decorateHand(row, l, color, settings.doneMark);
      }
      cache.get(l.id)!.height = n * ROW;
    });
    const live = new Set(visible.map((l) => l.id));
    for (const id of cache.keys()) if (!live.has(id)) cache.delete(id);
    let top = 0;
    const out: Block[] = visible.map((l) => {
      const height = cache.get(l.id)!.height;
      const b = { id: l.id, top, height, line: l };
      top += height;
      return b;
    });
    blocks.current = out;
    contentEnd.current = top;
    // A lasso selection survives the page being redrawn (e.g. a transcription arriving), if its strokes do.
    const held = selRef.current;
    if (held) {
      const items = held.items.filter(({ id, i }) => out.some((b) => b.id === id && b.line.ink?.strokes[i]));
      if (items.length) {
        markSelection(items);
        setSel({ items, box: selectionBox(items) });
      } else setSel(null);
    }
    const spare = Math.max(SPARE_ROWS, Math.ceil((window.innerHeight - host.getBoundingClientRect().top - top) / ROW));
    host.style.minHeight = `${top + spare * ROW}px`;
  };

  // The page keeps its own layout while the pen is down, and until storage has caught up with every stroke
  // already placed (a stale page would send the next stroke to the wrong line).
  const caughtUp = (ls: Line[]) => {
    const stored = new Map(ls.map((l) => [l.id, l.ink?.strokes.length ?? 0]));
    return blocks.current.every((b) => stored.has(b.id) && stored.get(b.id)! >= (b.line.ink?.strokes.length ?? 0));
  };
  const inflight = useRef(0);
  const apply = (ls: Line[]) => {
    if (drawing.current || (inflight.current > 0 && !caughtUp(ls))) deferred.current = ls;
    else {
      deferred.current = null;
      build(ls);
    }
  };
  useLayoutEffect(() => {
    if (lines) apply(lines);
  }, [lines]);

  useEffect(() => {
    const onResize = () => lines && !drawing.current && build(lines);
    window.addEventListener('resize', onResize);
    return () => window.removeEventListener('resize', onResize);
  }, [lines]);

  // The pen must not scroll the page (Safari would turn a stroke into a scroll); fingers still do.
  useEffect(() => {
    const host = sheet.current!;
    const stylus = (e: TouchEvent) => {
      if (Array.from(e.touches).some((t) => (t as Touch & { touchType?: string }).touchType === 'stylus')) e.preventDefault();
    };
    host.addEventListener('touchstart', stylus, { passive: false });
    host.addEventListener('touchmove', stylus, { passive: false });
    return () => {
      host.removeEventListener('touchstart', stylus);
      host.removeEventListener('touchmove', stylus);
    };
  }, []);

  // Handwriting is transcribed after a pause in writing, and when leaving Pen mode (unmount).
  const pause = useRef(0);
  const settingsRef = useRef(settings);
  settingsRef.current = settings;
  const soon = () => {
    clearTimeout(pause.current);
    pause.current = window.setTimeout(() => void transcribePage(log.id, slot, settingsRef.current), 2500);
  };
  useEffect(
    () => () => {
      clearTimeout(pause.current);
      void transcribePage(log.id, slot, settingsRef.current);
    },
    [log.id, slot],
  );

  const pushUndo = (snap: InkSnapshot) => {
    if (!snap.size) return;
    undo.current.push(snap);
    if (undo.current.length > 100) undo.current.shift();
    setCanUndo(true);
  };

  const flush = () => {
    drawing.current = false;
    if (deferred.current) apply(deferred.current);
  };

  /**
   * Runs a write, holding back stale pages until it lands. A page held back during a stroke write is only
   * used if it already has the strokes (a newer one follows the write anyway); after erasing, the latest is.
   */
  const write = async <T,>(w: Promise<T>, erase = false): Promise<T> => {
    inflight.current++;
    try {
      return await w;
    } finally {
      inflight.current--;
      const held = deferred.current;
      if (held && inflight.current === 0 && !drawing.current && (erase || caughtUp(held))) {
        deferred.current = null;
        build(held);
      }
    }
  };

  // ---------- one stroke ----------

  const points = useRef<number[]>([]);
  const erased = useRef<Map<string, Set<number>>>(new Map());
  const frame = useRef(0);
  const tool = useRef<PenTool>('write');
  const isPen = useRef(false);

  // The sheet's place on screen, read once per stroke: reading it on every pen move made the browser
  // lay the page out again in the middle of the stroke.
  const originRect = useRef<DOMRect | null>(null);
  const origin = () => originRect.current ?? sheet.current!.getBoundingClientRect();

  // The stroke in progress is drawn in the sheet's own coordinates (the same as the stored ink),
  // so it appears exactly under the pen tip.
  const paintLive = () => {
    frame.current = 0;
    const path = live.current;
    if (!path || tool.current === 'erase') return;
    path.setAttribute('class', `ink-${toolRef.current.color}`);
    path.setAttribute('d', strokePath({ k: tool.current === 'draw' ? 'd' : 'w', p: points.current, pen: isPen.current }, 0, 1, true));
  };

  const clearLive = () => live.current?.setAttribute('d', '');

  // ---------- bullets of typed entries ----------

  const press = useRef<{ id: string; x: number; y: number; timer: number; held: boolean } | null>(null);

  const stateful = (l: Line) => hasStates(l.type, settings.eventStates);

  const setState = async (id: string, state: LineState) => {
    const b = blocks.current.find((x) => x.id === id);
    if (!b || b.line.state === state) return;
    const el = sheet.current?.querySelector<HTMLElement>(`.pen-row[data-id="${id}"] .pen-typed`);
    if (state === 'done') playDoneFx(el, 'done');
    else if (state === 'cancelled') playDoneFx(el, 'cancel');
    pushUndo(await markInkState(id, state));
  };

  const bulletDown = (e: React.PointerEvent): boolean => {
    const bullet = (e.target as Element).closest('.pen-typed .bullet, .pen-hand-bullet');
    const id = bullet?.closest<HTMLElement>('.pen-row')?.dataset.id;
    const b = id ? blocks.current.find((x) => x.id === id) : undefined;
    if (!b || !stateful(b.line)) return false;
    e.preventDefault();
    const r = bullet!.getBoundingClientRect();
    const timer = window.setTimeout(() => {
      if (!press.current) return;
      press.current.held = true;
      setMenu({ id: b.id, x: r.left, y: r.bottom, state: b.line.state });
    }, 500);
    press.current = { id: b.id, x: e.clientX, y: e.clientY, timer, held: false };
    return true;
  };

  const bulletUp = (e: React.PointerEvent): boolean => {
    const p = press.current;
    if (!p) return false;
    press.current = null;
    clearTimeout(p.timer);
    const b = blocks.current.find((x) => x.id === p.id);
    if (!p.held && b && Math.hypot(e.clientX - p.x, e.clientY - p.y) < 12) void setState(p.id, nextState(b.line.state));
    return true;
  };

  const add = (e: PointerEvent) => {
    const o = origin();
    const evs = e.getCoalescedEvents?.() ?? [];
    for (const ev of evs.length ? evs : [e]) {
      const pressure = ev.pointerType === 'pen' ? ev.pressure || 0.5 : 0.5;
      points.current.push(ev.clientX - o.left, ev.clientY - o.top, pressure);
    }
  };

  const eraseAt = () => {
    const p = points.current;
    const path: Array<[number, number]> = [];
    for (let i = Math.max(0, p.length - 30); i < p.length; i += 3) path.push([p[i], p[i + 1]]);
    for (const b of blocks.current) {
      if (!hasInk(b.line.ink)) continue;
      b.line.ink.strokes.forEach((s, i) => {
        if (erased.current.get(b.id)?.has(i)) return;
        if (strokeHit(s.p, b.top, path, ERASER_RADIUS)) {
          if (!erased.current.has(b.id)) erased.current.set(b.id, new Set());
          erased.current.get(b.id)!.add(i);
          sheet.current!.querySelector(`.pen-row[data-id="${b.id}"] path[data-i="${i}"]`)?.classList.add('erasing');
        }
      });
    }
  };

  // ---------- lasso ----------

  const pathsOf = (items: Array<{ id: string; i: number }>) =>
    items
      .map(({ id, i }) => sheet.current?.querySelector<SVGPathElement>(`.pen-row[data-id="${id}"] .pen-ink path[data-i="${i}"]`))
      .filter((p): p is SVGPathElement => !!p);

  function markSelection(items: Array<{ id: string; i: number }>) {
    sheet.current?.querySelectorAll('.lassoed').forEach((p) => p.classList.remove('lassoed'));
    pathsOf(items).forEach((p) => p.classList.add('lassoed'));
  }

  function selectionBox(items: Array<{ id: string; i: number }>): Box {
    const boxes = items.map(({ id, i }) => {
      const b = blocks.current.find((x) => x.id === id)!;
      const s = strokeBox(b.line.ink!.strokes[i].p);
      return { x0: s.x0, x1: s.x1, y0: s.y0 + b.top, y1: s.y1 + b.top };
    });
    return boxes.reduce((a, b) => ({ x0: Math.min(a.x0, b.x0), y0: Math.min(a.y0, b.y0), x1: Math.max(a.x1, b.x1), y1: Math.max(a.y1, b.y1) }));
  }

  const clearSelection = () => {
    sheet.current?.querySelectorAll('.lassoed').forEach((p) => p.classList.remove('lassoed'));
    setSel(null);
  };

  useEffect(() => {
    if (pen.tool !== 'lasso' && selRef.current) clearSelection();
  }, [pen.tool]);

  const PAD = 10;

  const lassoDown = (e: React.PointerEvent) => {
    const o = origin();
    const x = e.clientX - o.left;
    const y = e.clientY - o.top;
    const box = selRef.current?.box;
    // Inside the selection: drag it. Anywhere else: a new loop.
    if (box && x >= box.x0 - PAD && x <= box.x1 + PAD && y >= box.y0 - PAD && y <= box.y1 + PAD) {
      mode.current = 'drag';
      dragFrom.current = { x: e.clientX, y: e.clientY, dx: 0, dy: 0 };
      return;
    }
    clearSelection();
    mode.current = 'lasso';
    points.current = [x, y, 0.5];
    live.current?.setAttribute('class', 'lasso-line');
  };

  const lassoMove = (e: React.PointerEvent) => {
    if (mode.current === 'drag') {
      const dx = e.clientX - dragFrom.current.x;
      const dy = e.clientY - dragFrom.current.y;
      dragFrom.current.dx = dx;
      dragFrom.current.dy = dy;
      for (const p of pathsOf(selRef.current?.items ?? [])) p.setAttribute('transform', `translate(${dx} ${dy})`);
      if (boxEl.current) boxEl.current.style.transform = `translate(${dx}px, ${dy}px)`;
      return;
    }
    add(e.nativeEvent);
    const p = points.current;
    let d = '';
    for (let i = 0; i < p.length; i += 3) d += `${i ? 'L' : 'M'}${p[i].toFixed(1)} ${p[i + 1].toFixed(1)}`;
    live.current?.setAttribute('d', `${d}Z`);
  };

  const lassoUp = async () => {
    if (mode.current === 'drag') {
      mode.current = 'ink';
      const { dx, dy } = dragFrom.current;
      if (Math.hypot(dx, dy) < 3) {
        for (const p of pathsOf(selRef.current?.items ?? [])) p.removeAttribute('transform');
        if (boxEl.current) boxEl.current.style.transform = '';
        flush();
        return;
      }
      return moveSelection(dx, dy);
    }
    mode.current = 'ink';
    const p = points.current;
    const loop: Array<[number, number]> = [];
    for (let i = 0; i < p.length; i += 3) loop.push([p[i], p[i + 1]]);
    clearLive();
    live.current?.removeAttribute('class');
    flush();
    const items = lassoed(
      blocks.current.map((b) => ({ id: b.id, top: b.top, strokes: b.line.ink?.strokes ?? [] })),
      loop,
    );
    if (!items.length) return;
    markSelection(items);
    setSel({ items, box: selectionBox(items) });
  };

  /** Drops the lassoed strokes where they were dragged: onto the line they now sit on, or a new one. */
  const moveSelection = async (dx: number, dy: number) => {
    const items = selRef.current?.items ?? [];
    const picked = new Map<string, Set<number>>();
    for (const { id, i } of items) {
      if (!picked.has(id)) picked.set(id, new Set());
      picked.get(id)!.add(i);
    }
    const moved: Stroke[] = items.map(({ id, i }) => {
      const b = blocks.current.find((x) => x.id === id)!;
      const s = b.line.ink!.strokes[i];
      return { ...s, p: s.p.map((v, j) => (j % 3 === 0 ? v + dx : j % 3 === 1 ? v + b.top + dy : v)) };
    });
    // The page as it will be once the strokes leave their lines (emptied lines stay as blank lines).
    let top = 0;
    const after = blocks.current.map((b) => {
      const strokes = (b.line.ink?.strokes ?? []).filter((_, i) => !picked.get(b.id)?.has(i));
      const typed = isTyped(b.line);
      const height = typed ? b.height : Math.max(ROW, inkRows({ strokes }) * ROW);
      const placed = { id: b.id, top, height, typed, strokes };
      top += height;
      return placed;
    });
    const anchor = moved.find((s) => s.k === 'w') ?? moved[0];
    const row = Math.max(0, strokeRow(strokeBox(anchor.p), anchor.k, null, 0));
    const placed = placeStroke(after, top, anchor, row);
    const strokes = moved.map((s) => ({ ...s, r: s.k === 'w' ? rowWithin(s.p, placed.top) : 0, p: s.p.map((v, j) => (j % 3 === 1 ? v - placed.top : v)) }));
    const to = 'join' in placed ? { join: placed.join } : { after: placed.after, blanks: placed.blanks };
    clearSelection();
    flush();
    pushUndo(await write(moveInk(log, slot, new Map([...picked].map(([id, s]) => [id, [...s]])), to, strokes), true));
    soon();
  };

  const deleteSelection = async () => {
    const items = selRef.current?.items ?? [];
    const hits = new Map<string, number[]>();
    for (const { id, i } of items) hits.set(id, [...(hits.get(id) ?? []), i]);
    clearSelection();
    if (hits.size) pushUndo(await write(eraseInk(log, hits), true));
    soon();
  };

  const onPointerDown = (e: React.PointerEvent) => {
    if (e.button > 0 || bulletDown(e)) return;
    if (e.pointerType === 'touch') return;
    e.preventDefault();
    try {
      (e.target as Element).setPointerCapture?.(e.pointerId);
    } catch {
      // not an active pointer (synthetic events)
    }
    drawing.current = true;
    originRect.current = sheet.current!.getBoundingClientRect();
    tool.current = toolRef.current.tool;
    isPen.current = e.pointerType === 'pen';
    points.current = [];
    erased.current = new Map();
    if (tool.current === 'lasso') return lassoDown(e);
    add(e.nativeEvent);
    if (tool.current === 'erase') eraseAt();
    else if (!frame.current) frame.current = requestAnimationFrame(paintLive);
  };

  const onPointerMove = (e: React.PointerEvent) => {
    if (!drawing.current || e.pointerType === 'touch') return;
    if (tool.current === 'lasso') return lassoMove(e);
    add(e.nativeEvent);
    if (tool.current === 'erase') eraseAt();
    else if (!frame.current) frame.current = requestAnimationFrame(paintLive);
  };

  const onPointerUp = async (e: React.PointerEvent) => {
    if (bulletUp(e)) return;
    if (!drawing.current || e.pointerType === 'touch') return;
    originRect.current = null;
    cancelAnimationFrame(frame.current);
    frame.current = 0;
    if (tool.current === 'lasso') return lassoUp();
    if (tool.current === 'erase') {
      const hits = new Map([...erased.current].map(([id, s]) => [id, [...s]]));
      flush();
      if (hits.size) pushUndo(await write(eraseInk(log, hits), true));
      soon();
      return;
    }
    const p = compact(points.current);
    if (p.length < 6) p.push(p[0] + 0.5, p[1] + 0.5, p[2]);
    await commit(p);
  };

  /** Files a finished stroke on the entry of the ruled line it was written on (or a new one below). */
  const commit = async (p: number[]) => {
    const kind = tool.current === 'draw' ? 'd' : 'w';
    const box = strokeBox(p);
    const now = Date.now();
    const recent = lastStroke.current;
    const row = Math.max(0, strokeRow(box, kind, recent, now));
    const draft: Stroke = {
      k: kind,
      c: toolRef.current.color,
      r: 0,
      p,
      ...(isPen.current ? { pen: true } : {}),
      ...(toolRef.current.size !== DEFAULT_SIZE ? { s: toolRef.current.size } : {}),
    };
    const placed = placeStroke(
      blocks.current.map((b) => ({ id: b.id, top: b.top, height: b.height, typed: isTyped(b.line), strokes: b.line.ink?.strokes ?? [] })),
      contentEnd.current,
      draft,
      row,
      recent && now - recent.at < 4000 ? recent.id : null,
    );
    const top = placed.top;
    // Stored to 0.1 px and 2-digit pressure: the raw floats (17 digits each) made a long paragraph several
    // times larger to store and sync, with no visible difference.
    const local = p.map((v, i) => (i % 3 === 2 ? Math.round(v * 100) / 100 : Math.round((i % 3 === 1 ? v - top : v) * 10) / 10));
    const r = 'join' in placed ? placed.r : 0;
    const stroke: Stroke = { ...draft, r: kind === 'w' ? r : 0, p: local };
    // Keep the stroke on screen until the page is rebuilt with it.
    const host = sheet.current!;
    const ghost = inkSvg(document, { strokes: [stroke] }, { width: host.clientWidth, height: Math.max(ROW, box.y1 - top + ROW), dy: 0 });
    ghost.classList.add('pen-pending');
    ghost.style.top = `${top}px`;
    host.append(ghost);
    clearLive();
    flush();
    // The layout takes the stroke right away, so the next one (often a few ms later) lands on the same line
    // even before storage answers. Storage keeps the writes in order.
    if ('join' in placed) {
      const target = blocks.current.find((b) => b.id === placed.join)!;
      target.line = { ...target.line, ink: { ...target.line.ink, strokes: [...(target.line.ink?.strokes ?? []), stroke] } };
      if (placed.absorb) blocks.current = blocks.current.filter((b) => b.id !== placed.absorb);
      reflow();
      lastStroke.current = { id: target.id, row, at: now, x0: box.x0, x1: box.x1 };
      pushUndo(await write(addInk(log, target.id, [stroke], placed.absorb)));
    } else {
      const added = [...Array.from({ length: placed.blanks }, () => newLine()), newLine({ ink: { strokes: [stroke] } })];
      const at = placed.after ? blocks.current.findIndex((b) => b.id === placed.after) + 1 : blocks.current.length;
      blocks.current.splice(at, 0, ...added.map((l) => ({ id: l.id, top: 0, height: ROW, line: l })));
      reflow();
      lastStroke.current = { id: added[added.length - 1].id, row, at: now, x0: box.x0, x1: box.x1 };
      pushUndo(await write(addInkLines(log, slot, added, placed.after)));
    }
    soon();
  };

  /** Block positions after a local change (before the page is rebuilt from storage). */
  const reflow = () => {
    let top = 0;
    for (const b of blocks.current) {
      b.top = top;
      b.height = Math.max(b.height, inkRows(b.line.ink) * ROW);
      top += b.height;
    }
    contentEnd.current = top;
  };

  const onUndo = async () => {
    const snap = undo.current.pop();
    setCanUndo(undo.current.length > 0);
    lastStroke.current = null;
    if (snap) await restoreInk(snap);
  };

  return (
    <>
      <div
        ref={sheet}
        className={`pen-sheet${pen.tool === 'draw' ? ' pen-plain' : ''}`}
        role="img"
        aria-label={label}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={() => {
          if (press.current) clearTimeout(press.current.timer);
          press.current = null;
          clearLive();
          flush();
        }}
      >
        <div className="pen-rows" />
        <svg className="pen-live" aria-hidden>
          <path ref={live} />
        </svg>
        {sel && (
          <div
            ref={boxEl}
            className="lasso-box"
            style={{ left: sel.box.x0 - PAD, top: sel.box.y0 - PAD, width: sel.box.x1 - sel.box.x0 + PAD * 2, height: sel.box.y1 - sel.box.y0 + PAD * 2 }}
          >
            <button
              className="lasso-delete"
              aria-label={t.pen.deleteSelection}
              onPointerDown={(e) => e.stopPropagation()}
              onClick={() => void deleteSelection()}
            >
              ×
            </button>
          </div>
        )}
      </div>
      {menu && (
        <StateMenu
          {...menu}
          eventStates={settings.eventStates}
          onPick={(s) => {
            setMenu(null);
            void setState(menu.id, s);
          }}
          onClose={() => setMenu(null)}
        />
      )}
      <PenToolbar canUndo={canUndo} onUndo={onUndo} />
    </>
  );
}

/** What a row looks like: the same signature draws the same row, so it can be reused as is. */
function rowSignature(l: Line, color: LineType, parent: boolean, width: number, doneMark: string): string {
  const ink = l.ink;
  let where = 0;
  for (const s of ink?.strokes ?? []) where += s.p[0] * 3 + s.p[1] + s.p.length + (s.b ? 7 : 0);
  return [
    l.text,
    l.type,
    l.state,
    l.indent,
    l.collapsed,
    l.priority,
    l.inspiration,
    l.explore,
    color,
    parent,
    width,
    doneMark,
    ink?.strokes.length ?? 0,
    ink?.tx ?? '',
    Math.round(where),
  ].join('|');
}

/** Has typed content of its own (not a transcription of its ink): it shows as text in Pen mode and never takes ink. */
export function isTyped(l: Line): boolean {
  // Handwriting that has been transcribed stays handwriting, even after its text was corrected in Type
  // mode: the ink is the original, the text its transcription (a corrected line showed both, overlapping).
  if (hasWriting(l.ink) && l.ink!.tx !== undefined) return false;
  if (l.text.trim()) return true;
  return l.type !== 'text' && !hasWriting(l.ink);
}

/**
 * A transcribed handwritten line shows its state like a typed one: the
 * hand-drawn bullet becomes ×, > or < in the entry's color, done and
 * cancelled lines fade, cancelled ones get a stroke through. The bullet
 * answers taps like a typed bullet.
 */
function decorateHand(row: HTMLElement, l: Line, color: InkColor | undefined, doneMark: 'cross' | 'check') {
  const bulletIdx = l.ink!.strokes.findIndex((s) => s.b);
  row.classList.add(`pen-s-${l.state}`);
  if (bulletIdx < 0) return;
  const b = strokeBox(l.ink!.strokes[bulletIdx].p);
  const cx = (b.x0 + b.x1) / 2;
  const cy = (b.y0 + b.y1) / 2;
  const hit = document.createElement('div');
  hit.className = 'pen-hand-bullet';
  hit.style.left = `${cx - 20}px`;
  hit.style.top = `${cy - 20}px`;
  row.append(hit);
  if (l.state === 'open' || l.state === 'cancelled') {
    if (l.state === 'cancelled') strikeThrough(row, l, bulletIdx, cy);
    return;
  }
  const mark = document.createElement('span');
  mark.className = `pen-hand-mark ink-text-${color ?? 'ink'}`;
  // Done follows Settings › Done mark, like typed bullets.
  mark.textContent = l.state === 'done' && doneMark === 'check' ? '✓' : glyph(l.type, l.state, true);
  mark.style.left = `${cx}px`;
  mark.style.top = `${cy}px`;
  row.append(mark);
}

function strikeThrough(row: HTMLElement, l: Line, bulletIdx: number, y: number) {
  const words = l.ink!.strokes.filter((s, i) => s.k === 'w' && i !== bulletIdx).map((s) => strokeBox(s.p));
  if (!words.length) return;
  const x0 = Math.min(...words.map((w) => w.x0));
  const x1 = Math.max(...words.map((w) => w.x1));
  const strike = document.createElement('span');
  strike.className = 'pen-hand-strike';
  strike.style.left = `${x0}px`;
  strike.style.width = `${x1 - x0}px`;
  strike.style.top = `${y}px`;
  row.append(strike);
}

const MENU_STATES: LineState[] = ['done', 'cancelled', 'migrated', 'scheduled', 'open'];

/** Held bullet: pick a state (one entry at a time, like the bullet menu in Type mode). */
function StateMenu(props: { x: number; y: number; state: LineState; eventStates: boolean; onPick: (s: LineState) => void; onClose: () => void }) {
  useEffect(() => {
    const close = (e: PointerEvent) => !(e.target as Element).closest('.pen-menu') && props.onClose();
    const t0 = window.setTimeout(() => document.addEventListener('pointerdown', close), 0);
    return () => {
      clearTimeout(t0);
      document.removeEventListener('pointerdown', close);
    };
  }, []);
  return (
    <div className="pen-menu" role="menu" style={{ left: Math.max(8, props.x - 8), top: props.y + 6 }}>
      {MENU_STATES.filter((s) => s !== props.state).map((s) => (
        <button key={s} role="menuitem" onClick={() => props.onPick(s)}>
          {t.menu.states[s]}
        </button>
      ))}
    </div>
  );
}

const COLORS: InkColor[] = ['ink', 'task', 'event', 'note'];

function PenToolbar({ canUndo, onUndo }: { canUndo: boolean; onUndo: () => void }) {
  const pen = usePen();
  const tool = (id: PenTool, icon: React.ReactNode) => (
    <button className={`pen-tool${pen.tool === id ? ' on' : ''}`} aria-label={t.pen.tools[id]} aria-pressed={pen.tool === id} onClick={() => setPenTool(id)}>
      {icon}
    </button>
  );
  return (
    <div className="pen-toolbar" role="toolbar" aria-label={t.pen.toolbar}>
      {tool(
        'write',
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round" aria-hidden>
          <path d="M15 4l5 5L9 20H4v-5z" />
        </svg>,
      )}
      {tool(
        'draw',
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" aria-hidden>
          <path d="M4 18c3-6 6 2 9-4s5-6 7-4" />
        </svg>,
      )}
      {tool(
        'erase',
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round" aria-hidden>
          <path d="M9 20h11M4 15l9-9 6 6-8 8H8z" />
        </svg>,
      )}
      {tool(
        'lasso',
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" aria-hidden>
          <ellipse cx="12" cy="10" rx="8" ry="5.5" strokeDasharray="2.6 2.6" />
          <path d="M8 15.5c-1 2.5 0 4.5 2.5 4.5" />
        </svg>,
      )}
      <span className="pen-sep" />
      {PEN_SIZES.map((size) => (
        <button
          key={size}
          className={`pen-tool pen-size${pen.size === size ? ' on' : ''}`}
          aria-label={t.pen.sizes[PEN_SIZES.indexOf(size)]}
          aria-pressed={pen.size === size}
          onClick={() => {
            setPenSize(size);
            if (pen.tool === 'erase') setPenTool('write');
          }}
        >
          <span style={{ height: [1.5, 2.5, 4][PEN_SIZES.indexOf(size)] }} />
        </button>
      ))}
      <span className="pen-sep" />
      {COLORS.map((c) => (
        <button
          key={c}
          className={`pen-color${pen.color === c ? ' on' : ''}`}
          style={{ background: `var(--ink-${c})` }}
          aria-label={t.pen.colors[c]}
          aria-pressed={pen.color === c}
          onClick={() => {
            setPenColor(c);
            if (pen.tool === 'erase') setPenTool('write');
          }}
        />
      ))}
      <span className="pen-sep" />
      <button className="pen-tool" aria-label={t.pen.undo} disabled={!canUndo} onClick={onUndo}>
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" aria-hidden>
          <path d="M9 7L4 12l5 5M4 12h11a5 5 0 010 10h-2" />
        </svg>
      </button>
    </div>
  );
}
