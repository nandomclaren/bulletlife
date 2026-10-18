// Editor-agnostic line model shared by both editor prototypes.
// A page is a flat list of lines with an indent level; parents are derived
// (the nearest previous line with a smaller indent), which maps 1:1 to Entry.
import { ulid } from 'ulid';

export type LineType = 'task' | 'event' | 'note' | 'text' | 'heading';
export type LineState = 'open' | 'done' | 'cancelled' | 'migrated' | 'scheduled';

export interface Line {
  id: string;
  type: LineType;
  state: LineState;
  indent: number;
  collapsed: boolean;
  priority: boolean;
  text: string;
}

export interface Prefixes {
  task: string;
  event: string;
  note: string;
  heading: string;
  priority: string;
}

export const DEFAULT_PREFIXES: Prefixes = { task: '.', event: 'o.', note: '-', heading: '#', priority: '*' };

export function newLine(partial: Partial<Line> = {}): Line {
  return { id: ulid(), type: 'text', state: 'open', indent: 0, collapsed: false, priority: false, text: '', ...partial };
}

export interface PrefixMatch {
  type: LineType;
  priority: boolean;
  /** Characters consumed, including the trailing space. */
  length: number;
}

/**
 * Recognizes a rapid-logging prefix at the very start of a line, typed up to
 * and including the trailing space: ". ", "o. ", "- ", "# ", optionally
 * preceded by "* " for priority. "* " alone marks priority on the current type.
 */
export function matchPrefix(textBeforeCaret: string, prefixes: Prefixes = DEFAULT_PREFIXES): PrefixMatch | null {
  if (!textBeforeCaret.endsWith(' ')) return null;
  let rest = textBeforeCaret;
  let priority = false;
  let consumed = 0;
  const prio = `${prefixes.priority} `;
  if (rest.startsWith(prio)) {
    priority = true;
    rest = rest.slice(prio.length);
    consumed += prio.length;
  }
  const kinds: Array<[Exclude<LineType, 'text'>, string]> = [
    ['event', prefixes.event],
    ['task', prefixes.task],
    ['note', prefixes.note],
    ['heading', prefixes.heading],
  ];
  for (const [type, p] of kinds) {
    if (rest === `${p} `) {
      if (type === 'heading' && priority) return null;
      return { type, priority, length: consumed + p.length + 1 };
    }
  }
  if (priority && rest === '') return { type: 'text', priority: true, length: consumed };
  return null;
}

export function hasStates(type: LineType, eventStates: boolean) {
  return type === 'task' || (type === 'event' && eventStates);
}

/** Tap cycle: open → done → cancelled → open. Migrated/scheduled go back to open. */
export function nextState(state: LineState): LineState {
  if (state === 'open') return 'done';
  if (state === 'done') return 'cancelled';
  return 'open';
}

export function glyph(type: LineType, state: LineState, eventStates: boolean): string {
  if (type === 'note') return '–';
  if (type === 'text' || type === 'heading') return '';
  const stateful = hasStates(type, eventStates);
  if (stateful && state === 'done') return '×';
  if (stateful && state === 'migrated') return '>';
  if (stateful && state === 'scheduled') return '<';
  return type === 'task' ? '•' : '○';
}

/** Color comes from the root line's type; children inherit it. */
export function colorTypes(lines: Pick<Line, 'type' | 'indent'>[]): Array<LineType> {
  const stack: Array<{ indent: number; color: LineType }> = [];
  return lines.map((l) => {
    while (stack.length && stack[stack.length - 1].indent >= l.indent) stack.pop();
    const color = stack.length ? stack[0].color : l.type;
    stack.push({ indent: l.indent, color });
    return color;
  });
}

export function parentIds(lines: Pick<Line, 'id' | 'indent'>[]): Array<string | null> {
  const stack: Array<{ indent: number; id: string }> = [];
  return lines.map((l) => {
    while (stack.length && stack[stack.length - 1].indent >= l.indent) stack.pop();
    const parent = stack.length ? stack[stack.length - 1].id : null;
    stack.push({ indent: l.indent, id: l.id });
    return parent;
  });
}

export function hasChildren(lines: Pick<Line, 'indent'>[], i: number) {
  return i + 1 < lines.length && lines[i + 1].indent > lines[i].indent;
}

/** Index just past the subtree of line i. */
export function subtreeEnd(lines: Pick<Line, 'indent'>[], i: number) {
  let j = i + 1;
  while (j < lines.length && lines[j].indent > lines[i].indent) j++;
  return j;
}

/** Which lines are hidden because an ancestor is collapsed. */
export function hiddenMask(lines: Pick<Line, 'indent' | 'collapsed'>[]): boolean[] {
  const hidden = new Array<boolean>(lines.length).fill(false);
  for (let i = 0; i < lines.length; i++) {
    if (hidden[i] || !lines[i].collapsed) continue;
    const end = subtreeEnd(lines, i);
    for (let j = i + 1; j < end; j++) hidden[j] = true;
  }
  return hidden;
}

/** Max indent a line can take: one deeper than the line above it. */
export function maxIndent(lines: Pick<Line, 'indent'>[], i: number) {
  return i === 0 ? 0 : lines[i - 1].indent + 1;
}

/** Type of a new line created by Enter at the end of `from`. */
export function continuationType(from: LineType): LineType {
  return from === 'heading' ? 'text' : from;
}

export interface EntryLike {
  id: string;
  parentId: string | null;
  type: LineType;
  state: LineState;
  text: string;
  signifiers: Array<'priority'>;
  collapsed: boolean;
}

export function toEntries(lines: Line[]): EntryLike[] {
  const parents = parentIds(lines);
  return lines.map((l, i) => ({
    id: l.id,
    parentId: parents[i],
    type: l.type,
    state: l.state,
    text: l.text,
    signifiers: l.priority ? ['priority'] : [],
    collapsed: l.collapsed,
  }));
}

export const SAMPLE_LINES: Line[] = [
  newLine({ type: 'heading', text: 'Sun, Oct 18' }),
  newLine({ type: 'task', text: 'Call the bank about the card', priority: true }),
  newLine({ type: 'task', text: 'Ask about the annual fee', indent: 1 }),
  newLine({ type: 'note', text: 'They close at 6 on weekdays', indent: 2 }),
  newLine({ type: 'event', text: 'Dinner with Ana at 8' }),
  newLine({ type: 'task', text: 'Buy bread', state: 'done' }),
  newLine({ type: 'note', text: 'Rain tomorrow, take the umbrella' }),
  newLine({ type: 'text', text: 'Slow morning. Long walk by the river before work.' }),
  newLine({ type: 'task', text: '' }),
];

/**
 * Indent (+1) or outdent (-1) lines from..to (inclusive) together with the
 * subtree of the last one. Returns the new indents, or null when not allowed.
 */
export function shiftIndent(lines: Pick<Line, 'indent'>[], from: number, to: number, delta: 1 | -1): number[] | null {
  const end = subtreeEnd(lines, to);
  const indents = lines.map((l) => l.indent);
  if (delta === 1 && lines[from].indent + 1 > maxIndent(lines, from)) return null;
  if (delta === -1 && lines[from].indent === 0) return null;
  for (let i = from; i < end; i++) indents[i] = Math.max(0, indents[i] + delta);
  return indents;
}
