import { createHmac } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import type { Stroke } from './ink';
import { hmac, requestBody } from './myscript';
import { readLineShape } from './structure';

const s = (pts: Array<[number, number]>): Stroke => ({ k: 'w', c: 'ink', r: 0, p: pts.flatMap(([x, y]) => [x, y, 0.5]) });
const word = (x: number) => s([[x, 20], [x + 20, 10], [x + 40, 22], [x + 60, 12]]);
const circle = (cx: number, cy: number, r: number) =>
  s(Array.from({ length: 13 }, (_, i) => [cx + r * Math.cos((i / 12) * 2 * Math.PI), cy + r * Math.sin((i / 12) * 2 * Math.PI)] as [number, number]));

describe('reading a handwritten line', () => {
  it('a dot before the words is a task', () => {
    const shape = readLineShape([s([[40, 20], [42, 21]]), word(62)]);
    expect(shape).toEqual({ type: 'task', bullet: [0], indent: 0 });
  });
  it('a small circle is an event, a dash is a note', () => {
    expect(readLineShape([circle(42, 20, 6), word(62)]).type).toBe('event');
    expect(readLineShape([s([[34, 20], [50, 21]]), word(62)]).type).toBe('note');
  });
  it('words without a bullet are free text', () => {
    expect(readLineShape([word(62), word(140)])).toEqual({ type: 'text', bullet: [], indent: 0 });
  });
  it('a lone mark is not a bullet (it may be a word)', () => {
    expect(readLineShape([s([[40, 20], [42, 21]])]).type).toBe('text');
  });
  it('a big first stroke is a letter, not a bullet', () => {
    expect(readLineShape([s([[60, 4], [64, 36]]), word(70)]).type).toBe('text');
  });
  it('starting further right indents, about a centimeter per level', () => {
    expect(readLineShape([s([[78, 20], [80, 21]]), word(98)]).indent).toBe(1);
    expect(readLineShape([word(60 + 72)]).indent).toBe(2);
    expect(readLineShape([word(70)]).indent).toBe(0);
  });
  it('drawings are left out', () => {
    expect(readLineShape([{ ...word(60), k: 'd' }])).toEqual({ type: 'text', bullet: [], indent: 0 });
  });
});

describe('MyScript request', () => {
  it('sends strokes as x/y/t/p arrays in writing order, in mm', () => {
    const body = requestBody([s([[1, 2], [3, 4]]), s([[5, 6]])], 'pt_BR');
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
