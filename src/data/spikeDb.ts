// Spike-only data access. The real app routes everything through src/data/ repositories.
import Dexie, { type Table } from 'dexie';
import dexieCloud from 'dexie-cloud-addon';

export interface Launch {
  id?: number;
  at: string;
}

export interface CheckResult {
  id: string;
  status: 'pass' | 'fail' | 'unsure' | null;
  note: string;
}

class LocalDb extends Dexie {
  launches!: Table<Launch, number>;
  results!: Table<CheckResult, string>;
  constructor() {
    super('bullet-life-spike');
    this.version(1).stores({ launches: '++id, at', results: 'id' });
  }
}

export const localDb = new LocalDb();

export interface SyncLine {
  id?: string;
  text: string;
  createdAt: string;
  device: string;
}

export class CloudDb extends Dexie {
  lines!: Table<SyncLine, string>;
  constructor(url: string) {
    super('bullet-life-spike-cloud', { addons: [dexieCloud] });
    this.version(1).stores({ lines: '@id, createdAt' });
    this.cloud.configure({ databaseUrl: url, requireAuth: true });
  }
}

const CLOUD_URL_KEY = 'spike.cloudUrl';

export function getCloudUrl(): string | null {
  try {
    return localStorage.getItem(CLOUD_URL_KEY);
  } catch {
    return null;
  }
}

export function setCloudUrl(url: string | null) {
  if (url) localStorage.setItem(CLOUD_URL_KEY, url);
  else localStorage.removeItem(CLOUD_URL_KEY);
}

let cloud: CloudDb | null = null;
export function getCloudDb(): CloudDb | null {
  const url = getCloudUrl();
  if (!url) return null;
  if (!cloud) cloud = new CloudDb(url);
  return cloud;
}

export async function recordLaunch() {
  await localDb.launches.add({ at: new Date().toISOString() });
}
