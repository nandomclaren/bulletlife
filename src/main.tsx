import { compactSyncQueue } from './data/syncQueue';

// The sync queue is tidied before anything opens the database: sync reads the whole queue as soon as
// it starts, and an oversized one ran the iPad out of memory on every launch.
void compactSyncQueue().finally(() => import('./boot'));
