import { createHmac } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import type { Stroke } from './ink';
import { hmac, requestBody } from './myscript';
import { lassoed, placeStroke, readLineShape, rowWithin, strokeRow, type PlacedBlock } from './structure';

const s = (pts: Array<[number, number]>): Stroke => ({ k: 'w', c: 'ink', r: 0, p: pts.flatMap(([x, y]) => [x, y, 0.5]) });
const word = (x: number) =>
  s([
    [x, 20],
    [x + 20, 10],
    [x + 40, 22],
    [x + 60, 12],
  ]);
const circle = (cx: number, cy: number, r: number) =>
  s(Array.from({ length: 13 }, (_, i) => [cx + r * Math.cos((i / 12) * 2 * Math.PI), cy + r * Math.sin((i / 12) * 2 * Math.PI)] as [number, number]));

describe('reading a handwritten line', () => {
  it('a dot before the words is a task', () => {
    const shape = readLineShape([
      s([
        [40, 20],
        [42, 21],
      ]),
      word(62),
    ]);
    expect(shape).toEqual({ type: 'task', bullet: [0], indent: 0 });
  });
  it('a small circle is an event, a dash is a note', () => {
    expect(readLineShape([circle(42, 20, 6), word(62)]).type).toBe('event');
    expect(
      readLineShape([
        s([
          [34, 20],
          [50, 21],
        ]),
        word(62),
      ]).type,
    ).toBe('note');
  });
  it('words without a bullet are free text', () => {
    expect(readLineShape([word(62), word(140)])).toEqual({ type: 'text', bullet: [], indent: 0 });
  });
  it('a lone mark is not a bullet (it may be a word)', () => {
    expect(
      readLineShape([
        s([
          [40, 20],
          [42, 21],
        ]),
      ]).type,
    ).toBe('text');
  });
  it('a big first stroke is a letter, not a bullet', () => {
    expect(
      readLineShape([
        s([
          [60, 4],
          [64, 36],
        ]),
        word(70),
      ]).type,
    ).toBe('text');
  });
  it('starting further right indents, about a centimeter per level', () => {
    expect(
      readLineShape([
        s([
          [78, 20],
          [80, 21],
        ]),
        word(98),
      ]).indent,
    ).toBe(1);
    expect(readLineShape([word(60 + 72)]).indent).toBe(2);
    expect(readLineShape([word(70)]).indent).toBe(0);
  });
  it('drawings are left out', () => {
    expect(readLineShape([{ ...word(60), k: 'd' }])).toEqual({ type: 'text', bullet: [], indent: 0 });
  });
});

describe('MyScript request', () => {
  it('sends strokes as x/y/t/p arrays in writing order, in mm', () => {
    const body = requestBody(
      [
        s([
          [1, 2],
          [3, 4],
        ]),
        s([[5, 6]]),
      ],
      'pt_BR',
    );
    expect(body.configuration.lang).toBe('pt_BR');
    expect(body.contentType).toBe('Text');
    expect(body.scaleX).toBe(0.265);
    expect(body.strokes[0]).toMatchObject({ x: [1, 3], y: [2, 4], p: [0.5, 0.5], pointerType: 'pen' });
    expect(body.strokes[1].t[0]).toBeGreaterThan(body.strokes[0].t[1]);
  });
  it('signs the body with HMAC-SHA512 keyed by application key + HMAC key', async () => {
    const keys = { applicationKey: 'app', hmacKey: 'secret' };
    const expected = createHmac('sha512', 'appsecret').update('{"a":1}').digest('hex');
    expect(await hmac('{"a":1}', keys)).toBe(expected);
  });
});

const at = (pts: Array<[number, number]>, k: 'w' | 'd' = 'w'): Stroke => ({ k, c: 'ink', r: 0, p: pts.flatMap(([x, y]) => [x, y, 0.5]) });
const box = (s: Stroke) => {
  const xs = s.p.filter((_, i) => i % 3 === 0);
  const ys = s.p.filter((_, i) => i % 3 === 1);
  return { x0: Math.min(...xs), x1: Math.max(...xs), y0: Math.min(...ys), y1: Math.max(...ys) };
};

describe('which ruled line a stroke is on', () => {
  it('reads a descender (g, q, p) by its top, so it stays on its line', () => {
    const g = at([
      [100, 18],
      [110, 38],
      [104, 62],
    ]); // x-height on line 0, tail deep into line 1
    expect(strokeRow(box(g), 'w', null, 0)).toBe(0);
  });
  it('a capital reaching above the line still belongs to it', () => {
    expect(
      strokeRow(
        box(
          at([
            [100, 36],
            [100, 72],
          ]),
        ),
        'w',
        null,
        0,
      ),
    ).toBe(1);
  });
  it('an accent made right after a letter on the line below stays with it', () => {
    const accent = box(
      at([
        [100, 34],
        [104, 30],
      ]),
    );
    expect(strokeRow(accent, 'w', null, 0)).toBe(0);
    expect(strokeRow(accent, 'w', { row: 1, at: 1000 }, 1500)).toBe(1);
  });
  it('a short word opening the next line stays on that line', () => {
    const e = box(
      at([
        [20, 98],
        [30, 110],
      ]),
    );
    expect(strokeRow(e, 'w', { row: 1, at: 1000 }, 1300)).toBe(2);
  });
});

describe('placing a stroke', () => {
  const typed = (id: string, top: number, rows = 1): PlacedBlock => ({ id, top, height: rows * 40, typed: true, strokes: [] });
  const hand = (id: string, top: number, rows: number, startX = 20): PlacedBlock => ({
    id,
    top,
    height: rows * 40,
    typed: false,
    strokes: Array.from({ length: rows }, (_, r) => ({
      ...at([
        [startX, 20],
        [startX + 80, 24],
      ]),
      r,
    })),
  });

  it('writing under a typed heading starts a new entry after it, never inside it', () => {
    const p = placeStroke(
      [typed('h', 0, 2)],
      80,
      at([
        [20, 50],
        [80, 60],
      ]),
      1,
    );
    expect(p).toEqual({ after: 'h', blanks: 0, top: 80 });
  });
  it('more writing on a handwritten line joins it', () => {
    expect(
      placeStroke(
        [hand('a', 0, 1)],
        40,
        at([
          [150, 20],
          [200, 25],
        ]),
        0,
      ),
    ).toEqual({ join: 'a', r: 0, top: 0 });
  });
  it('the line right below continues the paragraph', () => {
    expect(
      placeStroke(
        [hand('a', 0, 2)],
        80,
        at([
          [22, 100],
          [90, 110],
        ]),
        2,
      ),
    ).toEqual({ join: 'a', r: 2, top: 0 });
  });
  it('a line opening with a dot or dash, or clearly further right, is a new entry', () => {
    expect(
      placeStroke(
        [hand('a', 0, 1)],
        40,
        at([
          [10, 60],
          [11, 61],
        ]),
        1,
      ),
    ).toEqual({ after: null, blanks: 0, top: 40 });
    expect(
      placeStroke(
        [hand('a', 0, 1)],
        40,
        at([
          [10, 60],
          [26, 61],
        ]),
        1,
      ),
    ).toEqual({ after: null, blanks: 0, top: 40 });
    expect(
      placeStroke(
        [hand('a', 0, 1)],
        40,
        at([
          [80, 60],
          [140, 66],
        ]),
        1,
      ),
    ).toEqual({ after: null, blanks: 0, top: 40 });
  });
  it('after a skipped line, a new entry with a blank line before it', () => {
    expect(
      placeStroke(
        [hand('a', 0, 1)],
        40,
        at([
          [20, 100],
          [90, 110],
        ]),
        2,
      ),
    ).toEqual({ after: null, blanks: 1, top: 80 });
  });
  it('a blank line takes what is written on it', () => {
    const blank: PlacedBlock = { id: 'b', top: 40, height: 40, typed: false, strokes: [] };
    expect(
      placeStroke(
        [hand('a', 0, 1), blank, hand('c', 80, 1)],
        120,
        at([
          [20, 60],
          [90, 66],
        ]),
        1,
      ),
    ).toEqual({ join: 'b', r: 0, top: 40 });
  });
  it('writing over a drawing (beside it) joins it, every stroke in the same place', () => {
    const drawing: PlacedBlock = {
      id: 'd',
      top: 0,
      height: 160,
      typed: false,
      strokes: [
        {
          ...at(
            [
              [200, 10],
              [300, 150],
            ],
            'd',
          ),
        },
      ],
    };
    expect(
      placeStroke(
        [drawing],
        160,
        at([
          [20, 90],
          [40, 110],
        ]),
        2,
      ),
    ).toEqual({ join: 'd', r: 2, top: 0 });
    expect(
      placeStroke(
        [drawing],
        160,
        at([
          [50, 90],
          [70, 110],
        ]),
        2,
      ),
    ).toEqual({ join: 'd', r: 2, top: 0 });
  });
  it('the rest of a line written over a typed entry stays with the entry it started', () => {
    const blocks = [typed('h', 0, 1), hand('n', 40, 1)];
    expect(
      placeStroke(
        blocks,
        80,
        at([
          [60, 10],
          [80, 30],
        ]),
        0,
        'n',
      ),
    ).toEqual({ join: 'n', r: 0, top: 40 });
    expect(
      placeStroke(
        blocks,
        80,
        at([
          [60, 10],
          [80, 30],
        ]),
        0,
        null,
      ),
    ).toEqual({ after: 'h', blanks: 0, top: 40 });
  });
  it('a drawing gets its own entry instead of joining handwriting', () => {
    expect(
      placeStroke(
        [hand('a', 0, 1)],
        40,
        at(
          [
            [20, 10],
            [90, 30],
          ],
          'd',
        ),
        0,
      ),
    ).toEqual({ after: 'a', blanks: 0, top: 40 });
  });
});

describe('lasso', () => {
  const st = (pts: Array<[number, number]>): Stroke => ({ k: 'w', c: 'ink', r: 0, p: pts.flatMap(([x, y]) => [x, y, 0.5]) });
  const blocks = [
    { id: 'a', top: 0, strokes: [st([[20, 10], [60, 30]]), st([[200, 10], [240, 30]])] },
    { id: 'b', top: 40, strokes: [st([[20, 10], [60, 30]])] },
  ];
  it('takes the strokes the loop goes around, across lines', () => {
    const loop: Array<[number, number]> = [[0, 0], [100, 0], [100, 80], [0, 80]];
    expect(lassoed(blocks, loop)).toEqual([
      { id: 'a', i: 0 },
      { id: 'b', i: 0 },
    ]);
  });
  it('leaves strokes mostly outside the loop', () => {
    expect(lassoed(blocks, [[0, 0], [30, 0], [30, 40], [0, 40]])).toEqual([]);
  });
  it('reads the ruled line of a dropped stroke within its new entry', () => {
    expect(rowWithin([20, 90, 0.5, 60, 110, 0.5], 40)).toBe(1);
  });
});
