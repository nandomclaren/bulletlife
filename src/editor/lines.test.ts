import { describe, expect, it } from 'vitest';
import { colorTypes, glyph, hiddenMask, matchPrefix, nextState, parentIds, shiftIndent, subtreeEnd } from './lines';

describe('matchPrefix', () => {
  it('recognizes each bullet prefix with a trailing space', () => {
    expect(matchPrefix('. ')).toEqual({ type: 'task', priority: false, length: 2 });
    expect(matchPrefix('o. ')).toEqual({ type: 'event', priority: false, length: 3 });
    expect(matchPrefix('- ')).toEqual({ type: 'note', priority: false, length: 2 });
    expect(matchPrefix('# ')).toEqual({ type: 'heading', priority: false, length: 2 });
  });

  it('handles priority before a bullet', () => {
    expect(matchPrefix('* . ')).toEqual({ type: 'task', priority: true, length: 4 });
    expect(matchPrefix('* o. ')).toEqual({ type: 'event', priority: true, length: 5 });
  });

  it('does not fire on plain words', () => {
    expect(matchPrefix('o ')).toBeNull();
    expect(matchPrefix('of ')).toBeNull();
    expect(matchPrefix('.')).toBeNull();
    expect(matchPrefix('hello ')).toBeNull();
  });
});

describe('state cycle', () => {
  it('goes open → done → cancelled → open', () => {
    expect(nextState('open')).toBe('done');
    expect(nextState('done')).toBe('cancelled');
    expect(nextState('cancelled')).toBe('open');
  });

  it('notes never show a state glyph; events only with event states on', () => {
    expect(glyph('note', 'done', true)).toBe('–');
    expect(glyph('event', 'done', true)).toBe('×');
    expect(glyph('event', 'done', false)).toBe('○');
    expect(glyph('task', 'migrated', true)).toBe('>');
  });
});

describe('tree helpers', () => {
  const lines = [
    { id: 'a', indent: 0, type: 'task' as const, collapsed: true },
    { id: 'b', indent: 1, type: 'note' as const, collapsed: false },
    { id: 'c', indent: 2, type: 'event' as const, collapsed: false },
    { id: 'd', indent: 0, type: 'event' as const, collapsed: false },
  ];

  it('derives parents from indentation', () => {
    expect(parentIds(lines)).toEqual([null, 'a', 'b', null]);
  });

  it('children inherit the root color', () => {
    expect(colorTypes(lines)).toEqual(['task', 'task', 'task', 'event']);
  });

  it('collapsing hides the whole subtree only', () => {
    expect(hiddenMask(lines)).toEqual([false, true, true, false]);
    expect(subtreeEnd(lines, 0)).toBe(3);
  });
});

describe('shiftIndent', () => {
  const l = (...indents: number[]) => indents.map((indent) => ({ indent }));

  it('indents a line with its subtree', () => {
    expect(shiftIndent(l(0, 0, 1, 0), 1, 1, 1)).toEqual([0, 1, 2, 0]);
  });

  it('refuses to indent deeper than one level below the line above', () => {
    expect(shiftIndent(l(0, 1), 1, 1, 1)).toBeNull();
    expect(shiftIndent(l(0), 0, 0, 1)).toBeNull();
  });

  it('outdents with the subtree and refuses at level 0', () => {
    expect(shiftIndent(l(0, 1, 2, 1), 1, 1, -1)).toEqual([0, 0, 1, 1]);
    expect(shiftIndent(l(0, 1), 0, 0, -1)).toBeNull();
  });
});
