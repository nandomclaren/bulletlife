// Open items (CLAUDE.md 4): a query derived from the entries, never stored.
// Shows what is loose; resolving anything is always the user's own gesture.
// Also the suggested destination of a > or < mark, shown read-only.
// Pure and unit tested.
import { addDays, addMonths, daysInMonth, fmt, fromIso, monthOf, weekKey, weekKeyStart, yearOf, type Weekday } from '../dates';
import { t } from '../i18n/en';
import type { Entry, LogKind, Settings } from './types';

export type OpenCategory = 'ended' | 'unplaced' | 'arrived';

export interface Source {
  logId: string;
  kind: LogKind;
  /** Period key ('2026-10-18', '2026-W43', '2026-10', '2026'); the id for a collection. */
  key: string;
  start?: string;
  end?: string;
}

export interface OpenItem {
  entry: Entry;
  category: OpenCategory;
  source: Source;
}

export interface OpenGroup {
  /** One group per page; Year items are grouped by month. */
  id: string;
  source: Source;
  slot: string;
  items: OpenItem[];
}

export function sourceOf(logId: string, firstDay: Weekday): Source {
  const i = logId.indexOf(':');
  const kind = logId.slice(0, i) as LogKind;
  const key = logId.slice(i + 1);
  switch (kind) {
    case 'daily':
      return { logId, kind, key, start: key, end: key };
    case 'weekly': {
      const start = weekKeyStart(key, firstDay);
      return { logId, kind, key, start, end: addDays(start, 6) };
    }
    case 'monthly':
      return { logId, kind, key, start: `${key}-01`, end: `${key}-${String(daysInMonth(key)).padStart(2, '0')}` };
    case 'future':
      return { logId, kind, key, start: `${key}-01-01`, end: `${key}-12-31` };
    default:
      return { logId, kind: 'collection', key: logId };
  }
}

/** Tasks always; events only with Settings › Event states; notes and text never. */
export function stateful(e: Pick<Entry, 'type'>, eventStates: boolean) {
  return e.type === 'task' || (e.type === 'event' && eventStates);
}

export function categoryOf(e: Entry, src: Source, s: Pick<Settings, 'eventStates'>, today: string): OpenCategory | null {
  if (!stateful(e, s.eventStates)) return null;
  // B. Marked > or < but not yet written at the destination.
  if ((e.state === 'migrated' || e.state === 'scheduled') && e.placement?.status === 'pending') return 'unplaced';
  if (e.state !== 'open') return null;
  // C. A Year item whose month has come (or whose date has passed).
  if (src.kind === 'future') return (e.slot && e.slot <= monthOf(today)) || (e.dueDate && e.dueDate <= today) ? 'arrived' : null;
  // A. Still open on a Day, Week or Month that has ended.
  if (src.kind !== 'collection' && src.end && src.end < today) return 'ended';
  return null;
}

/** Everything that is loose, oldest first. */
export function openItems(entries: Entry[], s: Pick<Settings, 'eventStates' | 'firstDayOfWeek'>, today: string): OpenItem[] {
  const out: OpenItem[] = [];
  for (const entry of entries) {
    const source = sourceOf(entry.logId, s.firstDayOfWeek as Weekday);
    const category = categoryOf(entry, source, s, today);
    if (category) out.push({ entry, category, source });
  }
  return sortItems(out);
}

/** Close the day: what is still open on today's page. */
export function openToday(entries: Entry[], s: Pick<Settings, 'eventStates' | 'firstDayOfWeek'>, today: string): OpenItem[] {
  const logId = `daily:${today}`;
  return sortItems(
    entries
      .filter((e) => e.logId === logId && e.state === 'open' && stateful(e, s.eventStates))
      .map((entry) => ({ entry, category: 'ended' as const, source: sourceOf(logId, s.firstDayOfWeek as Weekday) })),
  );
}

const KIND_RANK: Record<LogKind, number> = { future: 0, monthly: 1, weekly: 2, daily: 3, collection: 4 };

function sortKey(i: OpenItem) {
  // Year items sort by their month; collections go last.
  const start = i.source.kind === 'future' ? `${i.entry.slot || i.source.key}-01` : (i.source.start ?? '9999');
  return [start, KIND_RANK[i.source.kind], i.source.logId, i.entry.slot, i.entry.order].join('|');
}

export function sortItems(items: OpenItem[]): OpenItem[] {
  return items
    .map((i) => [sortKey(i), i] as const)
    .sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
    .map(([, i]) => i);
}

export function groupItems(items: OpenItem[]): OpenGroup[] {
  const groups: OpenGroup[] = [];
  for (const item of items) {
    const slot = item.source.kind === 'future' ? item.entry.slot : '';
    const id = `${item.source.logId}|${slot}`;
    const last = groups[groups.length - 1];
    if (last?.id === id) last.items.push(item);
    else groups.push({ id, source: item.source, slot, items: [item] });
  }
  return groups;
}

/**
 * Items the user acted on while the panel is open stay listed (with their new
 * state) until it closes, so a second tap can still cancel a completed item.
 */
export function withKept(items: OpenItem[], kept: Map<string, OpenItem>, byId: Map<string, Entry>): OpenItem[] {
  const listed = new Set(items.map((i) => i.entry.id));
  const extra: OpenItem[] = [];
  for (const [id, item] of kept) {
    const entry = byId.get(id);
    if (!listed.has(id) && entry) extra.push({ ...item, entry });
  }
  return extra.length ? sortItems([...items, ...extra]) : items;
}

// ---------- Labels ----------

const rel = new Intl.RelativeTimeFormat('en', { numeric: 'auto' });

/** How long ago a period ended: "yesterday", "2 weeks ago". Empty while it is still running. */
export function ageLabel(end: string | undefined, today: string): string {
  if (!end || end >= today) return '';
  const days = Math.round((fromIso(today).getTime() - fromIso(end).getTime()) / 86_400_000);
  if (days < 7) return rel.format(-days, 'day');
  if (days < 30) return rel.format(-Math.round(days / 7), 'week');
  if (days < 365) return rel.format(-Math.round(days / 30.4), 'month');
  return rel.format(-Math.round(days / 365), 'year');
}

/** "Wk 41 · Oct 5 – 11", "Mon, Oct 5", "September 2026", "2026 · October", or the collection title. */
export function groupLabel(g: Pick<OpenGroup, 'source' | 'slot'>, collectionTitle?: string): string {
  const { kind, key, start, end } = g.source;
  switch (kind) {
    case 'daily':
      return fmt(key, { weekday: 'short', month: 'short', day: 'numeric' });
    case 'weekly': {
      const sameMonth = start!.slice(0, 7) === end!.slice(0, 7);
      const range = `${fmt(start!, { month: 'short', day: 'numeric' })} – ${fmt(end!, sameMonth ? { day: 'numeric' } : { month: 'short', day: 'numeric' })}`;
      return `${t.nav.weekShort} ${Number(key.split('-W')[1])} · ${range}`;
    }
    case 'monthly':
      return fmt(`${key}-01`, { month: 'long', year: 'numeric' });
    case 'future':
      return g.slot ? `${key} · ${fmt(`${g.slot}-01`, { month: 'long' })}` : key;
    default:
      return collectionTitle ?? '';
  }
}

/** Where an entry lives, as a route. */
export function sourcePath(src: Source): string {
  switch (src.kind) {
    case 'daily':
      return `/day/${src.key}`;
    case 'weekly':
      return `/week/${src.key}`;
    case 'monthly':
      return `/month/${src.key}`;
    case 'future':
      return `/year/${src.key}`;
    default:
      return `/collection/${encodeURIComponent(src.logId)}`;
  }
}

// ---------- Suggested destination (read-only) ----------

export type Mark = 'migrated' | 'scheduled';

export interface Destination {
  path: string;
  label: string;
  /** Element to scroll to on arrival (a Year month). */
  flashId?: string;
}

type Level = 'day' | 'week' | 'month';
const LEVEL_OF: Partial<Record<LogKind, Level>> = { daily: 'day', weekly: 'week', monthly: 'month' };

function isActive(level: Level, s: Pick<Settings, 'activeLogs'>) {
  return s.activeLogs[level === 'day' ? 'daily' : level === 'week' ? 'weekly' : 'monthly'];
}

function finest(s: Pick<Settings, 'activeLogs'>): Level {
  return s.activeLogs.daily ? 'day' : s.activeLogs.weekly ? 'week' : 'month';
}

function keyAt(level: Level, iso: string, firstDay: Weekday) {
  return level === 'day' ? iso : level === 'week' ? weekKey(iso, firstDay) : monthOf(iso);
}


function periodDestination(level: Level, key: string, today: string, firstDay: Weekday): Destination {
  switch (level) {
    case 'day':
      return {
        path: `/day/${key}`,
        label: key === today ? t.open.dest.today : key === addDays(today, 1) ? t.open.dest.tomorrow : fmt(key, { weekday: 'short', month: 'short', day: 'numeric' }),
      };
    case 'week':
      return { path: `/week/${key}`, label: key === weekKey(today, firstDay) ? t.open.dest.thisWeek : `${t.nav.weekShort} ${Number(key.split('-W')[1])}` };
    case 'month':
      return {
        path: `/month/${key}`,
        label: key === monthOf(today) ? t.open.dest.thisMonth : fmt(`${key}-01`, yearOf(key) === yearOf(today) ? { month: 'long' } : { month: 'long', year: 'numeric' }),
      };
  }
}

/**
 * > goes to the next period of the same log (or the current one, for an item
 * left behind), or to the finest active log when its own level is off; from
 * the Year it comes down to this Month. < goes to the Year, at the first
 * month after the item's period. Nothing is ever written there.
 */
export function suggestDestination(
  entry: Pick<Entry, 'logId' | 'slot'>,
  mark: Mark,
  s: Pick<Settings, 'activeLogs' | 'firstDayOfWeek'>,
  today: string,
): Destination {
  const firstDay = s.firstDayOfWeek as Weekday;
  const src = sourceOf(entry.logId, firstDay);
  const nextMonth = addMonths(monthOf(today), 1);

  if (mark === 'scheduled') {
    const after = src.kind === 'future' && entry.slot ? addMonths(entry.slot, 1) : src.end ? addMonths(monthOf(src.end), 1) : nextMonth;
    const ym = after > nextMonth ? after : nextMonth;
    return { path: `/year/${yearOf(ym)}`, label: `${yearOf(ym)} · ${fmt(`${ym}-01`, { month: 'long' })}`, flashId: `year-month-${ym}` };
  }

  const own = LEVEL_OF[src.kind];
  if (own && isActive(own, s)) {
    const next = keyAt(own, addDays(src.end!, 1), firstDay);
    const current = keyAt(own, today, firstDay);
    return periodDestination(own, next > current ? next : current, today, firstDay);
  }
  const level: Level = src.kind === 'future' && s.activeLogs.monthly ? 'month' : finest(s);
  const from = src.kind === 'future' && entry.slot && `${entry.slot}-01` > today ? `${entry.slot}-01` : today;
  const key = keyAt(level, from, firstDay);
  return periodDestination(level, key, today, firstDay);
}
