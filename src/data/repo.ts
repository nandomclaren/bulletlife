// The only way the UI reads or writes data. Swapping the sync backend later
// means changing this file and db.ts, not the pages.
import { useLiveQuery, useObservable } from 'dexie-react-hooks';
import { ulid } from 'ulid';
import { addDays, daysInMonth, fmt, todayIso, weekKeyStart, type Weekday } from '../dates';
import type { Line } from '../editor/lines';
import type { Stroke } from '../ink/ink';
import { backupFileName, buildBackup, parseBackup, planRestore, snapshotsToPrune, type Backup } from './backup';
import { backupDb, type Snapshot } from './backupDb';
import { diffEntries, entriesToLines } from './convert';
import { openItems, type OpenItem } from './openItems';
import { bestMatch } from './similar';
import { db } from './db';
import { DEFAULT_SETTINGS, type Entry, type EntryState, type Log, type LogKind, type Settings } from './types';

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
    useLiveQuery(async () => {
      const entries = await db.entries.where('logId').anyOf(logIds).toArray();
      return new Set(entries.filter((e) => e.text.trim() || e.type !== 'text').map((e) => e.logId));
    }, [logIds.join()]) ?? new Set()
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

/** Pins a collection to the top of the Index, or unpins it (synced). */
export async function setCollectionPinned(id: string, pinned: boolean) {
  await db.logs.update(id, { pinned, updatedAt: new Date().toISOString() });
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

// ---------- Backup ----------

const BEFORE_RESTORE_KEEP = 5;

async function currentBackup(): Promise<Backup> {
  const [logs, entries] = await Promise.all([db.logs.toArray(), db.entries.toArray()]);
  return buildBackup(logs, entries, new Date().toISOString());
}

async function storeSnapshot(id: string, kind: Snapshot['kind'], data: Backup) {
  await backupDb.snapshots.put({ id, kind, createdAt: data.createdAt, entryCount: data.entries.length, collectionCount: data.logs.length, data });
}

/** Once a day (on launch and when the app comes back to the foreground): a full copy, kept for 30 days. */
export async function takeDailySnapshot(): Promise<void> {
  const id = todayIso();
  if (await backupDb.snapshots.get(id)) return;
  const data = await currentBackup();
  if (!data.entries.length && !data.logs.length) return;
  await storeSnapshot(id, 'daily', data);
  const daily = await backupDb.snapshots.where('kind').equals('daily').primaryKeys();
  await backupDb.snapshots.bulkDelete(snapshotsToPrune(daily));
}

export function startBackups() {
  const run = () => void takeDailySnapshot().catch(() => {});
  window.setTimeout(run, 3000);
  document.addEventListener('visibilitychange', () => document.visibilityState === 'visible' && run());
}

export type SnapshotInfo = Omit<Snapshot, 'data'>;

export function useSnapshots(): SnapshotInfo[] | undefined {
  return useLiveQuery(async () => {
    const all = await backupDb.snapshots.orderBy('createdAt').reverse().toArray();
    return all.map(({ data: _data, ...info }) => info);
  });
}

/** Replaces everything with a backup. The current state is saved first, so a restore can be undone. */
export async function restoreBackup(backup: Backup): Promise<void> {
  const before = await currentBackup();
  if (before.entries.length || before.logs.length) {
    await storeSnapshot(`before-restore:${before.createdAt}`, 'before-restore', before);
    const safety = await backupDb.snapshots.where('kind').equals('before-restore').primaryKeys();
    await backupDb.snapshots.bulkDelete(snapshotsToPrune(safety, BEFORE_RESTORE_KEEP));
  }
  await db.transaction('rw', db.logs, db.entries, async () => {
    const plan = planRestore({ logs: await db.logs.toArray(), entries: await db.entries.toArray() }, backup);
    if (plan.removeEntries.length) await db.entries.bulkDelete(plan.removeEntries);
    if (plan.removeLogs.length) await db.logs.bulkDelete(plan.removeLogs);
    if (plan.putLogs.length) await db.logs.bulkPut(plan.putLogs);
    if (plan.putEntries.length) await db.entries.bulkPut(plan.putEntries);
  });
}

export async function restoreSnapshot(id: string): Promise<void> {
  const snap = await backupDb.snapshots.get(id);
  if (snap) await restoreBackup(snap.data);
}

/** Restores from an exported file. Throws BackupError when the file is not a backup. */
export async function restoreFromFile(text: string): Promise<void> {
  await restoreBackup(parseBackup(text));
}

/** Whether anything has been written at all (for the export reminder). */
export function useHasEntries(): boolean | undefined {
  return useLiveQuery(async () => (await db.entries.limit(1).count()) > 0);
}

/** Everything as a JSON file (name + contents), and remembers when this device last exported. */
export async function exportEverything(): Promise<{ name: string; text: string }> {
  const data = await currentBackup();
  await updateSettings({ lastExportAt: data.createdAt });
  return { name: backupFileName(new Date()), text: JSON.stringify(data, null, 1) };
}

/** Every page that has something written: log ids with entries, plus the collections. */
export async function writtenPages(): Promise<{ logIds: string[]; collections: Log[] }> {
  const [logIds, collections] = await Promise.all([db.entries.orderBy('logId').uniqueKeys(), db.logs.toArray()]);
  return { logIds: logIds as string[], collections };
}

// ---------- Open items (CLAUDE.md 4) ----------

/** All entries, live. Open items are derived from them in the UI (never stored). */
export function useAllEntries(): Entry[] | undefined {
  return useLiveQuery(() => db.entries.toArray());
}

/**
 * One entry's state, from the Open items panel: always a single entry, always
 * the user's own gesture. Marking > or < leaves the destination to be written
 * by hand (placement pending); anything else clears the mark.
 */
export async function markEntry(id: string, state: EntryState): Promise<void> {
  const migrating = state === 'migrated' || state === 'scheduled';
  await db.transaction('rw', db.entries, async () => {
    const e = await db.entries.get(id);
    if (!e || e.state === state) return;
    const next: Entry = { ...e, state, updatedAt: new Date().toISOString() };
    if (migrating) next.placement = e.state === 'migrated' || e.state === 'scheduled' ? (e.placement ?? { status: 'pending' }) : { status: 'pending' };
    else delete next.placement;
    await db.entries.put(next);
  });
}

/** "I wrote it there": the user confirms they rewrote the item at its destination. */
export async function confirmPlaced(id: string): Promise<void> {
  const now = new Date().toISOString();
  await db.entries.update(id, { placement: { status: 'placed', confirmedAt: now }, updatedAt: now });
}

/** Which of these period logs are set up: explicitly ("Set up week") or by having entries. */
export function usePeriodsSetUp(logIds: string[]): Set<string> | undefined {
  return useLiveQuery(async () => {
    const [marks, entries] = await Promise.all([
      db.logs.where('kind').anyOf(['daily', 'weekly', 'monthly']).toArray(),
      db.entries.where('logId').anyOf(logIds).toArray(),
    ]);
    const ids = new Set(logIds);
    return new Set([...marks.map((l) => l.periodLogId ?? ''), ...entries.map((e) => e.logId)].filter((id) => ids.has(id)));
  }, [logIds.join()]);
}

/**
 * "Set up week" / "Set up month": records that the empty page was set up, so
 * the banner goes away on every device. The page itself stays empty. Synced
 * ids must be unique, so the row gets its own id and names its period.
 */
export async function setUpPeriod(log: LogRef): Promise<void> {
  const now = new Date().toISOString();
  await db.logs.add({
    id: `setup:${ulid()}`,
    kind: log.kind,
    title: log.title,
    periodStart: log.periodStart,
    periodEnd: log.periodEnd,
    periodLogId: log.id,
    createdAt: now,
    updatedAt: now,
  });
}

// ---------- Phase 4b: linking a rewritten item ----------

const dismissedKey = 'link.dismissed';
function dismissedLinks(): Set<string> {
  try {
    return new Set(JSON.parse(localStorage.getItem(dismissedKey) ?? '[]') as string[]);
  } catch {
    return new Set();
  }
}

/** "Not this one": the same pair is never suggested again on this device. */
export function dismissLink(lineId: string, sourceId: string) {
  const all = [...dismissedLinks(), `${lineId}:${sourceId}`].slice(-500);
  try {
    localStorage.setItem(dismissedKey, JSON.stringify(all));
  } catch {
    // forgotten after this session
  }
}

/**
 * An open item (from another page) that the text just written looks like a
 * rewrite of, or null. Only a suggestion: nothing is linked without a tap.
 */
export async function findRewriteOf(lineId: string, text: string, logId: string, s: Settings): Promise<{ item: OpenItem; collectionTitle?: string } | null> {
  const entries = await db.entries.toArray();
  const dismissed = dismissedLinks();
  const candidates = openItems(entries, s, todayIso())
    .filter((i) => i.entry.id !== lineId && i.source.logId !== logId && !dismissed.has(`${lineId}:${i.entry.id}`))
    .map((i) => ({ ...i, text: i.entry.text }));
  const item = bestMatch(text, candidates);
  if (!item) return null;
  return { item, collectionTitle: item.source.kind === 'collection' ? (await db.logs.get(item.source.logId))?.title : undefined };
}

/**
 * "Link it": the user confirms the new line is the rewrite of an open item.
 * The original gets its > (if it was still open) and is marked as written there.
 */
export async function linkRewrite(sourceId: string, placedEntryId: string): Promise<void> {
  const now = new Date().toISOString();
  await db.transaction('rw', db.entries, async () => {
    const e = await db.entries.get(sourceId);
    if (!e) return;
    const state = e.state === 'migrated' || e.state === 'scheduled' ? e.state : 'migrated';
    await db.entries.put({ ...e, state, placement: { status: 'placed', placedEntryId, confirmedAt: now }, updatedAt: now });
  });
}

// ---------- Pen mode ----------

/** The page's lines, live (Pen mode redraws when anything on the page changes). */
export function usePageLines(logId: string, slot = ''): Line[] | undefined {
  return useLiveQuery(async () => entriesToLines(await db.entries.where('[logId+slot]').equals([logId, slot]).toArray()), [logId, slot]);
}

/** What some entries were before a pen action, to undo it: null = did not exist. */
export type InkSnapshot = Map<string, Entry | null>;

async function snapshot(ids: string[]): Promise<InkSnapshot> {
  const rows = await db.entries.bulkGet(ids);
  return new Map(ids.map((id, i) => [id, rows[i] ?? null]));
}

/** Adds strokes to an entry the user wrote on. Returns how to undo it. */
export async function addInk(log: LogRef, entryId: string, strokes: Stroke[]): Promise<InkSnapshot> {
  return db.transaction('rw', db.logs, db.entries, async () => {
    const before = await snapshot([entryId]);
    const e = before.get(entryId);
    if (!e) return new Map();
    const now = new Date().toISOString();
    await db.entries.put({ ...e, ink: { strokes: [...(e.ink?.strokes ?? []), ...strokes] }, updatedAt: now });
    if (log.kind === 'collection') await db.logs.update(log.id, { updatedAt: now });
    return before;
  });
}

/**
 * The user wrote below the last line: new lines go at the end of the page,
 * the empty ones standing for ruled lines skipped (as on paper) and the last
 * one holding the strokes. The caller makes the lines, so it can keep
 * writing on them before this is stored.
 */
export async function addInkLines(log: LogRef, slot: string, added: Line[]): Promise<InkSnapshot> {
  return db.transaction('rw', db.logs, db.entries, async () => {
    const existing = await db.entries.where('[logId+slot]').equals([log.id, slot]).toArray();
    const lines = entriesToLines(existing);
    const now = new Date().toISOString();
    const { put } = diffEntries([...lines, ...added], existing, log.id, slot, now, lines);
    await db.entries.bulkPut(put);
    if (log.kind === 'collection') await db.logs.update(log.id, { updatedAt: now });
    return new Map(added.map((l) => [l.id, null]));
  });
}

/** Removes strokes the eraser touched (by entry: stroke indexes). */
export async function eraseInk(log: LogRef, hits: Map<string, number[]>): Promise<InkSnapshot> {
  return db.transaction('rw', db.logs, db.entries, async () => {
    const before = await snapshot([...hits.keys()]);
    const now = new Date().toISOString();
    for (const [id, idx] of hits) {
      const e = before.get(id);
      if (!e?.ink) continue;
      const gone = new Set(idx);
      const strokes = e.ink.strokes.filter((_, i) => !gone.has(i));
      // An emptied line stays as a blank ruled line, so nothing below moves up; only the last line of the page goes.
      const page = await db.entries.where('[logId+slot]').equals([e.logId, e.slot]).toArray();
      const last = page.every((o) => o.order <= e.order);
      if (!strokes.length && !e.text.trim() && e.type === 'text' && last) await db.entries.delete(id);
      else {
        const next: Entry = { ...e, updatedAt: now };
        if (strokes.length) next.ink = { strokes };
        else delete next.ink;
        await db.entries.put(next);
      }
    }
    if (log.kind === 'collection') await db.logs.update(log.id, { updatedAt: now });
    return before;
  });
}

/** Undo of a pen action: puts the entries back as they were. */
export async function restoreInk(before: InkSnapshot): Promise<void> {
  await db.transaction('rw', db.entries, async () => {
    for (const [id, e] of before) {
      if (e) await db.entries.put({ ...e, updatedAt: new Date().toISOString() });
      else await db.entries.delete(id);
    }
  });
}
