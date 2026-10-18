import { describe, expect, it } from 'vitest';
import { addMonths, addWeeks, daysInMonth, isoWeek, weekDays, weekKey, weekKeyStart, weekStart } from './dates';

describe('weeks', () => {
  it('numbers weeks like ISO 8601', () => {
    expect(isoWeek('2026-10-18')).toEqual({ year: 2026, week: 42 });
    expect(isoWeek('2026-10-19')).toEqual({ year: 2026, week: 43 });
    expect(isoWeek('2027-01-01')).toEqual({ year: 2026, week: 53 });
    expect(isoWeek('2026-01-01')).toEqual({ year: 2026, week: 1 });
  });

  it('starts weeks on the chosen day', () => {
    expect(weekStart('2026-10-18', 1)).toBe('2026-10-12'); // Sunday → previous Monday
    expect(weekStart('2026-10-18', 0)).toBe('2026-10-18'); // Sunday-first
  });

  it('round-trips week keys for Monday and Sunday starts', () => {
    expect(weekKey('2026-10-18', 1)).toBe('2026-W42');
    expect(weekKeyStart('2026-W42', 1)).toBe('2026-10-12');
    expect(weekKey('2026-10-18', 0)).toBe('2026-W43');
    expect(weekKeyStart('2026-W43', 0)).toBe('2026-10-18');
    expect(weekDays('2026-W43', 1)).toEqual([
      '2026-10-19',
      '2026-10-20',
      '2026-10-21',
      '2026-10-22',
      '2026-10-23',
      '2026-10-24',
      '2026-10-25',
    ]);
  });

  it('steps across year boundaries', () => {
    expect(addWeeks('2026-W53', 1, 1)).toBe('2027-W01');
    expect(addWeeks('2027-W01', -1, 1)).toBe('2026-W53');
  });
});

describe('months', () => {
  it('knows month lengths and steps across years', () => {
    expect(daysInMonth('2026-02')).toBe(28);
    expect(daysInMonth('2028-02')).toBe(29);
    expect(addMonths('2026-12', 1)).toBe('2027-01');
    expect(addMonths('2026-01', -1)).toBe('2025-12');
  });
});
