// Reading the structure of a handwritten line, by geometry alone: the bullet
// drawn at its start (dot = task, small circle = event, dash = note) and how
// far right it starts (indentation). The words themselves go to the recognizer.
import type { LineType } from '../editor/lines';
import { strokeBox, type Box, type Stroke } from './ink';

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
  const writing = strokes.map((s, i) => ({ s, i, b: strokeBox(s.p) })).filter((x) => x.s.k === 'w');
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
