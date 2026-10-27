import { setAsideLargeQueue } from './data/syncQueue';

// An oversized sync queue is set aside before anything opens the database: sync reads the whole queue
// as soon as it starts, and an oversized one ran the iPad out of memory on every launch.
void setAsideLargeQueue().finally(() => import('./boot'));
