// Line markup shared by both editors, so they look and behave the same.
import { t } from '../i18n/en';
import { glyph, hasStates, type Line, type LineType } from './lines';

export const EVENT_STATES = true; // Settings toggle arrives later in Phase 1.

export interface LineView {
  color: LineType;
  hasChildren: boolean;
  hidden: boolean;
}

export function lineClass(line: Pick<Line, 'type' | 'state' | 'priority' | 'collapsed'>, view: LineView) {
  const c = ['line', `t-${line.type}`, `c-${view.color}`];
  if (hasStates(line.type, EVENT_STATES)) c.push(`s-${line.state}`);
  if (line.priority) c.push('prio');
  if (view.hasChildren) c.push('has-children');
  if (view.hasChildren && line.collapsed) c.push('collapsed');
  if (view.hidden) c.push('is-hidden');
  return c.join(' ');
}

export function bulletLabel(line: Pick<Line, 'type' | 'state'>) {
  if (line.type === 'text' || line.type === 'heading') return '';
  const type = t.bullets[line.type];
  return hasStates(line.type, EVENT_STATES) ? `${type}, ${t.bullets.states[line.state]}` : type;
}

export function bulletGlyph(line: Pick<Line, 'type' | 'state'>) {
  return glyph(line.type, line.state, EVENT_STATES);
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
  sig.textContent = line.priority ? '*' : '';
  const bullet = doc.createElement('span');
  bullet.className = 'bullet';
  const label = bulletLabel(line);
  if (label) {
    bullet.setAttribute('role', 'button');
    bullet.setAttribute('aria-label', label);
  }
  const g = bulletGlyph(line);
  // Open/cancelled task and event bullets are drawn in CSS (see editor.css).
  if (g === '•' || g === '○') bullet.classList.add('drawn', g === '•' ? 'dot' : 'ring');
  else bullet.textContent = g;
  gutter.append(chevron, sig, bullet);
  return gutter;
}
