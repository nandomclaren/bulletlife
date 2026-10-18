import { generateKeyBetween } from 'fractional-indexing';

/**
 * Assigns fractional order keys to items in their new sequence, keeping
 * existing keys whenever they are still in order so that only moved or new
 * items get written (smaller diffs, fewer sync conflicts).
 */
export function assignOrders(ids: string[], existing: Map<string, string>): string[] {
  const out: string[] = [];
  let prev: string | null = null;
  for (let i = 0; i < ids.length; i++) {
    const own = existing.get(ids[i]);
    if (own !== undefined && (prev === null || own > prev)) {
      out.push(own);
      prev = own;
      continue;
    }
    // Upper bound: the next item that will keep its key, if it is above prev.
    let upper: string | null = null;
    for (let j = i + 1; j < ids.length; j++) {
      const k = existing.get(ids[j]);
      if (k !== undefined) {
        if (prev === null || k > prev) upper = k;
        break;
      }
    }
    const key = generateKeyBetween(prev, upper);
    out.push(key);
    prev = key;
  }
  return out;
}
