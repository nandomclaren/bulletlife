// Upkeep of Dexie Cloud's queue of changes waiting to be sent (its `$<table>_mutations` stores).
// Uses IndexedDB directly so it runs before the app (and sync, which reads the whole queue) opens.

/** What must be sent again after the queue was set aside, per synced table (kept across launches). */
export type Resend = Record<string, { put: string[]; del: string[] }>;

const RESEND_KEY = 'sync.resend';
/**
 * A healthy queue is near empty (it is sent within seconds). Setting it aside is always safe (its
 * entries are sent again), so it is not measured, only counted: measuring meant holding each change
 * as text as well.
 */
const QUEUE_LIMIT = 60;

export function readResend(): Resend {
  try {
    return JSON.parse(localStorage.getItem(RESEND_KEY) ?? '{}') as Resend;
  } catch {
    return {};
  }
}

export function writeResend(r: Resend): void {
  const left = Object.fromEntries(Object.entries(r).filter(([, v]) => v.put.length || v.del.length));
  try {
    if (Object.keys(left).length) localStorage.setItem(RESEND_KEY, JSON.stringify(left));
    else localStorage.removeItem(RESEND_KEY);
  } catch {
    // Storage full or blocked: the queue is gone, but the data is all on this device.
  }
}

const req = <T>(r: IDBRequest<T>) =>
  new Promise<T>((resolve, reject) => {
    r.onsuccess = () => resolve(r.result);
    r.onerror = () => reject(r.error);
  });

/**
 * Sets an oversized sync queue aside. Every stroke used to be stored as a full write of its entry, so
 * a long handwritten paragraph left hundreds of full copies waiting; sync reads the whole queue and
 * sends it as one request, which ran the iPad out of memory at every launch (and the server refuses it,
 * 413). The data itself is all in the tables: the queue only says what to send. So when it is far too
 * long, it is read one change at a time to note which entries it names, then cleared; the app sends
 * those entries again in small batches (`resendPending` in repo.ts). Never throws.
 */
export async function setAsideLargeQueue(dbName = 'bullet-life'): Promise<number> {
  let idb: IDBDatabase;
  try {
    const rq = indexedDB.open(dbName);
    // No database yet: do not create one (Dexie must create it with its own schema).
    rq.onupgradeneeded = () => rq.transaction?.abort();
    idb = await req(rq);
  } catch {
    return 0;
  }
  try {
    idb.onversionchange = () => idb.close();
    const stores = [...idb.objectStoreNames].filter((n) => n.startsWith('$') && n.endsWith('_mutations'));
    let cleared = 0;
    for (const store of stores) {
      const table = store.slice(1, -'_mutations'.length);
      const revs = await req(idb.transaction(store).objectStore(store).getAllKeys());
      if (!revs.length) continue;
      if (revs.length < QUEUE_LIMIT) continue;
      // One change in memory at a time: the entries it names.
      const last = new Map<string, 'put' | 'del'>();
      for (const rev of revs) {
        const m = (await req(idb.transaction(store).objectStore(store).get(rev))) as { type?: string; keys?: unknown[] } | undefined;
        if (!m) continue;
        for (const k of m.keys ?? []) last.set(String(k), m.type === 'delete' ? 'del' : 'put');
      }
      const resend = readResend();
      const prev = resend[table] ?? { put: [], del: [] };
      const put = new Set(prev.put);
      const del = new Set(prev.del);
      for (const [k, op] of last) {
        (op === 'put' ? put : del).add(k);
        (op === 'put' ? del : put).delete(k);
      }
      resend[table] = { put: [...put], del: [...del] };
      writeResend(resend);
      const names = ['$baseRevs', store].filter((n) => idb.objectStoreNames.contains(n));
      const tx = idb.transaction(names, 'readwrite');
      tx.objectStore(store).clear();
      if (names.includes('$baseRevs')) tx.objectStore('$baseRevs').delete(IDBKeyRange.bound([table, -Infinity], [table, Infinity]));
      await new Promise<void>((resolve, reject) => {
        tx.oncomplete = () => resolve();
        tx.onerror = tx.onabort = () => reject(tx.error);
      });
      cleared += revs.length;
    }
    return cleared;
  } catch {
    return 0;
  } finally {
    idb.close();
  }
}
