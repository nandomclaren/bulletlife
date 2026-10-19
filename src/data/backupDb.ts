// Snapshots live in their own local database, never synced: a deletion or a
// bug that spreads through sync cannot reach them.
import Dexie, { type Table } from 'dexie';
import type { Backup } from './backup';

export interface Snapshot {
  /** 'YYYY-MM-DD' for the daily snapshot, 'before-restore:<ISO time>' for the safety copy taken before a restore. */
  id: string;
  kind: 'daily' | 'before-restore';
  createdAt: string;
  entryCount: number;
  collectionCount: number;
  data: Backup;
}

class BackupDb extends Dexie {
  snapshots!: Table<Snapshot, string>;
  constructor() {
    super('bullet-life-backups');
    this.version(1).stores({ snapshots: 'id, kind, createdAt' });
  }
}

export const backupDb = new BackupDb();
