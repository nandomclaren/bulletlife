// Handwriting and drawings made with the pen (Pen mode). Strokes are stored
// as vectors on the entry they were written on, so they scale cleanly and
// can later be transcribed (writing) or kept as a picture (drawing).
import { getStroke } from 'perfect-freehand';

/** Height of one ruled line in Pen mode, in CSS px. */
export const ROW = 40;

/** 'w' = writing (one row; transcribed later), 'd' = drawing (never transcribed). */
export type StrokeKind = 'w' | 'd';
/** Colors are theme tokens, so ink re-colors with the theme. */
export type InkColor = 'ink' | 'task' | 'event' | 'note';

export interface Stroke {
  k: StrokeKind;
  c: InkColor;
  /** Writing: the ruled row (within the entry) the stroke belongs to. */
  r: number;
  /** Flat [x, y, pressure, ...]: x from the sheet's left edge, y from the entry's top. */
  p: number[];
  /** Pressure came from a real pen (otherwise it is simulated from speed). */
  pen?: boolean;
  /** The hand-drawn bullet of the line (found when transcribing): drawn in the entry's color. */
  b?: boolean;
  /** Pen size (stroke diameter, px) when not the default. */
  s?: number;
}

export interface Ink {
  strokes: Stroke[];
  /** Text the last transcription wrote; while the entry's text still equals it, a new transcription may replace it. */
  tx?: string;
  /** Writing strokes the last transcription read; a different count means the ink changed since. */
  n?: number;
  /** A drawing's size and place in Type mode, when the user moved or resized it there. */
  view?: { w: number; x: number };
}

export const writingCount = (ink: Ink | undefined) => ink?.strokes.filter((s) => s.k === 'w').length ?? 0;
export const hasWriting = (ink: Ink | undefined) => writingCount(ink) > 0;
/** Needs (re)transcribing: has writing the last transcription did not read. */
export const needsTranscription = (ink: Ink | undefined) => hasWriting(ink) && ink!.n !== writingCount(ink);

export const hasInk = (ink: Ink | undefined): ink is Ink => !!ink && ink.strokes.length > 0;

export interface Box {
  x0: number;
  y0: number;
  x1: number;
  y1: number;
}

export function strokeBox(p: number[]): Box {
  const b = { x0: Infinity, y0: Infinity, x1: -Infinity, y1: -Infinity };
  for (let i = 0; i < p.length; i += 3) {
    b.x0 = Math.min(b.x0, p[i]);
    b.x1 = Math.max(b.x1, p[i]);
    b.y0 = Math.min(b.y0, p[i + 1]);
    b.y1 = Math.max(b.y1, p[i + 1]);
  }
  return b;
}

export function inkBox(ink: Ink): Box | null {
  if (!hasInk(ink)) return null;
  return ink.strokes
    .map((s) => strokeBox(s.p))
    .reduce((a, b) => ({ x0: Math.min(a.x0, b.x0), y0: Math.min(a.y0, b.y0), x1: Math.max(a.x1, b.x1), y1: Math.max(a.y1, b.y1) }));
}

/**
 * Ruled rows an entry's ink takes. Writing counts the rows its strokes were
 * written on (descenders reaching into the next line don't add one);
 * drawings count every row they cover.
 */
export function inkRows(ink: Ink | undefined): number {
  if (!hasInk(ink)) return 0;
  let rows = 0;
  for (const s of ink.strokes) rows = Math.max(rows, s.k === 'w' ? s.r + 1 : Math.ceil((strokeBox(s.p).y1 + 4) / ROW));
  return rows;
}

/** Rounds points so stored ink stays small: 0.1 px and 0.01 pressure. */
export function compact(points: number[]): number[] {
  return points.map((v, i) => (i % 3 === 2 ? Math.round(v * 100) / 100 : Math.round(v * 10) / 10));
}

/** Whether a stroke passes within `radius` of any point of the eraser path. */
export function strokeHit(p: number[], dy: number, eraser: Array<[number, number]>, radius: number): boolean {
  const r2 = radius * radius;
  for (let i = 0; i < p.length; i += 3) {
    const x = p[i];
    const y = p[i + 1] + dy;
    for (const [ex, ey] of eraser) if ((x - ex) ** 2 + (y - ey) ** 2 <= r2) return true;
  }
  return false;
}

/** Pen sizes in the toolbar (stroke diameter, px): fine, medium, bold. */
export const PEN_SIZES = [1.8, 2.4, 3.4] as const;
export const DEFAULT_SIZE = 2.4;

/** SVG path of a stroke's outline (variable width from pressure). */
export function strokePath(s: Pick<Stroke, 'k' | 'p' | 'pen' | 's'>, dy = 0, scale = 1): string {
  const pts: number[][] = [];
  for (let i = 0; i < s.p.length; i += 3) pts.push([s.p[i] * scale, (s.p[i + 1] + dy) * scale, s.p[i + 2]]);
  const outline = getStroke(pts, {
    // A fine ballpoint feel: little width change with pressure, smooth curves.
    size: (s.s ?? DEFAULT_SIZE) * Math.max(scale, 0.6),
    thinning: 0.35,
    smoothing: 0.65,
    streamline: 0.45,
    simulatePressure: !s.pen,
    last: true,
  });
  if (!outline.length) return '';
  const d = outline.map(([x, y], i) => `${i ? 'L' : 'M'}${x.toFixed(1)} ${y.toFixed(1)}`);
  return `${d.join('')}Z`;
}

const SVG = 'http://www.w3.org/2000/svg';

/** An <svg> holding these strokes, positioned by the caller. */
export function inkSvg(
  doc: Document,
  ink: Ink,
  opts: { width: number; height: number; dx?: number; dy?: number; scale?: number; bulletColor?: InkColor },
): SVGSVGElement {
  const svg = doc.createElementNS(SVG, 'svg');
  svg.setAttribute('class', 'ink-svg');
  svg.setAttribute('width', String(opts.width));
  svg.setAttribute('height', String(opts.height));
  svg.setAttribute('aria-hidden', 'true');
  const scale = opts.scale ?? 1;
  const g = doc.createElementNS(SVG, 'g');
  if (opts.dx || opts.dy) g.setAttribute('transform', `translate(${(opts.dx ?? 0) * scale} ${(opts.dy ?? 0) * scale})`);
  ink.strokes.forEach((s, i) => {
    const path = doc.createElementNS(SVG, 'path');
    path.setAttribute('d', strokePath(s, 0, scale));
    path.setAttribute('class', s.b ? `ink-${opts.bulletColor ?? s.c} ink-b` : `ink-${s.c}`);
    path.dataset.i = String(i);
    g.append(path);
  });
  svg.append(g);
  return svg;
}
