import { describe, expect, it } from 'vitest';
import { inlineHtml, parseInline, stripInline } from './inline';

describe('inline formatting', () => {
  it('reads bold, italic, highlight and nesting', () => {
    expect(parseInline('a **b** c')).toEqual(['a ', { kind: 'b', mark: '**', children: ['b'] }, ' c']);
    expect(parseInline('pensar menos *==em==* mim')).toEqual([
      'pensar menos ',
      { kind: 'i', mark: '*', children: [{ kind: 'h', mark: '==', children: ['em'] }] },
      ' mim',
    ]);
    expect(parseInline('**antes mesmo de ter feito qualquer coisa.**')[0]).toMatchObject({ kind: 'b' });
  });

  it('leaves things that are not formatting alone', () => {
    expect(parseInline('2*3*4')).toEqual(['2*3*4']);
    expect(parseInline('a * b * c')).toEqual(['a * b * c']);
    expect(parseInline('** not bold **')).toEqual(['** not bold **']);
    expect(parseInline('unclosed **bold')).toEqual(['unclosed **bold']);
  });

  it('plain text drops the markers; rich text uses tags', () => {
    expect(stripInline('a **b** *c* ==d==')).toBe('a b c d');
    expect(inlineHtml('x **<y>** ==z==', (s) => s.replace(/</g, '&lt;').replace(/>/g, '&gt;'))).toBe('x <b>&lt;y&gt;</b> <mark>z</mark>');
  });
});
