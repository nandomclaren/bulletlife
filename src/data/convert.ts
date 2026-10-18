// Editor lines <-> stored entries. Pure functions, unit tested.
import { parentIds, signifiersOf, type Line } from '../editor/lines';
import { assignOrders } from './order';
import type { Entry } from './types';

/** Stored entries (any order) → editor lines in document order with indents. */
export function entriesToLines(entries: Entry[]): Line[] {
  const sorted = [...entries].sort((a, b) => (a.order < b.order ? -1 : a.order > b.order ? 1 : 0));
  const depth = new Map<string, number>();
  return sorted.map((e) => {
    const d = e.parentId && depth.has(e.parentId) ? depth.get(e.parentId)! + 1 : 0;
    depth.set(e.id, d);
    return {
      id: e.id,
      type: e.type,
      state: e.state,
      indent: d,
      collapsed: e.collapsed,
      priority: e.signifiers.includes('priority'),
      inspiration: e.signifiers.includes('inspiration'),
      explore: e.signifiers.includes('explore'),
      text: e.text,
    };
  });
}

export function isBlank(lines: Line[]) {
  return lines.every((l) => l.text.trim() === '' && (l.type === 'text' || l.type === 'heading'));
}

export interface EntryDiff {
  put: Entry[];
  remove: string[];
}

/**
 * Lines this editor actually changed since `base` (what it loaded or last
 * saved): new, edited, re-parented or moved lines. Everything else on the page
 * is left alone, so an editor that has not yet received a change made
 * elsewhere (another window, the other device) never writes it back over.
 */
export function touchedIds(lines: Line[], base: Line[]): Set<string> {
  const before = new Map(base.map((l, i) => [l.id, { l, prev: base[i - 1]?.id ?? null }]));
  const parents = parentIds(lines);
  const baseParents = new Map(parentIds(base).map((p, i) => [base[i].id, p]));
  const touched = new Set<string>();
  lines.forEach((l, i) => {
    const b = before.get(l.id);
    if (
      !b ||
      b.prev !== (lines[i - 1]?.id ?? null) ||
      baseParents.get(l.id) !== parents[i] ||
      b.l.text !== l.text ||
      b.l.type !== l.type ||
      b.l.state !== l.state ||
      b.l.collapsed !== l.collapsed ||
      signifiersOf(b.l).join() !== signifiersOf(l).join()
    )
      touched.add(l.id);
  });
  return touched;
}

/**
 * Changes needed to store `lines` for one (log, slot). Without `base`, the
 * stored entries are made to match `lines` exactly. With `base`, only lines
 * the editor touched are written and only lines it removed are deleted.
 */
export function diffEntries(lines: Line[], existing: Entry[], logId: string, slot: string, now: string, base?: Line[]): EntryDiff {
  const byId = new Map(existing.map((e) => [e.id, e]));
  const keep = isBlank(lines) ? [] : lines;
  const parents = parentIds(keep);
  const orders = assignOrders(
    keep.map((l) => l.id),
    new Map(existing.map((e) => [e.id, e.order])),
  );
  const put: Entry[] = [];
  keep.forEach((l, i) => {
    const old = byId.get(l.id);
    const signifiers = signifiersOf(l);
    const migrating = l.state === 'migrated' || l.state === 'scheduled';
    const next: Entry = {
      ...(old ?? { createdAt: now }),
      id: l.id,
      logId,
      slot,
      parentId: parents[i],
      order: orders[i],
      type: l.type,
      state: l.state,
      text: l.text,
      signifiers,
      collapsed: l.collapsed,
      updatedAt: old?.updatedAt ?? now,
    } as Entry;
    // Marked > or < : pending until the user confirms they wrote it at the destination (CLAUDE.md 4.3).
    if (migrating) next.placement = old?.placement ?? { status: 'pending' };
    else delete next.placement;
    if (!old || changed(old, next)) put.push({ ...next, updatedAt: now });
  });
  const live = new Set(keep.map((l) => l.id));
  if (!base) return { put, remove: existing.filter((e) => !live.has(e.id)).map((e) => e.id) };
  const touched = touchedIds(keep, base);
  const known = new Set(base.map((l) => l.id));
  return {
    put: put.filter((e) => touched.has(e.id)),
    // Only what this editor knew and removed; entries that arrived from elsewhere stay.
    remove: existing.filter((e) => known.has(e.id) && !live.has(e.id)).map((e) => e.id),
  };
}

function changed(a: Entry, b: Entry) {
  return (
    a.parentId !== b.parentId ||
    a.order !== b.order ||
    a.type !== b.type ||
    a.state !== b.state ||
    a.text !== b.text ||
    a.collapsed !== b.collapsed ||
    a.slot !== b.slot ||
    a.signifiers.join() !== b.signifiers.join() ||
    a.placement?.status !== b.placement?.status
  );
}
