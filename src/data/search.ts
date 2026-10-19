// Global search (CLAUDE.md 5, ⌘K): every entry on every page, collapsed or
// not, and collection names. Accent- and case-insensitive; every word typed
// must appear. Pure and unit tested.
import type { Entry, Log } from './types';

export const fold = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

export interface SearchHit<T> {
  item: T;
  /** Where the words were found in the text, for highlighting. */
  ranges: Array<[number, number]>;
}

function match(text: string, words: string[]): Array<[number, number]> | null {
  const folded = fold(text);
  const ranges: Array<[number, number]> = [];
  for (const w of words) {
    const at = folded.indexOf(w);
    if (at < 0) return null;
    ranges.push([at, at + w.length]);
  }
  return ranges.sort((a, b) => a[0] - b[0]);
}

export function queryWords(query: string): string[] {
  return fold(query).split(/\s+/).filter(Boolean);
}

/** Entries containing every word, most recently changed first. Blank lines never match. */
export function searchEntries(entries: Entry[], query: string, limit = 60): SearchHit<Entry>[] {
  const words = queryWords(query);
  if (!words.length) return [];
  const hits: SearchHit<Entry>[] = [];
  for (const e of entries) {
    if (!e.text.trim()) continue;
    const ranges = match(e.text, words);
    if (ranges) hits.push({ item: e, ranges });
  }
  return hits.sort((a, b) => (a.item.updatedAt < b.item.updatedAt ? 1 : a.item.updatedAt > b.item.updatedAt ? -1 : 0)).slice(0, limit);
}

export function searchCollections(logs: Log[], query: string): SearchHit<Log>[] {
  const words = queryWords(query);
  if (!words.length) return [];
  return logs.flatMap((l) => {
    const ranges = l.kind === 'collection' ? match(l.title, words) : null;
    return ranges ? [{ item: l, ranges }] : [];
  });
}
