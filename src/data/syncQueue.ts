// Upkeep of Dexie Cloud's queue of changes waiting to be sent (its `$<table>_mutations` stores).
// Uses IndexedDB directly, so it can also run before the app (and sync, which reads the whole queue) opens.

/**
 * Past this many waiting changes in one table, the queue is rewritten. A healthy queue is near empty
 * (it is sent within seconds), but writing by hand while sync is slow or offline adds a change per
 * stroke, each carrying all the ink of its entry.
 */
const QUEUE_LIMIT = 20;

type Mutation = { rev?: number; type?: string; keys?: unknown[]; userId?: string };

/**
 * Rewrites an oversized sync queue as one change per entry: the entry as it is now on this device
 * (or its deletion). Every stroke used to queue a full copy of its entry, so a long handwritten
 * paragraph left hundreds of copies waiting; sync reads the whole queue and sends it as one request,
 * which ran the iPad out of memory and was refused by the server (413).
 *
 * The queue must never just be emptied: while an entry has a change waiting, sync does not let the
 * server's (older) copy overwrite it. Emptying it once let a pull replace handwriting with the
 * server's copy from the middle of the writing. Here the old changes and the new ones are swapped in
 * one transaction, so every entry stays covered.
 *
 * Changes are read one at a time (they can be large). Never throws; returns how many were replaced.
 */
export function compactSyncQueue(dbName = 'bullet-life'): Promise<number> {
  return new Promise((resolve) => {
    let rq: IDBOpenDBRequest;
    try {
      rq = indexedDB.open(dbName);
    } catch {
      return resolve(0);
    }
    // No database yet: do not create one (Dexie must create it with its own schema).
    rq.onupgradeneeded = () => rq.transaction?.abort();
    rq.onerror = rq.onblocked = () => resolve(0);
    rq.onsuccess = () => {
      const idb = rq.result;
      idb.onversionchange = () => idb.close();
      const stores = [...idb.objectStoreNames].filter((n) => /^\$.+_mutations$/.test(n) && idb.objectStoreNames.contains(n.slice(1, -10)));
      let replaced = 0;
      const next = (i: number) => {
        if (i >= stores.length) {
          idb.close();
          return resolve(replaced);
        }
        compactStore(idb, stores[i], stores[i].slice(1, -10))
          .then((n) => (replaced += n))
          .catch(() => {})
          .finally(() => next(i + 1));
      };
      next(0);
    };
  });
}

function compactStore(idb: IDBDatabase, store: string, table: string): Promise<number> {
  return new Promise((resolve, reject) => {
    const tx = idb.transaction([store, table], 'readwrite');
    const muts = tx.objectStore(store);
    const rows = tx.objectStore(table);
    let replaced = 0;
    tx.oncomplete = () => resolve(replaced);
    tx.onerror = tx.onabort = () => reject(tx.error);
    const keysReq = muts.getAllKeys();
    keysReq.onsuccess = () => {
      const revs = keysReq.result as number[];
      if (revs.length < QUEUE_LIMIT) return;
      // What each entry's last waiting change was, read one change at a time.
      const last = new Map<string, 'put' | 'del'>();
      let userId: string | undefined;
      let i = 0;
      const readNext = () => {
        if (i >= revs.length) return rewrite();
        const g = muts.get(revs[i++]);
        g.onsuccess = () => {
          const m = g.result as Mutation | undefined;
          if (m) {
            // A change without keys (a query-based edit) cannot be replaced by per-entry ones: leave the queue.
            if (!m.keys?.length) return;
            userId = m.userId ?? userId;
            for (const k of m.keys) last.set(String(k), m.type === 'delete' ? 'del' : 'put');
          }
          readNext();
        };
      };
      // The new changes go in first, then the old ones go: all in this one transaction.
      const rewrite = () => {
        const txid = `compact-${Date.now().toString(36)}`;
        const ts = Date.now();
        let opNo = 0;
        const add = (type: 'upsert' | 'delete', key: string, row?: unknown) =>
          muts.add({ type, ts, opNo: ++opNo, keys: [key], txid, userId, ...(type === 'upsert' ? { values: [row] } : {}) });
        const keys = [...last.keys()];
        let k = 0;
        const putNext = () => {
          if (k >= keys.length) {
            muts.delete(IDBKeyRange.bound(revs[0], revs[revs.length - 1]));
            replaced = revs.length;
            return;
          }
          const key = keys[k++];
          if (last.get(key) === 'del') {
            add('delete', key);
            return putNext();
          }
          const r = rows.get(key);
          r.onsuccess = () => {
            if (r.result) add('upsert', key, r.result);
            else add('delete', key);
            putNext();
          };
        };
        putNext();
      };
      readNext();
    };
  });
}
