// Recognizing an open item the user is rewriting elsewhere (CLAUDE.md 4.4,
// Phase 4b). Local, no AI, no network: normalized words compared by overlap.
// It only ever suggests; linking is the user's tap.
import { DUE_TOKEN } from '../editor/due';

// English and Portuguese filler words: the user writes in either.
const STOPWORDS = new Set(
  (
    'a an the and or but of to in on at for from by with about as is are be was it this that these those my your our ' +
    'o os as um uma uns umas e ou mas de do da dos das no na nos nas em para pra por com sem ao aos que se meu minha'
  ).split(' '),
);

export function normalize(text: string): string[] {
  return text
    .replace(DUE_TOKEN, ' ')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, ' ')
    .split(/\s+/)
    .filter((w) => w && !STOPWORDS.has(w));
}

/** Dice coefficient over word sets: 1 = same words. */
export function similarity(a: string[], b: string[]): number {
  if (!a.length || !b.length) return 0;
  const A = new Set(a);
  const B = new Set(b);
  let shared = 0;
  for (const w of A) if (B.has(w)) shared++;
  return (2 * shared) / (A.size + B.size);
}

/**
 * A strong match only: the same words, or most words shared with at least two
 * of them in common. Noise would make the suggestion annoying, so it errs on
 * the side of saying nothing.
 */
export function isStrongMatch(a: string[], b: string[]): boolean {
  if (!a.length || !b.length) return false;
  if (a.join(' ') === b.join(' ')) return true;
  const shared = new Set(a.filter((w) => b.includes(w))).size;
  return shared >= 2 && similarity(a, b) >= 0.7;
}

/** The best strong match for `text` among the candidates, or null. */
export function bestMatch<T extends { text: string }>(text: string, candidates: T[]): T | null {
  const words = normalize(text);
  let best: T | null = null;
  let score = 0;
  for (const c of candidates) {
    const other = normalize(c.text);
    if (!isStrongMatch(words, other)) continue;
    const s = similarity(words, other);
    if (s > score) [best, score] = [c, s];
  }
  return best;
}
