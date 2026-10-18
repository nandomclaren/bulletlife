import { describe, expect, it } from 'vitest';
import { isLastActive, toggleActiveLog } from './settings';

describe('active logs', () => {
  const all = { monthly: true, weekly: true, daily: true };

  it('turns logs off while at least one stays on', () => {
    expect(toggleActiveLog(all, 'weekly')).toEqual({ monthly: true, weekly: false, daily: true });
  });

  it('never allows all three off', () => {
    const onlyDay = { monthly: false, weekly: false, daily: true };
    expect(toggleActiveLog(onlyDay, 'daily')).toBeNull();
    expect(isLastActive(onlyDay, 'daily')).toBe(true);
    expect(isLastActive(onlyDay, 'weekly')).toBe(false);
  });

  it('turns a log back on', () => {
    expect(toggleActiveLog({ monthly: false, weekly: false, daily: true }, 'monthly')).toEqual({
      monthly: true,
      weekly: false,
      daily: true,
    });
  });
});
