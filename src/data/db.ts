import Dexie, { type Table } from 'dexie';
import type { Entry, Log, Settings } from './types';

export interface SettingsRow extends Settings {
  id: 'settings';
}

export class BulletLifeDb extends Dexie {
  logs!: Table<Log, string>;
  entries!: Table<Entry, string>;
  settings!: Table<SettingsRow, string>;

  constructor() {
    super('bullet-life');
    this.version(1).stores({
      logs: 'id, kind, periodStart',
      entries: 'id, logId, [logId+slot], parentId, updatedAt',
      settings: 'id',
    });
  }
}

// Only src/data/ may import this. The UI goes through the repository.
export const db = new BulletLifeDb();
