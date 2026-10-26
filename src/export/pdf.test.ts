import { describe, expect, it } from 'vitest';
import { pagesInRange } from './pdf';

describe('PDF pages in notebook order', () => {
  const ids = ['daily:2026-10-27', 'monthly:2026-10', 'weekly:2026-W44', 'future:2026', 'daily:2026-10-26', 'daily:2026-09-30', 'monthly:2026-09', 'daily:2025-12-31'];
  const cols = [{ id: 'collection:b', title: 'Waiting for' }, { id: 'collection:a', title: 'Recurring' }];

  it('Year first, then each Month with its weeks and days in date order', () => {
    const refs = pagesInRange(ids, cols, 'year', '2026-10-27');
    expect(refs.map((r) => ('key' in r ? `${r.kind}:${r.key}` : r.id))).toEqual([
      'future:2026',
      'monthly:2026-09',
      'daily:2026-09-30',
      'monthly:2026-10',
      'weekly:2026-W44',
      'daily:2026-10-26',
      'daily:2026-10-27',
    ]);
  });

  it('this month keeps the pages that overlap it', () => {
    const refs = pagesInRange(ids, cols, 'month', '2026-10-27');
    expect(refs.map((r) => ('key' in r ? `${r.kind}:${r.key}` : r.id))).toEqual(['future:2026', 'monthly:2026-10', 'weekly:2026-W44', 'daily:2026-10-26', 'daily:2026-10-27']);
  });

  it('everything adds every year and the collections at the end', () => {
    const refs = pagesInRange(ids, cols, 'all', '2026-10-27');
    expect(refs[0]).toEqual({ kind: 'daily', key: '2025-12-31' });
    expect(refs.slice(-2)).toEqual([
      { kind: 'collection', id: 'collection:a', title: 'Recurring' },
      { kind: 'collection', id: 'collection:b', title: 'Waiting for' },
    ]);
  });
});
