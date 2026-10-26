// Pen mode: the page as a ruled sheet you write and draw on with the pen.
// Each ruled line is an entry: writing on a line adds to that entry, writing
// below the last line starts a new one. Typed entries sit on the same lines.
// Fingers scroll; only the pen (or a mouse) leaves ink. Bullets of typed
// entries still work: a tap cycles the state, holding opens the states menu.
import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { addInk, addInkLines, eraseInk, markInkState, restoreInk, usePageLines, useSettings, type InkSnapshot, type LogRef } from '../data/repo';
import { playDoneFx } from '../editor/doneFx';
import { colorTypes, hasChildren, hasStates, hiddenMask, newLine, nextState, type Line, type LineState } from '../editor/lines';
import { buildGutter, fillText, lineClass } from '../editor/render';
import { t } from '../i18n/en';
import { compact, hasInk, inkRows, inkSvg, ROW, rowOf, strokeBox, strokeHit, strokePath, type Stroke } from './ink';
import { setPenColor, setPenTool, usePen, type PenTool } from './penStore';
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
  const settings = useSettings();
  const [menu, setMenu] = useState<{ id: string; x: number; y: number; state: LineState } | null>(null);
  const blocks = useRef<Block[]>([]);
  const contentEnd = useRef(0);
  const drawing = useRef(false);
  const deferred = useRef<Line[] | null>(null);
  const undo = useRef<InkSnapshot[]>([]);
  const [canUndo, setCanUndo] = useState(false);
  const lastStroke = useRef<{ id: string; r: number; at: number } | null>(null);
  const toolRef = useRef(pen);
  toolRef.current = pen;

  /** Lays the page out as ruled blocks: one per visible entry, as many lines tall as its text or ink. */
  const build = (ls: Line[]) => {
    const host = sheet.current;
    if (!host) return;
    const colors = colorTypes(ls);
    const hidden = hiddenMask(ls);
    const rows = host.querySelector<HTMLElement>('.pen-rows')!;
    rows.replaceChildren();
    host.querySelectorAll('.pen-pending').forEach((el) => el.remove());
    const width = host.clientWidth;
    let top = 0;
    const out: Block[] = [];
    ls.forEach((l, i) => {
      if (hidden[i]) return;
      const row = document.createElement('div');
      row.className = 'pen-row';
      row.dataset.id = l.id;
      const typed = l.text.trim() !== '' || l.type !== 'text';
      let typedRows = 0;
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
      rows.append(row);
      if (typed) typedRows = Math.ceil((row.firstElementChild as HTMLElement).offsetHeight / ROW - 0.05);
      const n = Math.max(1, typedRows, inkRows(l.ink));
      row.style.height = `${n * ROW}px`;
      if (hasInk(l.ink)) {
        const svg = inkSvg(document, l.ink, { width, height: n * ROW });
        svg.classList.add('pen-ink');
        row.append(svg);
      }
      out.push({ id: l.id, top, height: n * ROW, line: l });
      top += n * ROW;
    });
    blocks.current = out;
    contentEnd.current = top;
    const spare = Math.max(SPARE_ROWS, Math.ceil((window.innerHeight - host.getBoundingClientRect().top - top) / ROW));
    host.style.minHeight = `${top + spare * ROW}px`;
  };

  useLayoutEffect(() => {
    if (!lines) return;
    if (drawing.current) deferred.current = lines;
    else build(lines);
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

  const pushUndo = (snap: InkSnapshot) => {
    if (!snap.size) return;
    undo.current.push(snap);
    if (undo.current.length > 100) undo.current.shift();
    setCanUndo(true);
  };

  const flush = () => {
    drawing.current = false;
    if (deferred.current) {
      build(deferred.current);
      deferred.current = null;
    }
  };

  // ---------- one stroke ----------

  const points = useRef<number[]>([]);
  const erased = useRef<Map<string, Set<number>>>(new Map());
  const frame = useRef(0);
  const tool = useRef<PenTool>('write');
  const isPen = useRef(false);

  const origin = () => sheet.current!.getBoundingClientRect();

  // The stroke in progress is drawn in the sheet's own coordinates (the same as the stored ink),
  // so it appears exactly under the pen tip.
  const paintLive = () => {
    frame.current = 0;
    const path = live.current;
    if (!path || tool.current === 'erase') return;
    path.setAttribute('class', `ink-${toolRef.current.color}`);
    path.setAttribute('d', strokePath({ k: tool.current === 'draw' ? 'd' : 'w', p: points.current, pen: isPen.current }));
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
    const bullet = (e.target as Element).closest('.pen-typed .bullet');
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

  const onPointerDown = (e: React.PointerEvent) => {
    if (e.button > 0 || bulletDown(e)) return;
    if (e.pointerType === 'touch') return;
    e.preventDefault();
    (e.target as Element).setPointerCapture?.(e.pointerId);
    drawing.current = true;
    tool.current = toolRef.current.tool;
    isPen.current = e.pointerType === 'pen';
    points.current = [];
    erased.current = new Map();
    add(e.nativeEvent);
    if (tool.current === 'erase') eraseAt();
    else if (!frame.current) frame.current = requestAnimationFrame(paintLive);
  };

  const onPointerMove = (e: React.PointerEvent) => {
    if (!drawing.current || e.pointerType === 'touch') return;
    add(e.nativeEvent);
    if (tool.current === 'erase') eraseAt();
    else if (!frame.current) frame.current = requestAnimationFrame(paintLive);
  };

  const onPointerUp = async (e: React.PointerEvent) => {
    if (bulletUp(e)) return;
    if (!drawing.current || e.pointerType === 'touch') return;
    cancelAnimationFrame(frame.current);
    frame.current = 0;
    if (tool.current === 'erase') {
      const hits = new Map([...erased.current].map(([id, s]) => [id, [...s]]));
      flush();
      if (hits.size) pushUndo(await eraseInk(log, hits));
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
    const anchor = kind === 'w' ? (box.y0 + box.y1) / 2 : box.y0;
    const now = Date.now();
    const target = blocks.current.find((b) => anchor < b.top + b.height && anchor >= b.top - (b === blocks.current[0] ? ROW : 0));
    const top = target ? target.top : contentEnd.current + Math.max(0, Math.floor((anchor - contentEnd.current) / ROW)) * ROW;
    const local = p.map((v, i) => (i % 3 === 1 ? v - top : v));
    const prev = lastStroke.current && (target ? lastStroke.current.id === target.id : false) ? lastStroke.current : null;
    const r = kind === 'w' ? rowOf(strokeBox(local), prev, now) : 0;
    const stroke: Stroke = { k: kind, c: toolRef.current.color, r, p: local, ...(isPen.current ? { pen: true } : {}) };
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
    if (target) {
      target.line = { ...target.line, ink: { strokes: [...(target.line.ink?.strokes ?? []), stroke] } };
      reflow();
      lastStroke.current = { id: target.id, r, at: now };
      pushUndo(await addInk(log, target.id, [stroke]));
    } else {
      const blanks = Math.round((top - contentEnd.current) / ROW);
      const added = [...Array.from({ length: blanks }, () => newLine()), newLine({ ink: { strokes: [stroke] } })];
      for (const l of added) blocks.current.push({ id: l.id, top: 0, height: ROW, line: l });
      reflow();
      const id = added[added.length - 1].id;
      lastStroke.current = { id, r, at: now };
      pushUndo(await addInkLines(log, slot, added));
    }
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
        className="pen-sheet"
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
