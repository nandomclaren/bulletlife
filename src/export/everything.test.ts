import { describe, expect, it } from 'vitest';
import type { Log } from '../data/types';
import { orderPages } from './everything';

const col = (id: string, title: string): Log => ({ id, kind: 'collection', title, createdAt: '', updatedAt: '' });

describe('export everything as Markdown', () => {
  it('orders Years, Months, Weeks, Days oldest first, then collections by name; skips empty collections', () => {
    const ids = ['daily:2026-10-19', 'collection:B', 'weekly:2026-W43', 'daily:2026-10-02', 'future:2026', 'monthly:2026-10', 'weekly:2026-W09', 'collection:A'];
    const pages = orderPages(ids, [col('collection:A', 'Reading'), col('collection:B', 'Errands'), col('collection:C', 'Empty')]);
    expect(pages.map((p) => (p.kind === 'collection' ? p.title : `${p.kind}:${p.key}`))).toEqual([
      'future:2026',
      'monthly:2026-10',
      'weekly:2026-W09',
      'weekly:2026-W43',
      'daily:2026-10-02',
      'daily:2026-10-19',
      'Errands',
      'Reading',
    ]);
  });
});
