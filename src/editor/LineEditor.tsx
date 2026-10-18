// Prototype B: our own editor. One contentEditable root, one div per line.
// The browser edits text inside a line; anything that changes line structure
// (Enter, Backspace at a line start, multi-line deletes, paste, undo) is
// intercepted in `beforeinput` and applied to the model, then re-rendered.
import { useEffect, useRef, type MutableRefObject } from 'react';
import { attachGutter } from './gutter';
import {
  colorTypes,
  continuationType,
  hasChildren,
  hasStates,
  hiddenMask,
  matchPrefix,
  newLine,
  nextState,
  shiftIndent,
  type Line,
} from './lines';
import { buildGutter, EVENT_STATES, lineClass } from './render';

interface Caret {
  index: number;
  offset: number;
}

interface Snapshot {
  lines: Line[];
  caret: Caret;
}

class LineEditorCore {
  private lines: Line[];
  private undoStack: Snapshot[] = [];
  private redoStack: Snapshot[] = [];
  private lastTyping = 0;
  private composing = false;
  private detachGutter: () => void;

  constructor(
    private root: HTMLElement,
    initial: Line[],
    private onChange: (lines: Line[]) => void,
    className = '',
  ) {
    this.lines = initial.length ? initial.map((l) => ({ ...l })) : [newLine()];
    root.contentEditable = 'true';
    root.className = `editor ${className}`.trim();
    root.spellcheck = true;
    root.setAttribute('autocapitalize', 'sentences');
    root.setAttribute('role', 'textbox');
    root.setAttribute('aria-multiline', 'true');
    root.addEventListener('beforeinput', this.onBeforeInput);
    root.addEventListener('input', this.onInput);
    root.addEventListener('keydown', this.onKeyDown);
    root.addEventListener('compositionstart', this.onCompStart);
    root.addEventListener('compositionend', this.onCompEnd);
    this.detachGutter = attachGutter(root, {
      bullet: (id) => this.updateById(id, (l) => (hasStates(l.type, EVENT_STATES) ? { ...l, state: nextState(l.state) } : null)),
      chevron: (id) => this.updateById(id, (l) => ({ ...l, collapsed: !l.collapsed })),
    });
    this.renderAll();
  }

  destroy() {
    this.root.removeEventListener('beforeinput', this.onBeforeInput);
    this.root.removeEventListener('input', this.onInput);
    this.root.removeEventListener('keydown', this.onKeyDown);
    this.root.removeEventListener('compositionstart', this.onCompStart);
    this.root.removeEventListener('compositionend', this.onCompEnd);
    this.detachGutter();
  }

  // ---------- rendering ----------

  private renderLine(line: Line, collapsed: boolean): HTMLElement {
    const el = document.createElement('div');
    el.dataset.id = line.id;
    el.style.setProperty('--indent', String(line.indent));
    const text = document.createElement('div');
    text.className = 'line-text';
    if (line.text) text.textContent = line.text;
    else text.append(document.createElement('br'));
    el.append(buildGutter(document, line, collapsed), text);
    return el;
  }

  private renderAll() {
    this.root.replaceChildren(...this.lines.map((l) => this.renderLine(l, l.collapsed)));
    this.refreshDecor();
  }

  /** Re-applies derived classes and gutters without touching line text. */
  private refreshDecor() {
    const colors = colorTypes(this.lines);
    const hidden = hiddenMask(this.lines);
    const els = this.root.children;
    this.lines.forEach((l, i) => {
      const el = els[i] as HTMLElement;
      el.className = lineClass(l, { color: colors[i], hasChildren: hasChildren(this.lines, i), hidden: hidden[i] });
      el.style.setProperty('--indent', String(l.indent));
      const gutter = el.querySelector(':scope > .gutter');
      gutter?.replaceWith(buildGutter(document, l, l.collapsed));
    });
  }

  private emit() {
    this.onChange(this.lines.map((l) => ({ ...l })));
  }

  // ---------- caret ----------

  private lineIndexOf(node: Node | null): number {
    const el = (node instanceof Element ? node : node?.parentElement)?.closest('.line');
    return el ? Array.prototype.indexOf.call(this.root.children, el) : -1;
  }

  private offsetIn(index: number, node: Node, offset: number): number {
    const text = this.root.children[index]?.querySelector('.line-text');
    if (!text || !text.contains(node)) return node === this.root.children[index] && offset > 0 ? this.lines[index].text.length : 0;
    const r = document.createRange();
    r.selectNodeContents(text);
    r.setEnd(node, offset);
    return r.toString().length;
  }

  private readSelection(): { start: Caret; end: Caret } | null {
    const sel = document.getSelection();
    if (!sel || sel.rangeCount === 0) return null;
    const r = sel.getRangeAt(0);
    const si = this.lineIndexOf(r.startContainer);
    const ei = this.lineIndexOf(r.endContainer);
    if (si < 0 || ei < 0) return null;
    return {
      start: { index: si, offset: this.offsetIn(si, r.startContainer, r.startOffset) },
      end: { index: ei, offset: this.offsetIn(ei, r.endContainer, r.endOffset) },
    };
  }

  private placeCaret({ index, offset }: Caret) {
    const text = this.root.children[index]?.querySelector('.line-text');
    if (!text) return;
    const sel = document.getSelection();
    const r = document.createRange();
    const walker = document.createTreeWalker(text, NodeFilter.SHOW_TEXT);
    let remaining = offset;
    let node = walker.nextNode();
    while (node) {
      const len = node.textContent?.length ?? 0;
      if (remaining <= len) {
        r.setStart(node, remaining);
        break;
      }
      remaining -= len;
      node = walker.nextNode();
    }
    if (!node) r.setStart(text, text.childNodes.length && text.lastChild?.nodeName === 'BR' ? 0 : text.childNodes.length);
    r.collapse(true);
    sel?.removeAllRanges();
    sel?.addRange(r);
  }

  // ---------- history ----------

  private snapshot(caret: Caret, coalesce = false) {
    const now = Date.now();
    if (coalesce && now - this.lastTyping < 800) return;
    this.lastTyping = coalesce ? now : 0;
    this.undoStack.push({ lines: this.lines.map((l) => ({ ...l })), caret });
    if (this.undoStack.length > 200) this.undoStack.shift();
    this.redoStack = [];
  }

  private restore(from: Snapshot[], to: Snapshot[]) {
    const snap = from.pop();
    if (!snap) return;
    const sel = this.readSelection();
    to.push({ lines: this.lines.map((l) => ({ ...l })), caret: sel?.start ?? { index: 0, offset: 0 } });
    this.lines = snap.lines;
    this.lastTyping = 0;
    this.renderAll();
    this.placeCaret(snap.caret);
    this.emit();
  }

  // ---------- structural edits ----------

  private commit(caret: Caret) {
    this.renderAll();
    this.placeCaret(caret);
    this.emit();
  }

  private deleteRange(start: Caret, end: Caret): Caret {
    const a = this.lines[start.index];
    const b = this.lines[end.index];
    a.text = a.text.slice(0, start.offset) + b.text.slice(end.offset);
    this.lines.splice(start.index + 1, end.index - start.index);
    return start;
  }

  private insertText(at: Caret, text: string): Caret {
    const parts = text.replace(/\r\n?/g, '\n').split('\n');
    const line = this.lines[at.index];
    const tail = line.text.slice(at.offset);
    line.text = line.text.slice(0, at.offset) + parts[0];
    let caret: Caret = { index: at.index, offset: line.text.length };
    for (const part of parts.slice(1)) {
      const fresh = newLine({ type: continuationType(line.type), indent: line.indent, text: part });
      this.lines.splice(caret.index + 1, 0, fresh);
      caret = { index: caret.index + 1, offset: part.length };
    }
    this.lines[caret.index].text += tail;
    return caret;
  }

  private enter(at: Caret) {
    const line = this.lines[at.index];
    if (!line.text && line.type !== 'text') {
      if (line.indent > 0) this.shiftLines(at.index, at.index, -1, false);
      else Object.assign(line, { type: 'text', state: 'open', priority: false });
      return this.commit(at);
    }
    const fresh = newLine({ type: continuationType(line.type), indent: line.indent });
    if (at.offset === 0 && line.text) {
      this.lines.splice(at.index, 0, fresh);
      return this.commit({ index: at.index + 1, offset: 0 });
    }
    fresh.text = line.text.slice(at.offset);
    line.text = line.text.slice(0, at.offset);
    line.collapsed = false;
    this.lines.splice(at.index + 1, 0, fresh);
    this.commit({ index: at.index + 1, offset: 0 });
  }

  /** Backspace at a line start: outdent first, then drop the bullet, then join lines. */
  private backspaceAtStart(at: Caret) {
    const line = this.lines[at.index];
    if (line.indent > 0) {
      this.shiftLines(at.index, at.index, -1, false);
      return this.commit(at);
    }
    if (line.type !== 'text') {
      Object.assign(line, { type: 'text', state: 'open', priority: false });
      return this.commit(at);
    }
    if (at.index === 0) return;
    const prev = this.lines[at.index - 1];
    const offset = prev.text.length;
    this.deleteRange({ index: at.index - 1, offset }, { index: at.index, offset: 0 });
    this.commit({ index: at.index - 1, offset });
  }

  private shiftLines(from: number, to: number, delta: 1 | -1, render = true) {
    const indents = shiftIndent(this.lines, from, to, delta);
    if (!indents) return;
    this.lines.forEach((l, i) => (l.indent = indents[i]));
    if (render) {
      this.refreshDecor();
      this.emit();
    }
  }

  private updateById(id: string, fn: (l: Line) => Line | null) {
    const i = this.lines.findIndex((l) => l.id === id);
    if (i < 0) return;
    const next = fn(this.lines[i]);
    if (!next) return;
    this.snapshot(this.readSelection()?.start ?? { index: i, offset: 0 });
    this.lines[i] = next;
    this.refreshDecor();
    this.emit();
  }

  // ---------- events ----------

  private onBeforeInput = (e: InputEvent) => {
    if (this.composing) return;
    const sel = this.readSelection();
    if (!sel) return;
    const { start, end } = sel;
    const multi = start.index !== end.index;
    const collapsed = !multi && start.offset === end.offset;

    switch (e.inputType) {
      case 'insertParagraph':
      case 'insertLineBreak': {
        e.preventDefault();
        this.snapshot(start);
        const at = collapsed ? start : this.deleteRange(start, end);
        return this.enter(at);
      }
      case 'deleteContentBackward':
      case 'deleteWordBackward':
      case 'deleteSoftLineBackward':
      case 'deleteHardLineBackward':
        if (multi) break;
        if (collapsed && start.offset === 0) {
          e.preventDefault();
          this.snapshot(start);
          return this.backspaceAtStart(start);
        }
        this.snapshot(start, true);
        return;
      case 'deleteContentForward':
      case 'deleteWordForward':
        if (multi) break;
        if (collapsed && start.offset === this.lines[start.index].text.length && start.index + 1 < this.lines.length) {
          e.preventDefault();
          this.snapshot(start);
          this.deleteRange(start, { index: start.index + 1, offset: 0 });
          return this.commit(start);
        }
        this.snapshot(start, true);
        return;
      case 'insertFromPaste':
      case 'insertFromDrop':
      case 'insertReplacementText': {
        const text = e.dataTransfer?.getData('text/plain') ?? e.data ?? '';
        if (!multi && !text.includes('\n')) {
          this.snapshot(start);
          return; // single-line: let the browser do it
        }
        e.preventDefault();
        this.snapshot(start);
        return this.commit(this.insertText(this.deleteRange(start, end), text));
      }
      case 'historyUndo':
        e.preventDefault();
        return this.restore(this.undoStack, this.redoStack);
      case 'historyRedo':
        e.preventDefault();
        return this.restore(this.redoStack, this.undoStack);
      case 'insertText':
        // A space at the very start of a line indents it (the iPhone keyboard has no Tab).
        if (collapsed && start.offset === 0 && e.data === ' ' && shiftIndent(this.lines, start.index, start.index, 1)) {
          e.preventDefault();
          this.snapshot(start);
          this.shiftLines(start.index, start.index, 1);
          return;
        }
        if (!multi) {
          this.snapshot(start, true);
          return;
        }
        break;
      default:
        if (!multi) {
          this.snapshot(start, true);
          return;
        }
    }

    // Anything else spanning several lines: do it on the model.
    e.preventDefault();
    this.snapshot(start);
    let at = this.deleteRange(start, end);
    if (e.inputType.startsWith('insert') && e.data) at = this.insertText(at, e.data);
    this.commit(at);
  };

  private onInput = () => {
    if (this.composing) return;
    const sel = this.readSelection();
    if (!sel) return;
    const i = sel.start.index;
    const el = this.root.children[i];
    const text = (el?.querySelector('.line-text')?.textContent ?? '').replace(/ /g, ' ');
    const line = this.lines[i];
    line.text = text;

    // Rapid logging prefix typed at the start of the line.
    const m = sel.start.offset <= 5 ? matchPrefix(text.slice(0, sel.start.offset)) : null;
    if (m && m.length === sel.start.offset) {
      line.text = text.slice(m.length);
      if (m.type !== 'text') Object.assign(line, { type: m.type, state: 'open' });
      line.priority = m.priority || line.priority;
      return this.commit({ index: i, offset: 0 });
    }
    // An emptied line can lose its <br>; keep it so the line keeps its height.
    const textEl = el?.querySelector('.line-text');
    if (textEl && !text && !textEl.querySelector('br')) textEl.append(document.createElement('br'));
    this.emit();
  };

  private onKeyDown = (e: KeyboardEvent) => {
    const sel = this.readSelection();
    if (!sel) return;
    if (e.code === 'Tab') {
      e.preventDefault();
      this.snapshot(sel.start);
      this.shiftLines(sel.start.index, sel.end.index, e.shiftKey ? -1 : 1);
    } else if (e.code === 'Enter' && (e.metaKey || e.ctrlKey)) {
      e.preventDefault();
      const l = this.lines[sel.start.index];
      if (hasStates(l.type, EVENT_STATES)) this.updateById(l.id, (x) => ({ ...x, state: nextState(x.state) }));
    } else if (e.code === 'KeyZ' && (e.metaKey || e.ctrlKey)) {
      // Safari does not always send historyUndo for our custom edits.
      e.preventDefault();
      if (e.shiftKey) this.restore(this.redoStack, this.undoStack);
      else this.restore(this.undoStack, this.redoStack);
    }
  };

  private onCompStart = () => {
    this.composing = true;
  };
  private onCompEnd = () => {
    this.composing = false;
    this.onInput();
  };

  /** Caret at the end of a line, or of the last visible line (the first line of an empty page). */
  focusEnd(lineId?: string) {
    this.root.focus();
    const hidden = hiddenMask(this.lines);
    let index = lineId ? this.lines.findIndex((l) => l.id === lineId) : -1;
    if (index < 0 || hidden[index]) {
      index = this.lines.length - 1;
      while (index > 0 && hidden[index]) index--;
    }
    this.placeCaret({ index, offset: this.lines[index].text.length });
  }
}

interface Props {
  initial: Line[];
  onChange: (lines: Line[]) => void;
  autoFocus?: boolean;
  className?: string;
  label?: string;
  /** Receives a function that places the caret at the end of a line (or of the page), for taps on empty space. */
  focusRef?: MutableRefObject<((lineId?: string) => void) | null>;
}

export function LineEditor({ initial, onChange, autoFocus, className, label, focusRef }: Props) {
  const host = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const core = new LineEditorCore(host.current!, initial, onChange, className);
    if (label) host.current!.setAttribute('aria-label', label);
    if (focusRef) focusRef.current = (lineId) => core.focusEnd(lineId);
    if (autoFocus) core.focusEnd();
    return () => {
      if (focusRef) focusRef.current = null;
      core.destroy();
    };
    // The editor owns its state after mount.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  return <div ref={host} />;
}
