import { describe, expect, it } from 'vitest';
import { bestMatch, isStrongMatch, normalize } from './similar';

const m = (a: string, b: string) => isStrongMatch(normalize(a), normalize(b));

describe('recognizing a rewritten item', () => {
  it('normalizes case, accents, punctuation, stopwords and dates', () => {
    expect(normalize('Ligar para o Banco, até às 18h! due:2026-10-20')).toEqual(['ligar', 'banco', 'ate', '18h']);
  });

  it('matches the same item written a little differently', () => {
    expect(m('Call the bank', 'call bank')).toBe(true);
    expect(m('Renew passport at the consulate', 'renew passport consulate')).toBe(true);
    expect(m('Pagar aluguel', 'pagar o aluguel!')).toBe(true);
    expect(m('Gym', 'gym')).toBe(true);
  });

  it('stays quiet on weak overlaps', () => {
    expect(m('Call the bank', 'Call mom')).toBe(false);
    expect(m('Buy bread', 'Buy a new phone case')).toBe(false);
    expect(m('Gym', 'Gym with Ana on Friday')).toBe(false);
  });

  it('picks the closest candidate', () => {
    const c = [{ text: 'renew passport' }, { text: 'renew passport at the consulate' }, { text: 'call bank' }];
    expect(bestMatch('Renew passport at consulate', c)?.text).toBe('renew passport at the consulate');
    expect(bestMatch('Water the plants', c)).toBeNull();
  });
});
