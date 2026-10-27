// Reading the structure of a handwritten line, by geometry alone: the bullet
// drawn at its start (dot = task, small circle = event, dash = note) and how
// far right it starts (indentation). The words themselves go to the recognizer.
import type { LineType } from '../editor/lines';
import { ROW, strokeBox, type Box, type Stroke } from './ink';

/** Where text starts on an unindented line (sheet x), and how far one indent level moves it by hand. */
export const TEXT_X = 60;
export const PEN_STEP = 36;

export interface LineShape {
  type: Exclude<LineType, 'heading'>;
  /** Indexes (in ink.strokes) of the strokes that form the bullet. */
  bullet: number[];
  indent: number;
}

const w = (b: Box) => b.x1 - b.x0;
const h = (b: Box) => b.y1 - b.y0;

function shapeOf(s: Stroke, b: Box): 'task' | 'event' | 'note' | null {
  const size = Math.max(w(b), h(b));
  if (size <= 9) return 'task';
  const n = s.p.length / 3;
  const closed = Math.hypot(s.p[0] - s.p[(n - 1) * 3], s.p[1] - s.p[(n - 1) * 3 + 1]) < Math.max(6, size * 0.45);
  if (size <= 26 && closed && w(b) > 5 && h(b) > 5 && w(b) / h(b) < 2.2 && h(b) / w(b) < 2.2) return 'event';
  if (w(b) >= 6 && w(b) <= 34 && h(b) <= Math.max(5, w(b) / 3)) return 'note';
  return null;
}

/**
 * The leftmost writing stroke is a bullet when it is small, has a clear gap
 * before the words, and looks like a dot, a circle or a dash. Lines without
 * one are free text.
 */
export function readLineShape(strokes: Stroke[]): LineShape {
  // Bullet and indent are read from the entry's first ruled line (a paragraph spans several).
  const writing = strokes.map((s, i) => ({ s, i, b: strokeBox(s.p) })).filter((x) => x.s.k === 'w' && x.s.r === 0);
  if (!writing.length) return { type: 'text', bullet: [], indent: 0 };
  writing.sort((a, b) => a.b.x0 - b.b.x0);
  const first = writing[0];
  const rest = writing.slice(1);
  let type: LineShape['type'] = 'text';
  let bullet: number[] = [];
  let start = first.b.x0;
  if (rest.length) {
    const kind = shapeOf(first.s, first.b);
    const gap = Math.min(...rest.map((x) => x.b.x0)) - first.b.x1;
    if (kind && gap >= 6) {
      type = kind;
      bullet = [first.i];
      // The words start after the bullet; the indent is read from the bullet, which sits in the gutter.
      start = (first.b.x0 + first.b.x1) / 2 + (TEXT_X - 42);
    }
  }
  const indent = Math.max(0, Math.floor((start - TEXT_X + PEN_STEP * 0.6) / PEN_STEP));
  return { type, bullet, indent };
}

// ---------- Where a new stroke goes ----------

export interface PlacedBlock {
  id: string;
  top: number;
  height: number;
  /** Typed text or a typed bullet: handwriting never goes into it. */
  typed: boolean;
  strokes: Stroke[];
}

/** `absorb`: a blank line the stroke was written on, taken over by the paragraph above (it goes away). */
export type Placement = { join: string; r: number; top: number; absorb?: string } | { after: string | null; blanks: number; top: number };

/** Small marks that start a new item when they open a line: a dot, a dash, a small circle left of the text. */
function bulletish(s: Stroke, b: Box, lineStart: number | null): boolean {
  const kind = shapeOf(s, b);
  if (kind === 'task' || kind === 'note') return true;
  return kind === 'event' && Math.max(w(b), h(b)) <= 16 && lineStart !== null && b.x1 <= lineStart + 4;
}

/** Where the last ruled line of a handwritten block starts (its leftmost writing stroke). */
function lastLineStart(block: PlacedBlock): { row: number; x: number } | null {
  const writing = block.strokes.filter((s) => s.k === 'w');
  if (!writing.length) return null;
  const row = Math.max(...writing.map((s) => s.r));
  return { row, x: Math.min(...writing.filter((s) => s.r === row).map((s) => strokeBox(s.p).x0)) };
}

/** The stroke written just before: its ruled line, when, and its sideways extent. */
export type LastStroke = { row: number; at: number; x0: number; x1: number };

/**
 * The ruled line a writing stroke belongs to. Letters sit on the rule and descenders (g, p, q, j) reach
 * into the line below, so the line is read from the top part of the stroke, not its middle. Two
 * corrections use the stroke written just before (within 2.5 s):
 * - a stroke that starts on that stroke's line, right after it, and only reaches down past the rule
 *   stays on it (a tall "p" opening a word was read one line down, and took the next letters with it);
 * - a small mark poking into the line above, over or before that stroke (an accent, an i-dot), stays
 *   with it. A small letter after it (to its right) is not an accent.
 */
export function strokeRow(box: Box, kind: 'w' | 'd', last: LastStroke | null, now: number): number {
  if (kind === 'd') return Math.floor(box.y0 / ROW);
  const ay = box.y0 + Math.min(box.y1 - box.y0, ROW * 0.6) * 0.5;
  const row = Math.floor(ay / ROW);
  const recent = last && now - last.at < 2500 ? last : null;
  if (!recent) return row;
  const sameLine = box.x0 >= recent.x0 - 8 && box.x0 <= recent.x1 + 60;
  if (row === recent.row + 1 && Math.floor(box.y0 / ROW) === recent.row && sameLine) return recent.row;
  const small = box.y1 - box.y0 < ROW * 0.35;
  // Only upward: accents and i-dots sit above their letter. A short word at the start of the next line
  // ("o", "e", "a") is small too, and must stay on its own line.
  if (small && row === recent.row - 1 && box.x0 <= recent.x1 + 4) return recent.row;
  return row;
}

/**
 * Handwriting goes into the entry of the line it was written on, with
 * these rules (Fernando's first real test):
 * - typed entries never take ink: writing on or next to one starts a new
 *   entry right after it;
 * - a handwritten line takes more writing on its own lines, and the line
 *   right below it continues it as a paragraph, unless that new line opens
 *   with a bullet or starts clearly further right (a new item or paragraph);
 * - a blank line takes what is written on it;
 * - drawings get their own entry, except over another drawing or a blank line;
 * - writing over a drawing joins it (text next to a drawing);
 * - below the last line, skipped lines become blank entries, as on paper.
 */
export function placeStroke(blocks: PlacedBlock[], contentEnd: number, s: Stroke, row: number, lastId: string | null = null): Placement {
  const box = strokeBox(s.p);
  const y = row * ROW;
  const i = blocks.findIndex((b) => y >= b.top && y < b.top + b.height);
  const drawingOnly = (b: PlacedBlock) => b.strokes.length > 0 && b.strokes.every((x) => x.k === 'd');
  if (i >= 0) {
    const b = blocks[i];
    const blank = !b.typed && !b.strokes.length;
    // A blank line right under a handwritten paragraph (often left by an Enter in Type mode): writing on it
    // from the margin continues the paragraph, as below the last line of the page.
    const prev = blocks[i - 1];
    if (blank && s.k === 'w' && prev && !prev.typed && !drawingOnly(prev)) {
      const start = lastLineStart(prev);
      if (start && y === prev.top + (start.row + 1) * ROW && !bulletish(s, box, start.x) && box.x0 <= start.x + PEN_STEP * 0.8)
        return { join: prev.id, r: start.row + 1, top: prev.top, absorb: b.id };
    }
    if (b.typed) {
      // The entry just started for writing on this typed line keeps the rest of it (each stroke must not
      // start yet another entry in the same place).
      const next = blocks[i + 1];
      if (next && next.id === lastId && !next.typed) return { join: next.id, r: 0, top: next.top };
      return { after: b.id, blanks: 0, top: b.top + b.height };
    }
    // Over a drawing, writing and drawing both join it: a drawing spans several ruled lines, and writing
    // next to it belongs there (moving each stroke below the drawing scattered the letters).
    if (s.k === 'd') return drawingOnly(b) || blank ? { join: b.id, r: 0, top: b.top } : { after: b.id, blanks: 0, top: b.top + b.height };
    return { join: b.id, r: Math.round((y - b.top) / ROW), top: b.top };
  }
  const blanks = Math.max(0, Math.round((y - contentEnd) / ROW));
  const last = blocks[blocks.length - 1];
  if (s.k === 'w' && blanks === 0 && last && !last.typed && !drawingOnly(last)) {
    const start = lastLineStart(last);
    if (start && !bulletish(s, box, start.x) && box.x0 <= start.x + PEN_STEP * 0.8) return { join: last.id, r: start.row + 1, top: last.top };
  }
  return { after: null, blanks, top: contentEnd + blanks * ROW };
}

// ---------- Lasso ----------

function inside(x: number, y: number, poly: Array<[number, number]>): boolean {
  let hit = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i];
    const [xj, yj] = poly[j];
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) hit = !hit;
  }
  return hit;
}

/** Strokes the lasso goes around: most of their points inside the loop (page coordinates). */
export function lassoed(blocks: Array<Pick<PlacedBlock, 'id' | 'top' | 'strokes'>>, loop: Array<[number, number]>): Array<{ id: string; i: number }> {
  if (loop.length < 3) return [];
  const out: Array<{ id: string; i: number }> = [];
  for (const b of blocks)
    b.strokes.forEach((s, i) => {
      let n = 0;
      let k = 0;
      for (let j = 0; j < s.p.length; j += 3, n++) if (inside(s.p[j], s.p[j + 1] + b.top, loop)) k++;
      if (n && k / n >= 0.6) out.push({ id: b.id, i });
    });
  return out;
}

/** A writing stroke's ruled line within an entry starting at `top` (see strokeRow). */
export function rowWithin(p: number[], top: number): number {
  const b = strokeBox(p);
  return Math.max(0, Math.floor((b.y0 - top + Math.min(b.y1 - b.y0, ROW * 0.6) * 0.5) / ROW));
}
