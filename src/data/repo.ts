// The only way the UI reads or writes data. Swapping the sync backend later
// means changing this file and db.ts, not the pages.
import { useLiveQuery, useObservable } from 'dexie-react-hooks';
import { ulid } from 'ulid';
import { addDays, daysInMonth, fmt, weekKeyStart, type Weekday } from '../dates';
import type { Line } from '../editor/lines';
import { diffEntries, entriesToLines } from './convert';
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

/**
 * Saves one editor's lines. With `base` (what the editor loaded or last
 * saved), only what the editor changed is written. Time pages need no log row (they are derived from
 * the date); a collection's row is touched so it sorts by last change.
 */
export async function saveLines(log: LogRef, slot: string, lines: Line[], base?: Line[]): Promise<void> {
  await db.transaction('rw', db.logs, db.entries, async () => {
    const now = new Date().toISOString();
    const existing = await db.entries.where('[logId+slot]').equals([log.id, slot]).toArray();
    const { put, remove } = diffEntries(lines, existing, log.id, slot, now, base);
    if (!put.length && !remove.length) return;
    if (log.kind === 'collection') await db.logs.update(log.id, { updatedAt: now });
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
  return useLoadedSettings() ?? DEFAULT_SETTINGS;
}

/** Settings, or undefined until they have been read (for decisions that must not use defaults). */
export function useLoadedSettings(): Settings | undefined {
  // null = read, no row stored yet.
  const row = useLiveQuery(async () => (await db.settings.get('settings')) ?? null);
  return row === undefined ? undefined : { ...DEFAULT_SETTINGS, ...row };
}

export async function updateSettings(patch: Partial<Settings>) {
  const current = (await db.settings.get('settings')) ?? { id: 'settings' as const, ...DEFAULT_SETTINGS };
  await db.settings.put({ ...current, ...patch, id: 'settings' });
}

// ---------- Collections and Index ----------

export function collectionRef(log: Log): LogRef {
  return { id: log.id, kind: 'collection', title: log.title };
}

/** Collections are created only by an explicit user action (principle 7). */
export async function createCollection(title: string): Promise<string> {
  const now = new Date().toISOString();
  const id = `collection:${ulid()}`;
  await db.logs.add({ id, kind: 'collection', title, createdAt: now, updatedAt: now });
  return id;
}

export async function renameCollection(id: string, title: string) {
  await db.logs.update(id, { title, updatedAt: new Date().toISOString() });
}

export function useLog(id: string): Log | null | undefined {
  return useLiveQuery(async () => (await db.logs.get(id)) ?? null, [id]);
}

export function useCollections(): Log[] | undefined {
  return useLiveQuery(async () => {
    const all = await db.logs.where('kind').equals('collection').toArray();
    return all.sort((a, b) => a.title.localeCompare(b.title, 'en', { sensitivity: 'base' }));
  });
}

// ---------- Sync ----------

export type SyncView =
  | { kind: 'off' } // not signed in: everything stays on this device
  | { kind: 'synced'; email?: string }
  | { kind: 'syncing'; email?: string }
  | { kind: 'offline'; email?: string }
  | { kind: 'error'; email?: string; message: string };

/** One calm summary of the sync state for the UI. */
export function useSync(): SyncView {
  const user = useObservable(db.cloud.currentUser);
  const state = useObservable(db.cloud.syncState);
  if (!user?.isLoggedIn) return { kind: 'off' };
  const email = user.email;
  if (!state) return { kind: 'syncing', email };
  if (state.phase === 'error' || state.status === 'error') return { kind: 'error', email, message: state.error?.message ?? '' };
  if (state.phase === 'offline' || state.status === 'offline' || state.status === 'disconnected') return { kind: 'offline', email };
  if (state.phase === 'in-sync') return { kind: 'synced', email };
  return { kind: 'syncing', email };
}

/** Opens the sign-in flow (email, then a one-time code). */
export function signIn() {
  return db.cloud.login();
}

/** Signs out (the sync service handles what happens to data on this device). */
export function signOut() {
  return db.cloud.logout();
}

export function syncNow() {
  return db.cloud.sync({ purpose: 'pull', wait: true });
}

/** Changes whenever the stored entries of one (log, slot) change, locally or from sync. */
export function useEntriesStamp(logId: string, slot = ''): string | undefined {
  return useLiveQuery(async () => {
    const entries = await db.entries.where('[logId+slot]').equals([logId, slot]).toArray();
    return entries
      .map((e) => `${e.id}@${e.updatedAt}`)
      .sort()
      .join('|');
  }, [logId, slot]);
}
