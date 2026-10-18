// The only way the UI reads or writes data. Swapping the sync backend later
// means changing this file and db.ts, not the pages.
import { useLiveQuery } from 'dexie-react-hooks';
import { addDays, daysInMonth, fmt, weekKeyStart, type Weekday } from '../dates';
import type { Line } from '../editor/lines';
import { diffEntries, entriesToLines, isBlank } from './convert';
import { db } from './db';
import { DEFAULT_SETTINGS, type Log, type LogKind, type Settings } from './types';

export type PeriodKind = Exclude<LogKind, 'collection'>;

export interface LogRef {
  id: string;
  kind: LogKind;
  title: string;
  periodStart?: string;
  periodEnd?: string;
}

/** Describes the log for a period without creating it (pages are created on first write). */
export function periodLog(kind: PeriodKind, key: string, firstDay: Weekday): LogRef {
  switch (kind) {
    case 'daily':
      return { id: `daily:${key}`, kind, title: fmt(key, { weekday: 'short', month: 'short', day: 'numeric' }), periodStart: key, periodEnd: key };
    case 'weekly': {
      const start = weekKeyStart(key, firstDay);
      return { id: `weekly:${key}`, kind, title: `Week ${Number(key.split('-W')[1])}`, periodStart: start, periodEnd: addDays(start, 6) };
    }
    case 'monthly':
      return {
        id: `monthly:${key}`,
        kind,
        title: fmt(`${key}-01`, { month: 'long', year: 'numeric' }),
        periodStart: `${key}-01`,
        periodEnd: `${key}-${String(daysInMonth(key)).padStart(2, '0')}`,
      };
    case 'future':
      return { id: `future:${key}`, kind, title: key, periodStart: `${key}-01-01`, periodEnd: `${key}-12-31` };
  }
}

export async function loadLines(logId: string, slot = ''): Promise<Line[]> {
  const entries = await db.entries.where('[logId+slot]').equals([logId, slot]).toArray();
  return entriesToLines(entries);
}

/** Saves one editor's lines. Creates the log only when there is something to keep. */
export async function saveLines(log: LogRef, slot: string, lines: Line[]): Promise<void> {
  await db.transaction('rw', db.logs, db.entries, async () => {
    const now = new Date().toISOString();
    const existing = await db.entries.where('[logId+slot]').equals([log.id, slot]).toArray();
    const { put, remove } = diffEntries(lines, existing, log.id, slot, now);
    if (!put.length && !remove.length) return;
    const stored = await db.logs.get(log.id);
    if (!stored && !isBlank(lines)) {
      const row: Log = { ...log, createdAt: now, updatedAt: now };
      await db.logs.add(row);
    } else if (stored) {
      await db.logs.update(log.id, { updatedAt: now });
    }
    if (put.length) await db.entries.bulkPut(put);
    if (remove.length) await db.entries.bulkDelete(remove);
  });
}

/** Which of these log ids have at least one written entry. */
export function useLogsWithContent(logIds: string[]): Set<string> {
  return (
    useLiveQuery(
      async () => {
        const entries = await db.entries.where('logId').anyOf(logIds).toArray();
        return new Set(entries.filter((e) => e.text.trim() || e.type !== 'text').map((e) => e.logId));
      },
      [logIds.join()],
    ) ?? new Set()
  );
}

export function useSettings(): Settings {
  const row = useLiveQuery(() => db.settings.get('settings'));
  return { ...DEFAULT_SETTINGS, ...row };
}

export async function updateSettings(patch: Partial<Settings>) {
  const current = (await db.settings.get('settings')) ?? { id: 'settings' as const, ...DEFAULT_SETTINGS };
  await db.settings.put({ ...current, ...patch, id: 'settings' });
}
