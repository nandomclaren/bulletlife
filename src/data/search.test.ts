import { describe, expect, it } from 'vitest';
import { searchCollections, searchEntries } from './search';
import type { Entry, Log } from './types';

const e = (id: string, text: string, updatedAt: string, extra: Partial<Entry> = {}): Entry => ({
  id,
  logId: 'daily:2026-10-19',
  slot: '',
  parentId: null,
  order: 'a0',
  type: 'task',
  state: 'open',
  text,
  signifiers: [],
  collapsed: false,
  createdAt: updatedAt,
  updatedAt,
  ...extra,
});

describe('global search', () => {
  const entries = [
    e('1', 'Ligar para o Banco', '2026-10-01'),
    e('2', 'Renew passport at the consulate', '2026-10-10'),
    e('3', 'banco de dados', '2026-10-15', { collapsed: true }),
    e('4', '   ', '2026-10-16'),
  ];
  it('finds every word, ignoring case and accents, newest first, collapsed included', () => {
    expect(searchEntries(entries, 'BANCO').map((h) => h.item.id)).toEqual(['3', '1']);
    expect(searchEntries(entries, 'passport consul').map((h) => h.item.id)).toEqual(['2']);
    expect(searchEntries(entries, 'lígar banco')[0].ranges).toEqual([
      [0, 5],
      [13, 18],
    ]);
    expect(searchEntries(entries, '  ')).toEqual([]);
  });

  it('matches collection names', () => {
    const logs: Log[] = [{ id: 'collection:1', kind: 'collection', title: 'Livros lidos', createdAt: '', updatedAt: '' }];
    expect(searchCollections(logs, 'livros').map((h) => h.item.title)).toEqual(['Livros lidos']);
  });
});
