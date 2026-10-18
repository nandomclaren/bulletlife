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
