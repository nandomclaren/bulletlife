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

describe('numbered lines', () => {
  it('finds a leading list number only when followed by a space', async () => {
    const { numberPrefix } = await import('./lines');
    expect(numberPrefix('1. Mistborn')).toBe('1.');
    expect(numberPrefix('12) Second')).toBe('12)');
    expect(numberPrefix('1.5 kg of flour')).toBeNull();
    expect(numberPrefix('2026 was good')).toBeNull();
  });

  it('a numbered plain line colors like a task and its children inherit', () => {
    const lines = [
      { type: 'text' as const, indent: 0, text: '1. Mistborn' },
      { type: 'note' as const, indent: 1, text: 'When: Jan' },
      { type: 'text' as const, indent: 0, text: 'Plain line' },
    ];
    expect(colorTypes(lines)).toEqual(['task', 'task', 'text']);
  });
});

describe('list numbers', () => {
  it('continues the list with the next number', async () => {
    const { nextNumber } = await import('./lines');
    expect(nextNumber('2.')).toBe('3.');
    expect(nextNumber('9)')).toBe('10)');
  });
});

describe('renumberLists', () => {
  // Simulates an edit: `before` is the list before it, `after` the list after it.
  const run = async (before: string[] | null, after: Array<[number, string]>) => {
    const { renumberLists, listRestarts } = await import('./lines');
    const lines = after.map(([indent, text], i) => ({ id: `l${i}`, indent, text }));
    const keep = before ? listRestarts(before.map((t, i) => ({ id: `l${i}`, indent: 0, text: t }))) : new Set<string>();
    renumberLists(lines, keep);
    return lines.map((l) => l.text);
  };

  it('renumbers after an item is inserted or removed', async () => {
    expect(await run(null, [[0, '1. a'], [0, '2. new'], [0, '2. b'], [0, '3. c']])).toEqual(['1. a', '2. new', '3. b', '4. c']);
    expect(await run(null, [[0, '1. a'], [0, '3. c']])).toEqual(['1. a', '2. c']);
  });

  it('counts siblings across their children and keeps nested lists separate', async () => {
    expect(await run(null, [[0, '1. a'], [1, 'note'], [1, '1. sub'], [1, '5. sub'], [0, '7. b']])).toEqual(['1. a', 'note', '1. sub', '2. sub', '2. b']);
  });

  it('a plain sibling ends the list; the first item keeps its number and separator', async () => {
    expect(await run(null, [[0, '4) a'], [0, '1. b'], [0, 'plain'], [0, '9. c']])).toEqual(['4) a', '5) b', 'plain', '9. c']);
  });

  it('keeps a number the user typed out of sequence and counts on from it', async () => {
    // "1. a / 2. b / 10. x" then Enter on 10 → new "11." line
    expect(await run(['1. a', '2. b', '10. x'], [[0, '1. a'], [0, '2. b'], [0, '10. x'], [0, '11. ']])).toEqual(['1. a', '2. b', '10. x', '11. ']);
    // deleting "b" still renumbers the in-sequence items, but not the chosen 10
    const { renumberLists, listRestarts } = await import('./lines');
    const before = ['1. a', '2. b', '3. c', '10. x', '11. y'].map((text, i) => ({ id: 'abcxy'[i], indent: 0, text }));
    const after = before.filter((l) => l.id !== 'b').map((l) => ({ ...l }));
    renumberLists(after, listRestarts(before));
    expect(after.map((l) => l.text)).toEqual(['1. a', '2. c', '10. x', '11. y']);
  });
});

describe('restartIfFirst', () => {
  it('an item indented into a new nested list starts at 1; one joining a list keeps counting', async () => {
    const { restartIfFirst } = await import('./lines');
    const a = [{ indent: 0, text: '1. Alpha' }, { indent: 1, text: '2. Inserted' }];
    restartIfFirst(a, 1);
    expect(a[1].text).toBe('1. Inserted');
    const b = [{ indent: 0, text: '1. a' }, { indent: 0, text: '2. b' }, { indent: 0, text: '3. c' }];
    restartIfFirst(b, 2);
    expect(b[2].text).toBe('3. c');
  });
});

describe('colors under a heading', () => {
  it('items under a section title keep their own color; children still inherit from a bullet', async () => {
    const { colorTypes } = await import('./lines');
    const lines = [
      { type: 'heading' as const, indent: 0 },
      { type: 'task' as const, indent: 1 },
      { type: 'note' as const, indent: 2 },
      { type: 'event' as const, indent: 1 },
    ];
    expect(colorTypes(lines)).toEqual(['heading', 'task', 'task', 'event']);
  });
});
