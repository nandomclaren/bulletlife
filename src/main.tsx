import { compactSyncQueue } from './data/syncQueue';

// The sync queue is kept small before anything opens the database: sync reads the whole queue as soon
// as it starts, and an oversized one ran the iPad out of memory on every launch.
try {
  localStorage.removeItem('sync.resend'); // from a version that set the queue aside (see syncQueue.ts)
} catch {
  // ignore
}
void compactSyncQueue().finally(() => import('./boot'));
