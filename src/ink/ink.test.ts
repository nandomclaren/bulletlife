import { describe, expect, it } from 'vitest';
import { diffEntries, entriesToLines, isBlank } from '../data/convert';
import type { Entry } from '../data/types';
import { newLine } from '../editor/lines';
import { compact, inkRows, ROW, strokeHit, type Stroke } from './ink';

const w = (r: number, p: number[]): Stroke => ({ k: 'w', c: 'ink', r, p });

describe('ink rows', () => {
  it('counts the rows writing was written on, not where descenders reach', () => {
    expect(inkRows({ strokes: [w(0, [0, 10, 0.5, 20, 52, 0.5])] })).toBe(1);
    expect(inkRows({ strokes: [w(0, [0, 10, 0.5]), w(2, [0, 90, 0.5])] })).toBe(3);
  });
  it('counts every row a drawing covers', () => {
    expect(inkRows({ strokes: [{ k: 'd', c: 'ink', r: 0, p: [0, 5, 0.5, 10, 2 * ROW + 10, 0.5] }] })).toBe(3);
  });
  it('is 0 without ink', () => {
    expect(inkRows(undefined)).toBe(0);
    expect(inkRows({ strokes: [] })).toBe(0);
  });
});

describe('eraser', () => {
  it('hits a stroke passing near the eraser path, offset by the entry top', () => {
    const p = [10, 10, 0.5, 50, 10, 0.5];
    expect(strokeHit(p, 100, [[50, 112]], 5)).toBe(true);
    expect(strokeHit(p, 100, [[50, 130]], 5)).toBe(false);
  });
});

it('rounds stored points', () => {
  expect(compact([1.234, 5.678, 0.12345])).toEqual([1.2, 5.7, 0.12]);
});

describe('ink in the model', () => {
  const entry = (id: string, ink?: Entry['ink']): Entry => ({
    id,
    logId: 'daily:2026-10-26',
    slot: '',
    parentId: null,
    order: 'a0',
    type: 'text',
    state: 'open',
    text: '',
    signifiers: [],
    collapsed: false,
    ...(ink ? { ink } : {}),
    createdAt: 'x',
    updatedAt: 'x',
  });
  const ink = { strokes: [w(0, [1, 2, 0.5])] };

  it('a line with only ink is not a blank page', () => {
    expect(isBlank([newLine({ ink })])).toBe(false);
    expect(isBlank([newLine()])).toBe(true);
  });

  it('typed edits keep the stored ink', () => {
    const [line] = entriesToLines([entry('e1', ink)]);
    expect(line.ink).toEqual(ink);
    const { put } = diffEntries([{ ...line, text: 'typed too', ink: undefined }], [entry('e1', ink)], 'daily:2026-10-26', '', 'now', [line]);
    expect(put[0].ink).toEqual(ink);
  });

  it('clearing the text of a handwritten line in Type mode stops it from being transcribed again', () => {
    const stored = { ...entry('e1', ink), text: 'A' };
    const [line] = entriesToLines([stored]);
    const { put } = diffEntries([{ ...line, text: '' }], [stored], 'daily:2026-10-26', '', 'now', [line]);
    expect(put[0].ink).toMatchObject({ tx: '', n: 1 });
    expect(put[0].text).toBe('');
  });

  it('ink removed in the text editor is removed from storage, and undo brings it back', () => {
    const other = { ...entry('t1'), order: 'a1', text: 'typed' };
    const stored = entry('e1', ink);
    const [line, typed] = entriesToLines([stored, other]);
    const cut = { ...line, ink: undefined, inkEdit: null };
    const removed = diffEntries([cut, typed], [stored, other], 'daily:2026-10-26', '', 'now', [line, typed]);
    const e1 = removed.put.find((e) => e.id === 'e1')!;
    expect(e1.ink).toBeUndefined();
    const back = diffEntries([line, typed], [e1, other], 'daily:2026-10-26', '', 'now', [cut, typed]);
    expect(back.put.find((e) => e.id === 'e1')!.ink).toEqual(ink);
  });

  it('a deleted ink line brought back (undo) gets its ink back', () => {
    const line = newLine({ ink });
    const { put } = diffEntries([line], [], 'daily:2026-10-26', '', 'now', []);
    expect(put[0].ink).toEqual(ink);
  });
});
