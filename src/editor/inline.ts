// Inline formatting written as Markdown, the way notes apps do: **bold**,
// *italic*, ==highlight==. The text is stored exactly as typed; the editor
// shows the markers faintly and the content formatted. Pure and unit tested.

export type InlineKind = 'b' | 'i' | 'h';
export type Inline = string | { kind: InlineKind; mark: string; children: Inline[] };

const RULES: Array<{ kind: InlineKind; mark: string; re: RegExp }> = [
  { kind: 'b', mark: '**', re: /\*\*(?=\S)([\s\S]*?\S)\*\*/ },
  { kind: 'h', mark: '==', re: /==(?=\S)([\s\S]*?\S)==/ },
  // A lone "*" next to a word or another "*" is not italic (e.g. "2*3", "**").
  { kind: 'i', mark: '*', re: /(?<![*\p{L}\p{N}])\*(?=[^\s*])([\s\S]*?[^\s*])\*(?![*\p{L}\p{N}])/u },
];

export function parseInline(text: string): Inline[] {
  let best: { rule: (typeof RULES)[number]; m: RegExpMatchArray } | null = null;
  for (const rule of RULES) {
    const m = text.match(rule.re);
    if (m && m.index !== undefined && (!best || m.index < best.m.index!)) best = { rule, m };
  }
  if (!best) return text ? [text] : [];
  const at = best.m.index!;
  const out: Inline[] = [];
  if (at > 0) out.push(text.slice(0, at));
  out.push({ kind: best.rule.kind, mark: best.rule.mark, children: parseInline(best.m[1]) });
  out.push(...parseInline(text.slice(at + best.m[0].length)));
  return out;
}

/** The text without its markers (plain text export, comparisons). */
export function stripInline(text: string): string {
  const flat = (nodes: Inline[]): string => nodes.map((n) => (typeof n === 'string' ? n : flat(n.children))).join('');
  return flat(parseInline(text));
}

const TAGS: Record<InlineKind, string> = { b: 'b', i: 'i', h: 'mark' };

/** Rich text: <b>, <i>, <mark>, with the text escaped by `esc`. */
export function inlineHtml(text: string, esc: (s: string) => string): string {
  const html = (nodes: Inline[]): string =>
    nodes.map((n) => (typeof n === 'string' ? esc(n) : `<${TAGS[n.kind]}>${html(n.children)}</${TAGS[n.kind]}>`)).join('');
  return html(parseInline(text));
}
