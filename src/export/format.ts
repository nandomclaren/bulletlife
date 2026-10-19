// Export formats (CLAUDE.md 7, contract in docs/export-format.md). Pure and
// unit tested. Works on the line model, so collapsed children are always
// included: collapsing never changes what is exported.
import type { Line } from '../editor/lines';

export type Format = 'markdown' | 'rich' | 'plain';
export type GlyphStyle = 'checkboxes' | 'dots';

export interface ExportSection {
  /** Fixed layout label (a Month day, a Year month, "Month tasks"); absent for a plain page. */
  heading?: string;
  lines: Line[];
}

export interface ExportDoc {
  title: string;
  sections: ExportSection[];
}

const INDENT = '  ';

/** Signifiers written before the text: * priority, ! inspiration, 👁 explore. */
function signifiers(l: Line): string {
  const s = `${l.priority ? '*' : ''}${l.inspiration ? '!' : ''}${l.explore ? '👁' : ''}`;
  return s ? `${s} ` : '';
}

function markdownLine(l: Line, style: GlyphStyle, headingLevel: number): string {
  const pad = INDENT.repeat(l.indent);
  const text = signifiers(l) + l.text;
  if (l.type === 'heading') return `${'#'.repeat(headingLevel)} ${l.text}`;
  if (l.type === 'text') return `${pad}${l.text}`;
  if (l.type === 'note') return `${pad}- ${style === 'dots' ? '- ' : ''}${text}`;

  const event = l.type === 'event';
  if (style === 'dots') {
    const mark = { open: '', done: 'x ', migrated: '> ', scheduled: '< ', cancelled: '' }[l.state];
    const glyph = event ? 'o' : '.';
    if (l.state === 'cancelled') return `${pad}- ~~${glyph} ${text}~~`;
    return `${pad}- ${mark}${event && mark ? 'o ' : mark ? '' : `${glyph} `}${text}`;
  }
  if (l.state === 'cancelled') return `${pad}- ~~${event ? '○ ' : ''}${text}~~`;
  const box = { open: '[ ] ', done: '[x] ', migrated: '[>] ', scheduled: '[<] ', cancelled: '' }[l.state];
  if (event) return `${pad}- ${l.state === 'open' ? '' : box}○ ${text}`;
  return `${pad}- ${box}${text}`;
}

export function toMarkdown(doc: ExportDoc, style: GlyphStyle = 'checkboxes'): string {
  const out = doc.title ? [`# ${doc.title}`] : [];
  for (const s of doc.sections) {
    if (!s.lines.length) continue;
    if (out.length) out.push('');
    if (s.heading) out.push(`## ${s.heading}`, '');
    for (const l of s.lines) out.push(markdownLine(l, style, s.heading ? 3 : 2));
  }
  return out.join('\n') + '\n';
}

/** Combining long stroke: strikethrough that survives as plain text (Notes, Messages). */
const strike = (s: string) => [...s].map((c) => c + '̶').join('');

function plainLine(l: Line): string {
  const pad = INDENT.repeat(l.indent);
  if (l.type === 'heading') return l.text.toUpperCase();
  if (l.type === 'text') return `${pad}${l.text}`;
  const glyph =
    l.type === 'note' ? '–' : l.state === 'done' ? '×' : l.state === 'migrated' ? '>' : l.state === 'scheduled' ? '<' : l.type === 'event' ? '○' : '•';
  const text = signifiers(l) + l.text;
  return `${pad}${glyph} ${l.state === 'cancelled' && l.type !== 'note' ? strike(text) : text}`;
}

export function toPlain(doc: ExportDoc): string {
  const out = doc.title ? [doc.title] : [];
  for (const s of doc.sections) {
    if (!s.lines.length) continue;
    if (out.length) out.push('');
    if (s.heading) out.push(s.heading);
    out.push(...s.lines.map(plainLine));
  }
  return out.join('\n') + '\n';
}

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const COLORS = { task: '#E0533D', event: '#3B82C4', note: '#2A9D8F', muted: '#8A857C' };

/** Rich text for pasting into Notes, Mail, Docs: nested lists, colored bullets, struck-through cancellations. */
export function toHtml(doc: ExportDoc): string {
  const parts = doc.title ? [`<h1>${esc(doc.title)}</h1>`] : [];
  for (const s of doc.sections) {
    if (!s.lines.length) continue;
    if (s.heading) parts.push(`<h2>${esc(s.heading)}</h2>`);
    parts.push(listHtml(s.lines, !!s.heading));
  }
  return `<meta charset="utf-8">${parts.join('')}`;
}

function listHtml(lines: Line[], inSection: boolean): string {
  let html = '';
  let depth = -1;
  for (const l of lines) {
    if (l.type === 'heading') {
      html += '</li></ul>'.repeat(depth + 1);
      depth = -1;
      html += `<h${inSection ? 3 : 2}>${esc(l.text)}</h${inSection ? 3 : 2}>`;
      continue;
    }
    if (l.indent > depth) html += '<ul style="list-style:none;padding-left:1.2em;margin:0">'.repeat(l.indent - depth);
    else {
      html += '</li>';
      html += '</ul></li>'.repeat(depth - l.indent);
    }
    depth = l.indent;
    html += `<li>${itemHtml(l)}`;
  }
  html += '</li></ul>'.repeat(depth + 1);
  return html;
}

function itemHtml(l: Line): string {
  if (l.type === 'text') return esc(l.text);
  const color = l.type === 'note' ? COLORS.note : l.type === 'event' ? COLORS.event : COLORS.task;
  const glyph =
    l.type === 'note' ? '–' : l.state === 'done' ? '×' : l.state === 'migrated' ? '&gt;' : l.state === 'scheduled' ? '&lt;' : l.type === 'event' ? '○' : '•';
  const text = esc(signifiers(l) + l.text);
  const muted = l.type !== 'note' && l.state !== 'open';
  const body = l.state === 'cancelled' && l.type !== 'note' ? `<s>${text}</s>` : text;
  return `<span style="color:${color};font-weight:600">${glyph}</span> ${muted ? `<span style="color:${COLORS.muted}">${body}</span>` : body}`;
}

/** Selected lines as a title-less document, shifted so the shallowest line sits at level 0. */
export function selectionDoc(lines: Line[]): ExportDoc {
  const min = Math.min(...lines.map((l) => l.indent));
  return { title: '', sections: [{ lines: lines.map((l) => ({ ...l, indent: l.indent - min })) }] };
}
