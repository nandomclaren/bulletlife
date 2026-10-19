// Editors save shortly after typing; exports first flush whatever is pending
// so they always include the last keystrokes.
const flushers = new Set<() => Promise<void>>();

export function registerFlush(fn: () => Promise<void>): () => void {
  flushers.add(fn);
  return () => flushers.delete(fn);
}

export async function flushAll(): Promise<void> {
  await Promise.all([...flushers].map((f) => f()));
}
