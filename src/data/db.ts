import Dexie, { type Table } from 'dexie';
import dexieCloud from 'dexie-cloud-addon';
import { CLOUD_DATABASE_URL } from './cloud';
import type { Entry, Log, Settings } from './types';

export interface SettingsRow extends Settings {
  id: 'settings';
}

export class BulletLifeDb extends Dexie {
  /** Collections only. Time pages (day, week, month, year) need no row: everything about them comes from the date. */
  logs!: Table<Log, string>;
  entries!: Table<Entry, string>;
  /** Per device for now (one fixed row; not synced). */
  settings!: Table<SettingsRow, string>;

  constructor() {
    super('bullet-life', { addons: [dexieCloud] });
    this.version(1).stores({
      logs: 'id, kind, periodStart',
      entries: 'id, logId, [logId+slot], parentId, updatedAt',
      settings: 'id',
    });
    // v2: sync. Synced primary keys must be globally unique, so the
    // deterministic time-log rows ('daily:2026-10-18') are dropped; entries
    // keep pointing to them by name. Entries (ULID) and collections
    // ('collection:<ULID>') already have unique ids.
    this.version(2)
      .stores({
        logs: 'id, kind',
        entries: 'id, logId, [logId+slot], parentId, updatedAt',
        settings: 'id',
      })
      .upgrade((tx) =>
        tx
          .table('logs')
          .filter((l: Log) => l.kind !== 'collection')
          .delete(),
      );
    this.cloud.configure({
      databaseUrl: CLOUD_DATABASE_URL,
      // Local-first: the app works fully without signing in; sync starts after sign-in.
      requireAuth: false,
      unsyncedTables: ['settings'],
      tryUseServiceWorker: false,
      // Keep the existing local database ('bullet-life') instead of opening a
      // new one named after the cloud database; it is upgraded in place.
      nameSuffix: false,
    });
  }
}

// Only src/data/ may import this. The UI goes through the repository.
export const db = new BulletLifeDb();
