// Backup format and rules (pure, unit tested). Storage lives in repo.ts.
import type { Entry, Log } from './types';

export const BACKUP_FORMAT = 1;
export const KEEP_SNAPSHOTS = 30;

export interface Backup {
  app: 'bullet-life';
  format: number;
  createdAt: string;
  /** Collections (time pages need no rows). */
  logs: Log[];
  entries: Entry[];
}

/** Fields the sync service adds; never part of a backup (they belong to one account and one device). */
const SYNC_FIELDS = ['realmId', 'owner', '$ts'];

function clean<T extends object>(row: T): T {
  const copy = { ...row } as Record<string, unknown>;
  for (const f of SYNC_FIELDS) delete copy[f];
  return copy as T;
}

export function buildBackup(logs: Log[], entries: Entry[], now: string): Backup {
  return {
    app: 'bullet-life',
    format: BACKUP_FORMAT,
    createdAt: now,
    logs: logs.filter((l) => l.kind === 'collection').map(clean),
    entries: entries.map(clean),
  };
}

export class BackupError extends Error {}

/** Reads a backup file; throws BackupError with a short reason when it is not one of ours. */
export function parseBackup(text: string): Backup {
  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch {
    throw new BackupError('not-json');
  }
  const b = data as Partial<Backup>;
  if (!b || b.app !== 'bullet-life' || typeof b.format !== 'number') throw new BackupError('not-backup');
  if (b.format > BACKUP_FORMAT) throw new BackupError('newer-format');
  if (!Array.isArray(b.entries) || !Array.isArray(b.logs)) throw new BackupError('not-backup');
  const okEntry = (e: Partial<Entry>) => typeof e.id === 'string' && typeof e.logId === 'string' && typeof e.text === 'string';
  if (!b.entries.every(okEntry)) throw new BackupError('not-backup');
  return { app: 'bullet-life', format: b.format, createdAt: String(b.createdAt ?? ''), logs: b.logs.map(clean), entries: b.entries.map(clean) };
}

/** What to write so the database matches the backup exactly (restore replaces, it does not merge). */
export function planRestore(current: { logs: Log[]; entries: Entry[] }, backup: Backup) {
  const keepEntries = new Set(backup.entries.map((e) => e.id));
  const keepLogs = new Set(backup.logs.map((l) => l.id));
  return {
    putEntries: backup.entries,
    putLogs: backup.logs,
    removeEntries: current.entries.filter((e) => !keepEntries.has(e.id)).map((e) => e.id),
    removeLogs: current.logs.filter((l) => l.kind === 'collection' && !keepLogs.has(l.id)).map((l) => l.id),
  };
}

/** Snapshot ids are local dates ('2026-10-19'); keep the newest ones. Returns the ids to delete. */
export function snapshotsToPrune(ids: string[], keep = KEEP_SNAPSHOTS): string[] {
  return [...ids].sort().reverse().slice(keep);
}

export function backupFileName(now: Date): string {
  const p = (n: number) => String(n).padStart(2, '0');
  return `bullet-life-${now.getFullYear()}-${p(now.getMonth() + 1)}-${p(now.getDate())}-${p(now.getHours())}${p(now.getMinutes())}.json`;
}
