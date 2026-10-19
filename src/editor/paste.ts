// Pasting entries back into a page. What the app copies (⌘C carries the exact
// lines; Copy As carries Markdown or plain text) is read back as entries with
// their type, state, signifiers and indentation, instead of literal glyphs.
// Pasting is the user's own gesture onto the page they are on, so it creates
// entries like typing would (CLAUDE.md 2).
import type { Line, LineState, LineType } from './lines';

/** Exact lines, set alongside text/plain and text/html when copying from an editor. */
export const LINES_MIME = 'application/x-bullet-life-lines';

type Pasted = Omit<Line, 'id'>;

const blank = (p: Partial<Pasted>): Pasted => ({
  type: 'text',
  state: 'open',
  indent: 0,
  collapsed: false,
  priority: false,
  inspiration: false,
  explore: false,
  text: '',
  ...p,
});

export function linesFromJson(json: string): Pasted[] | null {
  if (!json) return null;
  try {
    const raw = JSON.parse(json) as Partial<Line>[];
    if (!Array.isArray(raw) || !raw.length) return null;
    return raw.map((l) =>
      blank({
        type: l.type,
        state: l.state,
        indent: Math.max(0, Number(l.indent) || 0),
        priority: !!l.priority,
        inspiration: !!l.inspiration,
        explore: !!l.explore,
        text: String(l.text ?? ''),
      }),
    );
  } catch {
    return null;
  }
}

const STRIKE = /̶/g;

/** Leading signifiers as written by the exporter: "*", "!", "👁", then a space. */
function signifiers(s: string): { rest: string; priority: boolean; inspiration: boolean; explore: boolean } {
  const m = s.match(/^([*!]|👁)+ /u);
  const sig = m ? m[0] : '';
  return { rest: s.slice(sig.length), priority: sig.includes('*'), inspiration: sig.includes('!'), explore: sig.includes('👁') };
}

function item(type: LineType, state: LineState, indent: number, body: string): Pasted {
  const s = signifiers(body);
  return blank({ type, state, indent, text: s.rest, priority: s.priority, inspiration: s.inspiration, explore: s.explore });
}

const BOX: Record<string, LineState> = { ' ': 'open', x: 'done', X: 'done', '>': 'migrated', '<': 'scheduled' };
const DOT: Record<string, LineState> = { x: 'done', '>': 'migrated', '<': 'scheduled' };
const GLYPH: Record<string, [LineType, LineState]> = {
  '•': ['task', 'open'],
  '○': ['event', 'open'],
  '–': ['note', 'open'],
  '×': ['task', 'done'],
  '>': ['task', 'migrated'],
  '<': ['task', 'scheduled'],
};

/** One line of Markdown (checkboxes or dot notation) or of plain text with glyphs. */
function parseLine(raw: string, glyphs: boolean): { line: Pasted; known: boolean } {
  // Notes apps leave hidden markers; Bear marks a folded item with <!-- {"fold":true} -->.
  const folded = /<!--[^>]*"fold"\s*:\s*true[^>]*-->/.test(raw);
  const r = parseOne(raw.replace(/\s*<!--.*?-->/g, ''), glyphs);
  return folded ? { ...r, line: { ...r.line, collapsed: true } } : r;
}

function parseOne(raw: string, glyphs: boolean): { line: Pasted; known: boolean } {
  const lead = raw.match(/^[ \t]*/)![0];
  const indent = Math.floor(lead.replace(/\t/g, '  ').length / 2);
  let s = raw.slice(lead.length);

  const h = s.match(/^#{1,6} (.*)$/);
  if (h) return { line: blank({ type: 'heading', indent: 0, text: h[1] }), known: true };

  if (s.startsWith('- ')) {
    s = s.slice(2);
    // Cancelled: "~~text~~", "~~○ text~~", "~~. text~~", "~~o text~~"
    const c = s.match(/^~~(.*)~~$/);
    if (c) {
      const m = c[1].match(/^(○|o|\.) (.*)$/);
      const type = m && m[1] !== '.' ? 'event' : 'task';
      return { line: item(type, 'cancelled', indent, m ? m[2] : c[1]), known: true };
    }
    const box = s.match(/^\[([ xX<>])\] (.*)$/);
    if (box) {
      const ev = box[2].match(/^○ (.*)$/);
      return { line: item(ev ? 'event' : 'task', BOX[box[1]], indent, ev ? ev[1] : box[2]), known: true };
    }
    const ev = s.match(/^○ (.*)$/);
    if (ev) return { line: item('event', 'open', indent, ev[1]), known: true };
    // Dot notation: ". t", "x t", "x o t", "o t", "- note"
    const dot = s.match(/^([x<>]) (?:(o) )?(.*)$/);
    if (dot) return { line: item(dot[2] ? 'event' : 'task', DOT[dot[1]], indent, dot[3]), known: true };
    const d2 = s.match(/^(\.|o|-) (.*)$/);
    if (d2) return { line: item(d2[1] === '.' ? 'task' : d2[1] === 'o' ? 'event' : 'note', 'open', indent, d2[2]), known: true };
    return { line: item('note', 'open', indent, s), known: true };
  }

  // Arrows written as text: "-> item" migrated, "<- item" scheduled.
  const arrow = s.match(/^(->|→|<-|←) (.*)$/);
  if (arrow) return { line: item('task', arrow[1] === '->' || arrow[1] === '→' ? 'migrated' : 'scheduled', indent, arrow[2]), known: true };

  const g = s.match(/^([•○–×<>]) (.*)$/);
  if (g && (glyphs || !'<>'.includes(g[1]))) {
    const [type, state] = GLYPH[g[1]];
    const struck = g[2].includes('\u0336');
    return { line: item(type, struck && type !== 'note' ? 'cancelled' : state, indent, g[2].replace(STRIKE, '')), known: true };
  }
  return { line: blank({ indent, text: s }), known: false };
}

/**
 * Reads pasted text as entries when it looks like something the app exported.
 * Returns null for ordinary text, which keeps the plain paste.
 */
export function linesFromText(text: string): Pasted[] | null {
  const rows = text.replace(/\r\n?/g, '\n').replace(/\n+$/, '').split('\n');
  // ">" and "<" alone (email quotes) only count next to our other glyphs.
  const glyphs = rows.some((r) => /^[ \t]*[•○–×] /.test(r));
  const kept = rows.filter((r) => r.trim());
  // A pasted page starts with its title ("# Sunday, October 18"); the page here has its own.
  if (kept.length > 1 && /^# \S/.test(kept[0])) kept.shift();
  const parsed = kept.map((r) => parseLine(r, glyphs));
  if (!parsed.some((p) => p.known)) return null;
  // A heading starts a section: what follows is indented relative to the
  // section, not nested under the title (Markdown from notes apps indents
  // lists under "## Title" without meaning them as its children).
  const out: Pasted[] = [];
  let section: Pasted[] = [];
  const flush = () => {
    const min = Math.min(...section.map((l) => l.indent));
    out.push(...section.map((l) => ({ ...l, indent: l.indent - min })));
    section = [];
  };
  for (const { line } of parsed) {
    if (line.type === 'heading') {
      flush();
      out.push(line);
    } else section.push(line);
  }
  flush();
  return out;
}
