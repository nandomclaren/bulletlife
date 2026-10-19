import { describe, expect, it } from 'vitest';
import { newLine } from '../editor/lines';
import { diffEntries, entriesToLines } from './convert';

const NOW = '2026-10-18T12:00:00.000Z';

describe('lines ↔ entries', () => {
  const lines = [
    newLine({ type: 'task', text: 'Call the bank', priority: true }),
    newLine({ type: 'note', text: 'closes at 6', indent: 1 }),
    newLine({ type: 'event', text: 'Dinner' }),
  ];

  it('stores parents and order, and round-trips', () => {
    const { put, remove } = diffEntries(lines, [], 'daily:2026-10-18', '', NOW);
    expect(remove).toEqual([]);
    expect(put).toHaveLength(3);
    expect(put[1].parentId).toBe(lines[0].id);
    expect(put[0].signifiers).toEqual(['priority']);
    expect(entriesToLines(put.reverse())).toEqual(lines);
  });

  it('writes only what changed and removes deleted lines', () => {
    const first = diffEntries(lines, [], 'L', '', NOW).put;
    const edited = [lines[0], { ...lines[2], state: 'done' as const }];
    const { put, remove } = diffEntries(edited, first, 'L', '', '2026-10-19T00:00:00.000Z');
    expect(put.map((e) => e.text)).toEqual(['Dinner']);
    expect(put[0].createdAt).toBe(NOW);
    expect(remove).toEqual([lines[1].id]);
  });

  it('never stores a blank page', () => {
    expect(diffEntries([newLine()], [], 'L', '', NOW).put).toEqual([]);
  });
});

describe('signifiers and placement', () => {
  it('stores all signifiers and reads them back', () => {
    const l = newLine({ type: 'task', text: 'Idea', priority: true, explore: true });
    const [e] = diffEntries([l], [], 'L', '', NOW).put;
    expect(e.signifiers).toEqual(['priority', 'explore']);
    expect(entriesToLines([e])[0]).toMatchObject({ priority: true, inspiration: false, explore: true });
  });

  it('marks > and < as pending placement and clears it when reopened', () => {
    const l = newLine({ type: 'task', text: 'Renew passport' });
    const [first] = diffEntries([l], [], 'L', '', NOW).put;
    const [migrated] = diffEntries([{ ...l, state: 'migrated' }], [first], 'L', '', NOW).put;
    expect(migrated.placement).toEqual({ status: 'pending' });
    const [reopened] = diffEntries([l], [migrated], 'L', '', NOW).put;
    expect(reopened.placement).toBeUndefined();
  });
});

describe('saving only what the editor changed', () => {
  const base = [newLine({ type: 'task', text: 'Pay rent' }), newLine({ type: 'text', text: 'Written here' })];
  const stored = diffEntries(base, [], 'L', '', NOW).put;

  it('a stale editor does not write back over a change made elsewhere', () => {
    // Elsewhere: "Pay rent" was completed. This editor still shows it open and edits the other line.
    const elsewhere = stored.map((e) => (e.text === 'Pay rent' ? { ...e, state: 'done' as const } : e));
    const mine = [base[0], { ...base[1], text: 'Written here (typing)' }];
    const { put, remove } = diffEntries(mine, elsewhere, 'L', '', NOW, base);
    expect(put.map((e) => e.text)).toEqual(['Written here (typing)']);
    expect(remove).toEqual([]);
  });

  it('never deletes an entry that arrived from elsewhere, but deletes what this editor removed', () => {
    const arrived = { ...stored[0], id: 'remote-1', text: 'From the iPhone', order: 'a5' };
    const { remove } = diffEntries([base[1]], [...stored, arrived], 'L', '', NOW, base);
    expect(remove).toEqual([base[0].id]);
  });
});

describe('reordering with a base', () => {
  it('writes every line whose order key changed, so stored order matches the page', async () => {
    const { newLine } = await import('../editor/lines');
    const { diffEntries } = await import('./convert');
    const lines = ['Pay', 'Call', 'Dentist', 'Gym', 'none'].map((text) => newLine({ type: 'task', text }));
    const first = diffEntries(lines, [], 'daily:2026-10-19', '', 'T0');
    const sorted = [lines[2], lines[0], lines[1], lines[3], lines[4]];
    const { put } = diffEntries(sorted, first.put, 'daily:2026-10-19', '', 'T1', lines);
    const stored = new Map(first.put.map((e) => [e.id, e]));
    for (const e of put) stored.set(e.id, e);
    const order = [...stored.values()].sort((a, b) => (a.order < b.order ? -1 : 1)).map((e) => e.text);
    expect(order).toEqual(['Dentist', 'Pay', 'Call', 'Gym', 'none']);
  });
});
