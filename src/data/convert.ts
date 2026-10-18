// Editor lines <-> stored entries. Pure functions, unit tested.
import { parentIds, type Line } from '../editor/lines';
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

/** Changes needed so that the stored entries of one (log, slot) match `lines`. */
export function diffEntries(lines: Line[], existing: Entry[], logId: string, slot: string, now: string): EntryDiff {
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
    const signifiers = mergeSignifiers(old?.signifiers ?? [], l.priority);
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
    if (!old || changed(old, next)) put.push({ ...next, updatedAt: now });
  });
  const live = new Set(keep.map((l) => l.id));
  const remove = existing.filter((e) => !live.has(e.id)).map((e) => e.id);
  return { put, remove };
}

function mergeSignifiers(old: Entry['signifiers'], priority: boolean): Entry['signifiers'] {
  const rest = old.filter((s) => s !== 'priority');
  return priority ? ['priority', ...rest] : rest;
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
    a.signifiers.join() !== b.signifiers.join()
  );
}
