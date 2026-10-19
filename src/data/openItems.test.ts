import { describe, expect, it } from 'vitest';
import { ageLabel, groupItems, groupLabel, openItems, openToday, suggestDestination, withKept } from './openItems';
import { DEFAULT_SETTINGS, type Entry, type Settings } from './types';

const TODAY = '2026-10-19'; // Monday, Wk 43
let n = 0;
const e = (logId: string, text: string, extra: Partial<Entry> = {}): Entry => ({
  id: `e${++n}`,
  logId,
  slot: '',
  parentId: null,
  order: `a${n}`,
  type: 'task',
  state: 'open',
  text,
  signifiers: [],
  collapsed: false,
  createdAt: '',
  updatedAt: '',
  ...extra,
});
const S: Settings = { ...DEFAULT_SETTINGS };
const texts = (entries: Entry[], s = S) => openItems(entries, s, TODAY).map((i) => i.entry.text);

describe('open items (derived, never stored)', () => {
  it('A: open tasks on a Day, Week or Month that has ended', () => {
    const entries = [
      e('weekly:2026-W41', 'last-week task'),
      e('daily:2026-10-18', 'yesterday task'),
      e('daily:2026-10-19', 'today task'),
      e('weekly:2026-W43', 'this week task'),
      e('monthly:2026-09', 'september task'),
      e('monthly:2026-10', 'this month task'),
      e('daily:2026-10-18', 'done', { state: 'done' }),
      e('daily:2026-10-18', 'cancelled', { state: 'cancelled' }),
      e('daily:2026-10-18', 'a note', { type: 'note' }),
      e('daily:2026-10-18', 'free text', { type: 'text' }),
      e('monthly:2026-09', 'day phrase', { type: 'text', slot: '2026-09-03' }),
      e('collection:01X', 'collection task'),
    ];
    expect(texts(entries)).toEqual(['september task', 'last-week task', 'yesterday task']);
  });

  it('events count only with Event states on', () => {
    const entries = [e('daily:2026-10-18', 'dinner', { type: 'event' })];
    expect(texts(entries)).toEqual(['dinner']);
    expect(texts(entries, { ...S, eventStates: false })).toEqual([]);
  });

  it('B: marked > or < without a confirmed destination, anywhere; placed ones leave', () => {
    const entries = [
      e('daily:2026-10-19', 'migrated today', { state: 'migrated', placement: { status: 'pending' } }),
      e('collection:01X', 'scheduled', { state: 'scheduled', placement: { status: 'pending' } }),
      e('daily:2026-10-12', 'placed', { state: 'migrated', placement: { status: 'placed', confirmedAt: TODAY } }),
    ];
    const items = openItems(entries, S, TODAY);
    expect(items.map((i) => [i.entry.text, i.category])).toEqual([
      ['migrated today', 'unplaced'],
      ['scheduled', 'unplaced'],
    ]);
  });

  it('C: Year items whose month has come, grouped by month', () => {
    const entries = [
      e('future:2026', 'november', { slot: '2026-11' }),
      e('future:2026', 'october', { slot: '2026-10' }),
      e('future:2026', 'march', { slot: '2026-03' }),
      e('future:2026', 'march done', { slot: '2026-03', state: 'done' }),
    ];
    const items = openItems(entries, S, TODAY);
    expect(items.map((i) => [i.entry.text, i.category])).toEqual([
      ['march', 'arrived'],
      ['october', 'arrived'],
    ]);
    expect(groupItems(items).map((g) => groupLabel(g))).toEqual(['2026 · March', '2026 · October']);
  });

  it('Due: any open task with a date today or earlier, on any page, first and by date', () => {
    const entries = [
      e('collection:01X', 'pay rent due:2026-10-19'),
      e('daily:2026-10-25', 'future page, overdue due:2026-10-10'),
      e('daily:2026-10-12', 'old, no date'),
      e('weekly:2026-W44', 'later due:2026-10-30'),
      e('daily:2026-10-12', 'done due:2026-10-01', { state: 'done' }),
      e('daily:2026-10-12', 'note due:2026-10-01', { type: 'note' }),
    ];
    const groups = groupItems(openItems(entries, S, TODAY));
    expect(groups.map((g) => [groupLabel(g), g.items.map((i) => i.entry.text)])).toEqual([
      ['Due', ['future page, overdue due:2026-10-10', 'pay rent due:2026-10-19']],
      ['Mon, Oct 12', ['old, no date']],
    ]);
  });

  it('groups by page, oldest first, with origin labels and age', () => {
    const items = openItems([e('daily:2026-10-05', 'b'), e('weekly:2026-W41', 'a'), e('daily:2026-10-05', 'c')], S, TODAY);
    const groups = groupItems(items);
    expect(groups.map((g) => [groupLabel(g), ageLabel(g.source.end, TODAY), g.items.length])).toEqual([
      ['Wk 41 · Oct 5 – 11', 'last week', 1],
      ['Mon, Oct 5', '2 weeks ago', 2],
    ]);
    expect(ageLabel('2026-10-18', TODAY)).toBe('yesterday');
    expect(ageLabel('2026-10-25', TODAY)).toBe('');
  });

  it('Close the day lists what is still open on today', () => {
    const entries = [e('daily:2026-10-19', 'open'), e('daily:2026-10-19', 'done', { state: 'done' }), e('daily:2026-10-18', 'old')];
    expect(openToday(entries, S, TODAY).map((i) => i.entry.text)).toEqual(['open']);
  });

  it('items acted on stay listed with their new state until the panel closes', () => {
    const task = e('daily:2026-10-18', 'tap me');
    const [item] = openItems([task], S, TODAY);
    const done = { ...task, state: 'done' as const };
    const kept = new Map([[task.id, item]]);
    const shown = withKept(openItems([done], S, TODAY), kept, new Map([[task.id, done]]));
    expect(shown.map((i) => [i.entry.text, i.entry.state])).toEqual([['tap me', 'done']]);
  });
});

describe('suggested destination (read-only)', () => {
  const at = (logId: string, mark: 'migrated' | 'scheduled', s: Settings = S, slot = '') => {
    const d = suggestDestination({ logId, slot }, mark, s, TODAY);
    return `${d.label} ${d.path}`;
  };
  it('> goes to the next period of the same log, or the current one for older items', () => {
    expect(at('daily:2026-10-19', 'migrated')).toBe('Tomorrow /day/2026-10-20');
    expect(at('daily:2026-10-12', 'migrated')).toBe('Today /day/2026-10-19');
    expect(at('weekly:2026-W43', 'migrated')).toBe('Wk 44 /week/2026-W44');
    expect(at('monthly:2026-10', 'migrated')).toBe('November /month/2026-11');
  });
  it('> from the Year comes down to this Month; from a collection to the finest log', () => {
    expect(at('future:2026', 'migrated', S, '2026-10')).toBe('This Month /month/2026-10');
    expect(at('collection:01X', 'migrated')).toBe('Today /day/2026-10-19');
    const weekOnly = { ...S, activeLogs: { monthly: false, weekly: true, daily: false } };
    expect(at('daily:2026-10-12', 'migrated', weekOnly)).toBe('This week /week/2026-W43');
  });
  it('< goes to the Year, at the month after the item', () => {
    expect(at('daily:2026-10-19', 'scheduled')).toBe('2026 · November /year/2026');
    expect(at('monthly:2026-12', 'scheduled')).toBe('2027 · January /year/2027');
    expect(at('future:2026', 'scheduled', S, '2026-10')).toBe('2026 · November /year/2026');
  });
});
