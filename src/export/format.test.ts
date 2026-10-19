import { describe, expect, it } from 'vitest';
import { newLine, type Line } from '../editor/lines';
import { toHtml, toMarkdown, toPlain, type ExportDoc } from './format';

const L = (p: Partial<Line>) => newLine(p);
const page = (lines: Line[]): ExportDoc => ({ title: 'Sun, Oct 18', sections: [{ lines }] });

const sample = [
  L({ type: 'task', text: 'Call the bank', priority: true, collapsed: true }),
  L({ type: 'note', text: 'closes at 6', indent: 1 }),
  L({ type: 'task', text: 'Buy bread', state: 'done' }),
  L({ type: 'task', text: 'Renew passport', state: 'migrated' }),
  L({ type: 'task', text: 'Dentist', state: 'scheduled' }),
  L({ type: 'task', text: 'Gym', state: 'cancelled' }),
  L({ type: 'event', text: 'Dinner with Ana' }),
  L({ type: 'event', text: 'Concert', state: 'done' }),
  L({ type: 'event', text: 'Trip', state: 'cancelled' }),
  L({ type: 'text', text: 'Quiet day.' }),
];

describe('Markdown (checkboxes)', () => {
  it('follows docs/export-format.md, including collapsed children', () => {
    expect(toMarkdown(page(sample))).toBe(
      [
        '# Sun, Oct 18',
        '',
        '- [ ] * Call the bank',
        '  - closes at 6',
        '- [x] Buy bread',
        '- [>] Renew passport',
        '- [<] Dentist',
        '- ~~Gym~~',
        '- ○ Dinner with Ana',
        '- [x] ○ Concert',
        '- ~~○ Trip~~',
        'Quiet day.',
        '',
      ].join('\n'),
    );
  });

  it('dot notation', () => {
    expect(toMarkdown(page(sample), 'dots').split('\n').slice(2, 11)).toEqual([
      '- . * Call the bank',
      '  - - closes at 6',
      '- x Buy bread',
      '- > Renew passport',
      '- < Dentist',
      '- ~~. Gym~~',
      '- o Dinner with Ana',
      '- x o Concert',
      '- ~~o Trip~~',
    ]);
  });

  it('sections get a heading and empty sections are skipped', () => {
    const doc: ExportDoc = {
      title: 'October 2026',
      sections: [
        { heading: '18 Sun', lines: [L({ type: 'text', text: 'Long walk' })] },
        { heading: '19 Mon', lines: [] },
        { heading: 'Month tasks', lines: [L({ type: 'task', text: 'Taxes' }), L({ type: 'heading', text: 'Work' })] },
      ],
    };
    expect(toMarkdown(doc)).toBe('# October 2026\n\n## 18 Sun\n\nLong walk\n\n## Month tasks\n\n- [ ] Taxes\n### Work\n');
  });
});

describe('plain text and rich text', () => {
  it('plain text uses the bullet glyphs and strikes cancelled items', () => {
    const lines = toPlain(page(sample)).split('\n');
    expect(lines.slice(1, 5)).toEqual(['', '• * Call the bank', '  – closes at 6', '× Buy bread']);
    expect(lines[7].startsWith('• G̶')).toBe(true);
  });

  it('rich text nests children and keeps them when collapsed', () => {
    const html = toHtml(page(sample.slice(0, 3)));
    expect(html).toContain('<h1>Sun, Oct 18</h1>');
    expect(html).toMatch(/Call the bank<ul[^>]*><li>.*closes at 6<\/li><\/ul><\/li><li>.*Buy bread/);
  });
});
