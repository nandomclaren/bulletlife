// Due dates written in the text: "due:" followed by a date the user types
// (2026-10-23, 23/10, today, tomorrow, fri, next monday, in 3 days...). Once
// the word is finished it is stored as "due:YYYY-MM-DD" (a written "tomorrow"
// must not drift) and shown as a small pill. Pure and unit tested.
import { addDays, addMonths, fmt, fromIso, weekStart, yearOf, type Weekday } from '../dates';
import { t } from '../i18n/en';
import { parentIds, subtreeEnd, type Line } from './lines';

/** Settings › Date format: how a short date is typed and shown (day or month first). */
export type DateOrder = 'dmy' | 'mdy';

export const DUE_TOKEN = /\bdue:(\d{4}-\d{2}-\d{2})(?![\w-])/g;

/** First due date written in a text, as 'YYYY-MM-DD'. */
export function dueOf(text: string): string | undefined {
  const m = text.match(/\bdue:(\d{4}-\d{2}-\d{2})(?![\w-])/);
  return m ? m[1] : undefined;
}

const pad = (n: number) => String(n).padStart(2, '0');

function validIso(y: number, m: number, d: number): string | null {
  if (m < 1 || m > 12 || d < 1) return null;
  if (d > new Date(y, m, 0).getDate()) return null;
  return `${y}-${pad(m)}-${pad(d)}`;
}

const DAYS = ['sun(?:day)?', 'mon(?:day)?', 'tue(?:s|sday)?', 'wed(?:nesday)?', 'thu(?:r|rs|rsday)?', 'fri(?:day)?', 'sat(?:urday)?'];
const END = '(?=$|[\\s,.;:!?)\\]])';

interface Rule {
  re: RegExp;
  date: (m: RegExpMatchArray, today: string, order: DateOrder, firstDay: Weekday) => string | null;
}

const RULES: Rule[] = [
  { re: new RegExp(`^(\\d{4})-(\\d{1,2})-(\\d{1,2})${END}`, 'i'), date: (m) => validIso(+m[1], +m[2], +m[3]) },
  {
    // Short date, this year. A day/month that only makes sense the other way round is read that way.
    re: new RegExp(`^(\\d{1,2})[-/.](\\d{1,2})${END}`, 'i'),
    date: (m, today, order) => {
      const y = +yearOf(today);
      const [a, b] = [+m[1], +m[2]];
      return order === 'dmy' ? (validIso(y, b, a) ?? validIso(y, a, b)) : (validIso(y, a, b) ?? validIso(y, b, a));
    },
  },
  { re: new RegExp(`^(?:today|tod)${END}`, 'i'), date: (_m, today) => today },
  { re: new RegExp(`^(?:tomorrow|tmrw|tmr|tom)${END}`, 'i'), date: (_m, today) => addDays(today, 1) },
  { re: new RegExp(`^(?:yesterday|yday)${END}`, 'i'), date: (_m, today) => addDays(today, -1) },
  { re: new RegExp(`^next\\s+week${END}`, 'i'), date: (_m, today, _o, firstDay) => addDays(weekStart(today, firstDay), 7) },
  { re: new RegExp(`^next\\s+month${END}`, 'i'), date: (_m, today) => `${addMonths(today.slice(0, 7), 1)}-01` },
  {
    re: new RegExp(`^in\\s+(\\d{1,3})\\s+(days?|weeks?|months?)${END}`, 'i'),
    date: (m, today) => {
      const n = +m[1];
      const unit = m[2].toLowerCase();
      if (unit.startsWith('day')) return addDays(today, n);
      if (unit.startsWith('week')) return addDays(today, n * 7);
      const ym = addMonths(today.slice(0, 7), n);
      const day = Math.min(+today.slice(8), new Date(+ym.slice(0, 4), +ym.slice(5), 0).getDate());
      return `${ym}-${pad(day)}`;
    },
  },
  {
    // "fri": the coming Friday (today if it is Friday); "next fri": strictly after today.
    re: new RegExp(`^(next\\s+)?(${DAYS.join('|')})${END}`, 'i'),
    date: (m, today) => {
      const target = DAYS.findIndex((d) => new RegExp(`^${d}$`, 'i').test(m[2]));
      const diff = (target - fromIso(today).getDay() + 7) % 7;
      return addDays(today, diff === 0 && m[1] ? 7 : diff);
    },
  },
];

/** Reads the date expression at the start of `rest`; null when it is not (yet) a whole date. */
export function parseDueExpr(rest: string, today: string, order: DateOrder = 'dmy', firstDay: Weekday = 1): { iso: string; length: number } | null {
  for (const rule of RULES) {
    const m = rest.match(rule.re);
    if (!m) continue;
    const iso = rule.date(m, today, order, firstDay);
    if (iso) return { iso, length: m[0].length };
  }
  return null;
}

/**
 * Turns every finished "due:<expression>" ending at or before `upTo` into
 * "due:YYYY-MM-DD". Returns the new text and how far `upTo` moved, or null if
 * nothing changed.
 */
export function resolveDue(
  text: string,
  today: string,
  order: DateOrder = 'dmy',
  firstDay: Weekday = 1,
  upTo = text.length,
): { text: string; shift: number } | null {
  const re = /\bdue:/gi;
  let out = '';
  let last = 0;
  let shift = 0;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text))) {
    const start = m.index + m[0].length;
    const rest = text.slice(start);
    if (/^\d{4}-\d{2}-\d{2}(?![\w-])/.test(rest) && m[0] === 'due:') continue;
    const parsed = parseDueExpr(rest, today, order, firstDay);
    if (!parsed || start + parsed.length > upTo) continue;
    const token = `due:${parsed.iso}`;
    out += text.slice(last, m.index) + token;
    last = start + parsed.length;
    shift += token.length - (last - m.index);
  }
  if (!last) return null;
  return { text: out + text.slice(last), shift };
}

export type DueStatus = 'overdue' | 'today' | 'future';

export function dueStatus(iso: string, today: string): DueStatus {
  return iso < today ? 'overdue' : iso === today ? 'today' : 'future';
}

/** "Today", "Tomorrow", "Yesterday", else "23 Oct" / "Oct 23" (+ year when not this year). */
export function dueLabel(iso: string, today: string, order: DateOrder = 'dmy'): string {
  if (iso === today) return t.due.today;
  if (iso === addDays(today, 1)) return t.due.tomorrow;
  if (iso === addDays(today, -1)) return t.due.yesterday;
  const day = fmt(iso, { day: 'numeric' });
  const month = fmt(iso, { month: 'short' });
  const base = order === 'dmy' ? `${day} ${month}` : `${month} ${day}`;
  return yearOf(iso) === yearOf(today) ? base : `${base} ${yearOf(iso)}`;
}

// ---------- Sorting a list by date (on request) ----------

const bulleted = (l: Pick<Line, 'type'>) => l.type === 'task' || l.type === 'event' || l.type === 'note';

export interface DateRun {
  /** Indices of the sibling items, in page order. */
  items: number[];
  sorted: boolean;
}

/**
 * Sequences of two or more sibling bullets (same parent, children in between)
 * where at least one has a due date. Each can be sorted by date on request.
 */
export function dateRuns(lines: Line[]): DateRun[] {
  const parents = parentIds(lines);
  const seen = new Set<number>();
  const runs: DateRun[] = [];
  lines.forEach((l, i) => {
    if (seen.has(i) || !bulleted(l)) return;
    const items = [i];
    let k = subtreeEnd(lines, i);
    while (k < lines.length && lines[k].indent === l.indent && parents[k] === parents[i] && bulleted(lines[k])) {
      items.push(k);
      k = subtreeEnd(lines, k);
    }
    items.forEach((x) => seen.add(x));
    const dues = items.map((x) => dueOf(lines[x].text));
    if (items.length < 2 || !dues.some(Boolean)) return;
    const keys = dues.map((d) => d ?? '￿');
    runs.push({ items, sorted: keys.every((k2, x) => x === 0 || keys[x - 1] <= k2) });
  });
  return runs;
}

/** The run sorted by date, nearest first; items without a date go last in their order. Children move with their item. */
export function sortRun(lines: Line[], run: DateRun): Line[] {
  const blocks = run.items.map((i) => lines.slice(i, subtreeEnd(lines, i)));
  const key = (b: Line[]) => dueOf(b[0].text) ?? '￿';
  const sorted = blocks
    .map((b, i) => [b, i] as const)
    .sort((a, b) => (key(a[0]) < key(b[0]) ? -1 : key(a[0]) > key(b[0]) ? 1 : a[1] - b[1]))
    .map(([b]) => b);
  const start = run.items[0];
  const end = subtreeEnd(lines, run.items[run.items.length - 1]);
  return [...lines.slice(0, start), ...sorted.flat(), ...lines.slice(end)];
}
