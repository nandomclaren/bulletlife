// Upkeep of Dexie Cloud's queue of changes waiting to be sent (its `$<table>_mutations` stores).
// Uses IndexedDB directly so it can run before the app (and the sync, which reads the whole queue) opens.

/**
 * Drops pending sync changes that a later full write (or delete) of the same entries replaces. Every
 * stroke used to be stored as a full write of its entry, so a long handwritten paragraph left hundreds
 * of full copies waiting; sync sends the whole queue in one request, which the server refused (413),
 * and reading it all at once ran the iPad out of memory. Only the last full write of each entry
 * matters, so the earlier ones go: what the server ends up with is unchanged. The queue is walked
 * newest first with a cursor, one change in memory at a time. Never throws; returns how many went.
 */
export function compactSyncQueue(dbName = 'bullet-life'): Promise<number> {
  return new Promise((resolve) => {
    let dropped = 0;
    let rq: IDBOpenDBRequest;
    try {
      rq = indexedDB.open(dbName);
    } catch {
      return resolve(0);
    }
    // No database yet: do not create one (Dexie must create it with its own schema).
    rq.onupgradeneeded = () => rq.transaction?.abort();
    rq.onerror = () => resolve(0);
    rq.onblocked = () => resolve(0);
    rq.onsuccess = () => {
      const idb = rq.result;
      idb.onversionchange = () => idb.close();
      const stores = [...idb.objectStoreNames].filter((n) => n.startsWith('$') && n.endsWith('_mutations'));
      if (!stores.length) {
        idb.close();
        return resolve(0);
      }
      const tx = idb.transaction(stores, 'readwrite');
      for (const name of stores) {
        const covered = new Set<string>();
        const cur = tx.objectStore(name).openCursor(null, 'prev');
        cur.onsuccess = () => {
          const c = cur.result;
          if (!c) return;
          const m = c.value as { type?: string; keys?: unknown[] };
          const keys = (m.keys ?? []).map(String);
          const full = m.type === 'upsert' || m.type === 'insert' || m.type === 'delete';
          if (keys.length && (full || m.type === 'update') && keys.every((k) => covered.has(k))) {
            c.delete();
            dropped++;
          } else if (full) keys.forEach((k) => covered.add(k));
          c.continue();
        };
      }
      const done = () => {
        idb.close();
        resolve(dropped);
      };
      tx.oncomplete = done;
      tx.onerror = done;
      tx.onabort = done;
    };
  });
}
