// Line markup shared by both editors, so they look and behave the same.
import { t } from '../i18n/en';
import { todayIso, type Weekday } from '../dates';
import { DUE_TOKEN, dueLabel, dueStatus, type DateOrder } from './due';
import { glyph, hasStates, numberPrefix, type Line, type LineType } from './lines';

/** How due dates are read and shown (Settings › Date format, First day of week); set by the app. */
export const dueView: { order: DateOrder; firstDay: Weekday } = { order: 'dmy', firstDay: 1 };

// Display always shows a saved state, also on events when "Event states" is
// off (CLAUDE.md 12: data is never hidden); only the interaction is gated.
const SHOW_STATES = true;

export interface LineView {
  color: LineType;
  hasChildren: boolean;
  hidden: boolean;
}

export function lineClass(line: Pick<Line, 'type' | 'state' | 'priority' | 'collapsed' | 'text'>, view: LineView) {
  const c = ['line', `t-${line.type}`, `c-${view.color}`];
  if (numberPrefix(line.text)) c.push('numbered');
  if (hasStates(line.type, SHOW_STATES)) c.push(`s-${line.state}`);
  if (line.priority) c.push('prio');
  if (view.hasChildren) c.push('has-children');
  if (view.hasChildren && line.collapsed) c.push('collapsed');
  if (view.hidden) c.push('is-hidden');
  return c.join(' ');
}

export function bulletLabel(line: Pick<Line, 'type' | 'state'>) {
  if (line.type === 'text' || line.type === 'heading') return '';
  const type = t.bullets[line.type];
  return hasStates(line.type, SHOW_STATES) ? `${type}, ${t.bullets.states[line.state]}` : type;
}

export function bulletGlyph(line: Pick<Line, 'type' | 'state'>) {
  return glyph(line.type, line.state, SHOW_STATES);
}

/** Builds the gutter (chevron, signifier, bullet). Text goes in the returned `.line-text`. */
export function buildGutter(doc: Document, line: Line, collapsed: boolean): HTMLElement {
  const gutter = doc.createElement('span');
  gutter.className = 'gutter';
  gutter.contentEditable = 'false';
  const chevron = doc.createElement('span');
  chevron.className = 'chevron';
  chevron.setAttribute('role', 'button');
  chevron.setAttribute('aria-label', collapsed ? t.editor.expand : t.editor.collapse);
  const sig = doc.createElement('span');
  sig.className = 'sig';
  if (line.priority) sig.append(mark(doc, 'sig-priority', '*'));
  if (line.inspiration) sig.append(mark(doc, 'sig-inspiration', '!'));
  if (line.explore) sig.append(eye(doc));
  const bullet = doc.createElement('span');
  bullet.className = 'bullet';
  const label = bulletLabel(line);
  if (label) {
    bullet.setAttribute('role', 'button');
    bullet.setAttribute('aria-label', label);
  }
  const g = bulletGlyph(line);
  // Dot, ring and cross are drawn in CSS (see editor.css) so they share one size and height.
  const drawn: Record<string, string> = { '•': 'dot', '○': 'ring', '×': 'cross' };
  if (drawn[g]) bullet.classList.add('drawn', drawn[g]);
  else bullet.textContent = g;
  gutter.append(chevron, sig, bullet);
  return gutter;
}

function mark(doc: Document, cls: string, text: string) {
  const m = doc.createElement('span');
  m.className = `sig-mark ${cls}`;
  m.textContent = text;
  return m;
}

/** Explore signifier: a small drawn eye (no emoji, same weight as the other marks). */
function eye(doc: Document) {
  const m = doc.createElement('span');
  m.className = 'sig-mark sig-explore';
  m.innerHTML =
    '<svg width="11" height="8" viewBox="0 0 22 16" fill="none" stroke="currentColor" stroke-width="2.4"><path d="M1.5 8C4 3.5 7.3 1.5 11 1.5S18 3.5 20.5 8C18 12.5 14.7 14.5 11 14.5S4 12.5 1.5 8Z"/><circle cx="11" cy="8" r="2.6" fill="currentColor" stroke="none"/></svg>';
  return m;
}

/**
 * Fills a line's text element: a leading list number gets its own span
 * (styled like a bullet) and each "due:YYYY-MM-DD" becomes a pill. The pill
 * keeps the stored text inside (so the line text reads back unchanged) and
 * shows its label instead; the user cannot edit inside it, only around it.
 */
export function fillText(el: HTMLElement, text: string) {
  const doc = el.ownerDocument;
  if (!text) return el.replaceChildren(doc.createElement('br'));
  const parts: Array<Node | string> = [];
  const num = numberPrefix(text);
  let rest = text;
  if (num) {
    const span = doc.createElement('span');
    span.className = 'num';
    span.textContent = num;
    parts.push(span);
    rest = text.slice(num.length);
  }
  let last = 0;
  for (const m of rest.matchAll(DUE_TOKEN)) {
    if (m.index > last) parts.push(rest.slice(last, m.index));
    parts.push(pill(doc, m[0], m[1]));
    last = m.index + m[0].length;
  }
  if (last < rest.length) parts.push(rest.slice(last));
  el.replaceChildren(...parts);
}

function pill(doc: Document, raw: string, iso: string) {
  const today = todayIso();
  const label = dueLabel(iso, today, dueView.order);
  const span = doc.createElement('span');
  span.className = `due due-${dueStatus(iso, today)}`;
  span.contentEditable = 'false';
  span.dataset.iso = iso;
  span.dataset.label = label;
  span.setAttribute('role', 'button');
  span.setAttribute('aria-label', t.due.label(label));
  span.textContent = raw;
  return span;
}

/** Whether the text element's DOM already matches how fillText would build it. */
export function textShapeMatches(el: Element, text: string) {
  const num = numberPrefix(text);
  const span = el.querySelector('.num');
  if (num ? !span || el.firstChild !== span || span.textContent !== num : span) return false;
  const pills = [...el.querySelectorAll<HTMLElement>('.due')];
  const tokens = [...text.matchAll(DUE_TOKEN)];
  if (pills.length !== tokens.length) return false;
  const today = todayIso();
  return tokens.every((m, i) => pills[i].textContent === m[0] && pills[i].dataset.label === dueLabel(m[1], today, dueView.order));
}
