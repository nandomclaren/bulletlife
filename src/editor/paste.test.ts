import { describe, expect, it } from 'vitest';
import { toMarkdown, toPlain, type ExportDoc } from '../export/format';
import { newLine, type Line } from './lines';
import { linesFromJson, linesFromText } from './paste';

const L = (p: Partial<Line>) => newLine(p);
const sample = [
  L({ type: 'task', text: 'Call the bank', priority: true }),
  L({ type: 'note', text: 'closes at 6', indent: 1 }),
  L({ type: 'task', text: 'Buy bread', state: 'done' }),
  L({ type: 'task', text: 'Renew passport', state: 'migrated' }),
  L({ type: 'task', text: 'Gym', state: 'cancelled', inspiration: true }),
  L({ type: 'event', text: 'Dinner with Ana' }),
  L({ type: 'event', text: 'Concert', state: 'done' }),
  L({ type: 'event', text: 'Trip', state: 'cancelled' }),
];
const doc: ExportDoc = { title: '', sections: [{ lines: sample }] };
const shape = (ls: Omit<Line, 'id'>[]) => ls.map((l) => [l.type, l.state, l.indent, l.text, !!l.priority, !!l.inspiration]);

describe('paste', () => {
  it('Markdown with checkboxes round-trips', () => {
    expect(shape(linesFromText(toMarkdown(doc))!)).toEqual(shape(sample));
  });

  it('Markdown in dot notation round-trips', () => {
    expect(shape(linesFromText(toMarkdown(doc, 'dots'))!)).toEqual(shape(sample));
  });

  it('plain text keeps type, state and indentation (done events read as tasks)', () => {
    const got = shape(linesFromText(toPlain(doc))!);
    expect(got[0]).toEqual(['task', 'open', 0, 'Call the bank', true, false]);
    expect(got[1]).toEqual(['note', 'open', 1, 'closes at 6', false, false]);
    expect(got[4]).toEqual(['task', 'cancelled', 0, 'Gym', false, true]);
    expect(got[5]).toEqual(['event', 'open', 0, 'Dinner with Ana', false, false]);
  });

  it('exact lines from the editor, with fresh ids left to the caller', () => {
    const got = linesFromJson(JSON.stringify(sample))!;
    expect(shape(got)).toEqual(shape(sample));
    expect(got[0]).not.toHaveProperty('id');
  });

  it('Markdown from a notes app: sections, folded items, arrows, hidden markers', () => {
    const bear = [
      '# Sunday, October 18, 2026',
      '',
      '## Âncoras',
      '  - [x] Devocional',
      '  - [x] Exercício ',
      '    - 15m Flow',
      '## Priorities',
      '  - [x] Hillsong<!-- {"fold":true} -->',
      '    - A note under it',
      '## Buffer',
      '  -> Weekly Review',
      '## Blurb',
      '  A paragraph of free text.',
    ].join('\n');
    const got = linesFromText(bear)!.map((l) => [l.type, l.state, l.indent, l.text.trim(), l.collapsed]);
    expect(got).toEqual([
      ['heading', 'open', 0, 'Âncoras', false],
      ['task', 'done', 0, 'Devocional', false],
      ['task', 'done', 0, 'Exercício', false],
      ['note', 'open', 1, '15m Flow', false],
      ['heading', 'open', 0, 'Priorities', false],
      ['task', 'done', 0, 'Hillsong', true],
      ['note', 'open', 1, 'A note under it', false],
      ['heading', 'open', 0, 'Buffer', false],
      ['task', 'migrated', 0, 'Weekly Review', false],
      ['heading', 'open', 0, 'Blurb', false],
      ['text', 'open', 0, 'A paragraph of free text.', false],
    ]);
  });

  it('ordinary text stays ordinary', () => {
    expect(linesFromText('Dear Ana,\nsee you soon')).toBeNull();
    expect(linesFromText('> quoted\n> reply')).toBeNull();
  });
});
