import { describe, expect, it } from 'vitest';
import { assignOrders } from './order';

const increasing = (keys: string[]) => keys.every((k, i) => i === 0 || keys[i - 1] < k);

describe('assignOrders', () => {
  it('creates increasing keys for new items', () => {
    const keys = assignOrders(['a', 'b', 'c'], new Map());
    expect(increasing(keys)).toBe(true);
  });

  it('keeps existing keys when nothing moved', () => {
    const existing = new Map([
      ['a', 'a0'],
      ['b', 'a1'],
      ['c', 'a2'],
    ]);
    expect(assignOrders(['a', 'b', 'c'], existing)).toEqual(['a0', 'a1', 'a2']);
  });

  it('only rewrites the inserted and moved items', () => {
    const existing = new Map([
      ['a', 'a0'],
      ['b', 'a1'],
      ['c', 'a2'],
    ]);
    const keys = assignOrders(['a', 'x', 'c', 'b'], existing);
    expect(keys[0]).toBe('a0');
    expect(keys[2]).toBe('a2');
    expect(keys[1] > 'a0' && keys[1] < 'a2').toBe(true);
    expect(keys[3] > 'a2').toBe(true);
    expect(increasing(keys)).toBe(true);
  });
});
