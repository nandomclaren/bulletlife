import { describe, expect, it } from 'vitest';
import { dateRuns, dueLabel, dueOf, parseDueExpr, resolveDue, sortRun } from './due';
import { newLine, type Line } from './lines';

const TODAY = '2026-10-19'; // Monday
const p = (s: string, order: 'dmy' | 'mdy' = 'dmy') => parseDueExpr(s, TODAY, order)?.iso ?? null;

describe('due: parsing', () => {
  it('ISO, short dates (this year) and words', () => {
    expect(p('2026-12-03')).toBe('2026-12-03');
    expect(p('23/10')).toBe('2026-10-23');
    expect(p('10-23')).toBe('2026-10-23'); // only makes sense month first
    expect(p('03/04')).toBe('2026-04-03');
    expect(p('03/04', 'mdy')).toBe('2026-03-04');
    expect(p('01-02 rest')).toBe('2026-02-01'); // this year even if it has passed
    expect(p('today')).toBe(TODAY);
    expect(p('Tomorrow')).toBe('2026-10-20');
    expect(p('yesterday')).toBe('2026-10-18');
    expect(p('fri')).toBe('2026-10-23');
    expect(p('monday')).toBe('2026-10-19');
    expect(p('next monday')).toBe('2026-10-26');
    expect(p('next week')).toBe('2026-10-26');
    expect(p('next month')).toBe('2026-11-01');
    expect(p('in 3 days')).toBe('2026-10-22');
    expect(p('in 2 weeks')).toBe('2026-11-02');
  });

  it('unfinished or invalid expressions are left alone', () => {
    expect(p('next')).toBeNull();
    expect(p('in 3')).toBeNull();
    expect(p('tomorrowx')).toBeNull();
    expect(p('31/02')).toBeNull();
    expect(p('2026-13-01')).toBeNull();
  });

  it('resolves finished expressions in the text, keeping the rest', () => {
    expect(resolveDue('Call Ana due:tomorrow about rent', TODAY)).toEqual({ text: 'Call Ana due:2026-10-20 about rent', shift: 2 });
    expect(resolveDue('Pay due:next monday', TODAY)?.text).toBe('Pay due:2026-10-26');
    expect(resolveDue('Pay due:2026-10-26', TODAY)).toBeNull();
    expect(resolveDue('Pay due:next', TODAY)).toBeNull();
    expect(resolveDue('overdue:today', TODAY)).toBeNull();
    // Only what ends before the caret.
    expect(resolveDue('a due:fri', TODAY, 'dmy', 1, 7)).toBeNull();
    expect(dueOf('x due:2026-10-26 y')).toBe('2026-10-26');
  });

  it('labels: relative near today, otherwise day and month', () => {
    expect(dueLabel('2026-10-19', TODAY)).toBe('Today');
    expect(dueLabel('2026-10-20', TODAY)).toBe('Tomorrow');
    expect(dueLabel('2026-10-18', TODAY)).toBe('Yesterday');
    expect(dueLabel('2026-10-23', TODAY)).toBe('23 Oct');
    expect(dueLabel('2026-10-23', TODAY, 'mdy')).toBe('Oct 23');
    expect(dueLabel('2027-01-05', TODAY)).toBe('5 Jan 2027');
  });
});

describe('sorting a list by date (on request)', () => {
  const L = (text: string, p: Partial<Line> = {}) => newLine({ type: 'task', text, ...p });
  const lines = [
    L('List', { type: 'heading' }),
    L('b due:2026-10-25'),
    L('child of b', { type: 'note', indent: 1 }),
    L('no date'),
    L('a due:2026-10-20', { state: 'cancelled' }),
    L('c due:2026-11-02'),
    L('free text', { type: 'text' }),
    L('alone due:2026-10-01'),
  ];

  it('finds runs of two or more sibling bullets with a date', () => {
    const runs = dateRuns(lines);
    expect(runs).toHaveLength(1);
    expect(runs[0]).toEqual({ items: [1, 3, 4, 5], sorted: false });
  });

  it('sorts nearest first, cancelled too, undated last; children move with their item', () => {
    const sorted = sortRun(lines, dateRuns(lines)[0]);
    expect(sorted.map((l) => l.text)).toEqual([
      'List',
      'a due:2026-10-20',
      'b due:2026-10-25',
      'child of b',
      'c due:2026-11-02',
      'no date',
      'free text',
      'alone due:2026-10-01',
    ]);
    expect(dateRuns(sorted)[0].sorted).toBe(true);
  });
});
