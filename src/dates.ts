// Calendar math on plain ISO strings ('2026-10-18'), in local time.
// Periods: day '2026-10-18', week '2026-W43', month '2026-10', year '2026'.

export type Weekday = 0 | 1 | 2 | 3 | 4 | 5 | 6; // 0 = Sunday

const pad = (n: number) => String(n).padStart(2, '0');

export function toIso(d: Date): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

export function fromIso(iso: string): Date {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(y, m - 1, d, 12); // noon: immune to DST edges
}

export function todayIso(now = new Date()): string {
  return toIso(now);
}

export function addDays(iso: string, n: number): string {
  const d = fromIso(iso);
  d.setDate(d.getDate() + n);
  return toIso(d);
}

export function monthOf(iso: string): string {
  return iso.slice(0, 7);
}

export function yearOf(iso: string): string {
  return iso.slice(0, 4);
}

export function daysInMonth(ym: string): number {
  const [y, m] = ym.split('-').map(Number);
  return new Date(y, m, 0).getDate();
}

export function addMonths(ym: string, n: number): string {
  const [y, m] = ym.split('-').map(Number);
  const d = new Date(y, m - 1 + n, 1, 12);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}`;
}

export function monthDays(ym: string): string[] {
  return Array.from({ length: daysInMonth(ym) }, (_, i) => `${ym}-${pad(i + 1)}`);
}

export function weekStart(iso: string, firstDay: Weekday): string {
  const d = fromIso(iso);
  const back = (d.getDay() - firstDay + 7) % 7;
  return addDays(iso, -back);
}

/** ISO-8601 week number and week-year of a date. */
export function isoWeek(iso: string): { year: number; week: number } {
  const d = fromIso(iso);
  const day = (d.getDay() + 6) % 7; // Monday = 0
  d.setDate(d.getDate() - day + 3); // Thursday of this week
  const year = d.getFullYear();
  const jan4 = new Date(year, 0, 4, 12);
  const week = 1 + Math.round(((d.getTime() - jan4.getTime()) / 86_400_000 - 3 + ((jan4.getDay() + 6) % 7)) / 7);
  return { year, week };
}

/**
 * Week key for the week containing `iso`. Weeks are numbered like ISO weeks;
 * a Sunday-first week takes the number of the Monday that follows its Sunday.
 */
export function weekKey(iso: string, firstDay: Weekday): string {
  const start = weekStart(iso, firstDay);
  const monday = addDays(start, (1 - firstDay + 7) % 7);
  const { year, week } = isoWeek(monday);
  return `${year}-W${pad(week)}`;
}

/** First day of a week key. */
export function weekKeyStart(key: string, firstDay: Weekday): string {
  const [y, w] = key.split('-W').map(Number);
  const jan4 = toIso(new Date(y, 0, 4, 12));
  const mondayW1 = addDays(jan4, -((fromIso(jan4).getDay() + 6) % 7));
  const monday = addDays(mondayW1, (w - 1) * 7);
  return addDays(monday, -((1 - firstDay + 7) % 7));
}

export function weekDays(key: string, firstDay: Weekday): string[] {
  const start = weekKeyStart(key, firstDay);
  return Array.from({ length: 7 }, (_, i) => addDays(start, i));
}

export function addWeeks(key: string, n: number, firstDay: Weekday): string {
  return weekKey(addDays(weekKeyStart(key, firstDay), n * 7), firstDay);
}

export function weekNumber(key: string): number {
  return Number(key.split('-W')[1]);
}

const fmtCache = new Map<string, Intl.DateTimeFormat>();
export function fmt(iso: string, opts: Intl.DateTimeFormatOptions): string {
  const k = JSON.stringify(opts);
  let f = fmtCache.get(k);
  if (!f) fmtCache.set(k, (f = new Intl.DateTimeFormat('en', opts)));
  return f.format(fromIso(iso));
}
