// Prototype B: our own editor. One contentEditable root, one div per line.
// The browser edits text inside a line; anything that changes line structure
// (Enter, Backspace at a line start, multi-line deletes, paste, undo) is
// intercepted in `beforeinput` and applied to the model, then re-rendered.
import { useCallback, useEffect, useMemo, useRef, useState, type MutableRefObject } from 'react';
import { BulletMenu, UndoToast, type MenuActions } from './BulletMenu';
import { selectionDoc, toHtml, toPlain } from '../export/format';
import { setSelection } from '../export/selection';
import { attachGutter } from './gutter';
import { attachSwipe } from './swipe';
import type { Mark } from '../data/openItems';
import { MarkToast } from '../open/MarkToast';
import { LINES_MIME, linesFromJson, linesFromText } from './paste';
import {
  colorTypes,
  continuationType,
  hasChildren,
  hasStates,
  hiddenMask,
  matchPrefix,
  newLine,
  nextNumber,
  NO_SIGNIFIERS,
  numberPrefix,
  listRestarts,
  renumberLists,
  restartIfFirst,
  nextState,
  shiftIndent,
  subtreeEnd,
  type Line,
} from './lines';
import { buildGutter, dueView, fillText, lineClass, textShapeMatches } from './render';
import { DUE_TOKEN, dateRuns, resolveDue, sortRun } from './due';
import { todayIso } from '../dates';
import { t } from '../i18n/en';

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
  private detachSwipe: () => void;
  /** Settings › Event states: whether event bullets cycle through states. */
  eventStates = true;
  /** Settings › Reverse swipe directions. */
  reverseSwipes = false;
  /** A task or event line was finished (Enter or leaving the editor): a chance to suggest a link (Phase 4b). */
  onLineDone: ((line: Line) => void) | null = null;
  /** The user answered a link suggestion. */
  onLinkAnswer: ((lineId: string, sourceId: string, link: boolean) => void) | null = null;
  private suggestions = new Map<string, { sourceId: string; text: string }>();
  /** A line was marked > or < (or the mark was taken back: null). */
  onMark: ((mark: Mark | null) => void) | null = null;
  /** Opens the bullet menu (set by the React wrapper). */
  onMenu: ((lineId: string, anchor: DOMRect) => void) | null = null;

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
    document.addEventListener('selectionchange', this.onSelectionChange);
    root.addEventListener('copy', this.onCopy);
    root.addEventListener('cut', this.onCopy);
    root.addEventListener('paste', this.onPaste);
    root.addEventListener('focusout', this.onBlur);
    root.addEventListener('click', this.onDecorClick);
    root.addEventListener('mousedown', this.onDecorDown);
    this.detachGutter = attachGutter(root, {
      bullet: (id) => this.updateById(id, (l) => (hasStates(l.type, this.eventStates) ? { ...l, state: nextState(l.state) } : null)),
      chevron: (id) => this.updateById(id, (l) => ({ ...l, collapsed: !l.collapsed })),
      menu: (id, anchor) => this.onMenu?.(id, anchor),
    });
    this.detachSwipe = attachSwipe(root, {
      canSwipe: (id) => {
        const l = this.lineById(id);
        return !!l && hasStates(l.type, this.eventStates);
      },
      current: (id) => this.lineById(id)?.state,
      commit: (id, mark) => this.markLine(id, mark),
      reverse: () => this.reverseSwipes,
    });
    this.renderAll();
  }

  destroy() {
    this.root.removeEventListener('beforeinput', this.onBeforeInput);
    this.root.removeEventListener('input', this.onInput);
    this.root.removeEventListener('keydown', this.onKeyDown);
    this.root.removeEventListener('compositionstart', this.onCompStart);
    this.root.removeEventListener('compositionend', this.onCompEnd);
    document.removeEventListener('selectionchange', this.onSelectionChange);
    this.root.removeEventListener('copy', this.onCopy);
    this.root.removeEventListener('cut', this.onCopy);
    this.root.removeEventListener('paste', this.onPaste);
    this.root.removeEventListener('focusout', this.onBlur);
    this.root.removeEventListener('click', this.onDecorClick);
    this.root.removeEventListener('mousedown', this.onDecorDown);
    this.detachGutter();
    this.detachSwipe();
  }

  // ---------- rendering ----------

  private renderLine(line: Line, collapsed: boolean): HTMLElement {
    const el = document.createElement('div');
    el.dataset.id = line.id;
    el.style.setProperty('--indent', String(line.indent));
    const text = document.createElement('div');
    text.className = 'line-text';
    fillText(text, line.text);
    el.append(buildGutter(document, line, collapsed), text);
    const s = this.suggestions.get(line.id);
    if (s) el.append(linkChip(s.text));
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
      el.className = lineClass(l, {
        color: colors[i],
        hasChildren: hasChildren(this.lines, i),
        hidden: hidden[i],
      });
      el.style.setProperty('--indent', String(l.indent));
      const gutter = el.querySelector(':scope > .gutter');
      gutter?.replaceWith(buildGutter(document, l, l.collapsed));
      el.querySelector(':scope > .sort-btn')?.remove();
    });
    // A list with due dates that is out of order offers to sort itself; it never does so on its own.
    for (const run of dateRuns(this.lines)) {
      if (run.sorted) continue;
      const el = els[run.items[0]] as HTMLElement;
      el.classList.add('has-sort');
      el.append(sortButton());
    }
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
      start: {
        index: si,
        offset: this.offsetIn(si, r.startContainer, r.startOffset),
      },
      end: {
        index: ei,
        offset: this.offsetIn(ei, r.endContainer, r.endOffset),
      },
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
        // Never inside a date pill: before it, or after it.
        const pill = node.parentElement?.closest('.due');
        if (pill && remaining === 0) r.setStartBefore(pill);
        else if (pill) r.setStartAfter(pill);
        else r.setStart(node, remaining);
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
    to.push({
      lines: this.lines.map((l) => ({ ...l })),
      caret: sel?.start ?? { index: 0, offset: 0 },
    });
    this.lines = snap.lines;
    this.lastTyping = 0;
    this.renderAll();
    this.placeCaret(snap.caret);
    this.emit();
  }

  // ---------- structural edits ----------

  /** Renumbers lists, keeping the numbers the user chose before this edit. */
  private renumber(): number[] {
    const before = this.undoStack[this.undoStack.length - 1]?.lines ?? this.lines;
    return renumberLists(this.lines, listRestarts(before));
  }

  private commit(caret: Caret) {
    this.renumber();
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
      const fresh = newLine({
        type: continuationType(line.type),
        indent: line.indent,
        text: part,
      });
      this.lines.splice(caret.index + 1, 0, fresh);
      caret = { index: caret.index + 1, offset: part.length };
    }
    this.lines[caret.index].text += tail;
    return caret;
  }

  private enter(at: Caret) {
    // A due date finished by Enter becomes a pill too.
    const resolved = this.resolveDueAt(at.index, at.offset);
    if (resolved !== null) at = { index: at.index, offset: resolved };
    this.lineDone(this.lines[at.index]);
    const i = at.index;
    const line = this.lines[i];
    if (!line.text && line.type !== 'text') {
      if (line.indent > 0) this.shiftLines(i, i, -1, false);
      else Object.assign(line, { type: 'text', state: 'open', ...NO_SIGNIFIERS });
      return this.commit(at);
    }
    const num = numberPrefix(line.text);
    // Enter on an empty list item ("3. " alone) ends the list.
    if (num && line.text.trim() === num) {
      line.text = '';
      return this.commit({ index: i, offset: 0 });
    }
    if (at.offset === 0 && line.text) {
      this.lines.splice(i, 0, newLine({ type: continuationType(line.type), indent: line.indent }));
      return this.commit({ index: i + 1, offset: 0 });
    }
    const kids = hasChildren(this.lines, i);
    // A collapsed item stays closed: the new line goes after everything hidden
    // inside it, as its next sibling. An open item gets a new first child.
    const asChild = kids && !line.collapsed;
    const at2 = asChild ? i + 1 : kids ? subtreeEnd(this.lines, i) : i + 1;
    const fresh = asChild
      ? newLine({
          type: this.lines[i + 1].type === 'heading' ? 'text' : this.lines[i + 1].type,
          indent: line.indent + 1,
        })
      : newLine({ type: continuationType(line.type), indent: line.indent });
    // Next list number for a sibling ("2. …" → "3. ").
    const prefix = num && !asChild ? `${nextNumber(num)} ` : '';
    fresh.text = prefix + line.text.slice(at.offset);
    line.text = line.text.slice(0, at.offset);
    this.lines.splice(at2, 0, fresh);
    this.commit({ index: at2, offset: prefix.length });
  }

  /** Backspace at a line start: drop a stray priority mark, outdent, drop the bullet, then join lines. */
  private backspaceAtStart(at: Caret) {
    const line = this.lines[at.index];
    // A plain line can still carry a priority mark (older data); it must always be removable.
    if ((line.type === 'text' || line.type === 'heading') && line.priority) {
      line.priority = false;
      return this.commit(at);
    }
    if (line.indent > 0) {
      this.shiftLines(at.index, at.index, -1, false);
      return this.commit(at);
    }
    if (line.type !== 'text') {
      Object.assign(line, { type: 'text', state: 'open', ...NO_SIGNIFIERS });
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
    const textBefore = this.lines[from].text;
    this.lines.forEach((l, i) => (l.indent = indents[i]));
    restartIfFirst(this.lines, from);
    if (render) {
      // Moving an item in or out of a list renumbers both lists.
      if (this.renumber().length || this.lines[from].text !== textBefore) {
        const caret = this.readSelection()?.start;
        this.renderAll();
        if (caret) this.placeCaret(caret);
      } else this.refreshDecor();
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

  // ---------- bullet menu actions (one entry at a time) ----------

  lineById(id: string): Line | undefined {
    return this.lines.find((l) => l.id === id);
  }

  patchLine(id: string, patch: Partial<Line>) {
    this.updateById(id, (l) => ({ ...l, ...patch }));
  }

  /** Marks one line > or <; marking it again takes it back to open. */
  markLine(id: string, mark: Mark) {
    const l = this.lineById(id);
    if (!l || !hasStates(l.type, this.eventStates)) return;
    const next = l.state === mark ? 'open' : mark;
    this.patchLine(id, { state: next });
    this.onMark?.(next === 'open' ? null : mark);
  }

  shiftLine(id: string, delta: 1 | -1) {
    const i = this.lines.findIndex((l) => l.id === id);
    if (i < 0 || !shiftIndent(this.lines, i, i, delta)) return;
    this.snapshot({ index: i, offset: 0 });
    this.shiftLines(i, i, delta);
  }

  /** Deletes one line; its children move up one level. Undoable. */
  deleteLine(id: string) {
    const i = this.lines.findIndex((l) => l.id === id);
    if (i < 0) return;
    this.snapshot({ index: i, offset: 0 });
    const end = subtreeEnd(this.lines, i);
    for (let j = i + 1; j < end; j++) this.lines[j].indent = Math.max(0, this.lines[j].indent - 1);
    this.lines.splice(i, 1);
    if (!this.lines.length) this.lines.push(newLine());
    this.renumber();
    this.renderAll();
    this.emit();
  }

  undo() {
    this.restore(this.undoStack, this.redoStack);
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
    if (line.text !== text && this.suggestions.has(line.id)) this.setSuggestion(line.id, null);
    line.text = text;

    // Rapid logging prefix typed at the start of the line.
    const m = sel.start.offset <= 5 ? matchPrefix(text.slice(0, sel.start.offset)) : null;
    // A lone "* " marks priority only on a line that already has a bullet;
    // on plain text it stays a typed asterisk.
    const bulletless = line.type === 'text' || line.type === 'heading';
    if (m && m.length === sel.start.offset && !(m.type === 'text' && bulletless)) {
      line.text = text.slice(m.length);
      if (m.type !== 'text') Object.assign(line, { type: m.type, state: 'open' });
      line.priority = m.priority || line.priority;
      return this.commit({ index: i, offset: 0 });
    }
    // A due date just finished (a space typed after it): store it as due:YYYY-MM-DD.
    let caret = sel.start;
    if (/\s/.test(line.text[caret.offset - 1] ?? '')) {
      const resolved = this.resolveDueAt(i, caret.offset - 1);
      if (resolved !== null) caret = { index: i, offset: resolved + 1 };
    }
    const textEl = el?.querySelector<HTMLElement>('.line-text');
    // A list number or a date pill appeared, changed or went away: rebuild this
    // line's text, keep the caret, and recolor (children inherit).
    if (textEl && line.text && !textShapeMatches(textEl, line.text)) {
      fillText(textEl, line.text);
      this.placeCaret(caret);
      this.refreshDecor();
    } else if (caret !== sel.start) this.refreshDecor();
    // An emptied line can lose its <br>; keep it so the line keeps its height.
    if (textEl && !text && !textEl.querySelector('br')) {
      textEl.append(document.createElement('br'));
      this.refreshDecor();
    }
    this.emit();
  };

  private onKeyDown = (e: KeyboardEvent) => {
    const sel = this.readSelection();
    if (!sel) return;
    const atLineStart = sel.start.index === sel.end.index && sel.start.offset === 0 && sel.end.offset === 0;
    if (e.key === 'Backspace' && atLineStart && !e.metaKey && !e.altKey && !e.ctrlKey && !this.composing) {
      // Handled here rather than in beforeinput: at the very start of the
      // editor WebKit may not let beforeinput cancel the deletion, and would
      // move the caret into the gutter.
      e.preventDefault();
      this.snapshot(sel.start);
      this.backspaceAtStart(sel.start);
      return;
    }
    if (e.code === 'Tab') {
      e.preventDefault();
      this.snapshot(sel.start);
      this.shiftLines(sel.start.index, sel.end.index, e.shiftKey ? -1 : 1);
    } else if (e.code === 'Enter' && (e.metaKey || e.ctrlKey)) {
      e.preventDefault();
      const l = this.lines[sel.start.index];
      if (hasStates(l.type, this.eventStates)) this.updateById(l.id, (x) => ({ ...x, state: nextState(x.state) }));
    } else if ((e.code === 'ArrowRight' || e.code === 'ArrowLeft') && e.ctrlKey && e.altKey && !e.metaKey) {
      // ⌃⌥→ migrate, ⌃⌥← schedule (⌥→ alone moves by word on the Mac).
      e.preventDefault();
      this.markLine(this.lines[sel.start.index].id, e.code === 'ArrowRight' ? 'migrated' : 'scheduled');
    } else if (e.code === 'KeyZ' && (e.metaKey || e.ctrlKey)) {
      // Safari does not always send historyUndo for our custom edits.
      e.preventDefault();
      if (e.shiftKey) this.restore(this.redoStack, this.undoStack);
      else this.restore(this.undoStack, this.redoStack);
    }
  };

  /**
   * Whole lines covered by the current selection, plus the hidden children of
   * a collapsed last line: exports and copies always carry collapsed content.
   */
  selectedLines(): Line[] | null {
    const sel = this.readSelection();
    if (!sel) return null;
    const { start, end } = sel;
    if (start.index === end.index && start.offset === end.offset) return null;
    let last = end.index;
    // A selection that ends at the very start of a line does not include it.
    if (end.offset === 0 && end.index > start.index) last--;
    if (this.lines[last].collapsed) last = subtreeEnd(this.lines, last) - 1;
    return this.lines.slice(start.index, last + 1).map((l) => ({ ...l }));
  }

  /**
   * ⌘C / iOS "Copy" over several lines, or over the whole text of a collapsed
   * parent: copy from the model, including collapsed children. A few words
   * inside one line keep the native copy.
   */
  private onCopy = (e: ClipboardEvent) => {
    const sel = this.readSelection();
    if (!sel || !e.clipboardData) return;
    const { start, end } = sel;
    const line = this.lines[start.index];
    const wholeCollapsed = line.collapsed && start.offset === 0 && end.offset >= line.text.length && subtreeEnd(this.lines, start.index) > start.index + 1;
    if (start.index === end.index && !wholeCollapsed) return;
    const lines = this.selectedLines();
    if (!lines) return;
    e.preventDefault();
    const doc = selectionDoc(lines);
    e.clipboardData.setData('text/plain', toPlain(doc));
    e.clipboardData.setData('text/html', toHtml(doc));
    e.clipboardData.setData(LINES_MIME, JSON.stringify(lines));
    if (e.type === 'cut') {
      // Cut what was copied: hidden children of a collapsed last line go too.
      const last = this.lines.findIndex((l) => l.id === lines[lines.length - 1].id);
      const to = last > end.index ? { index: last, offset: this.lines[last].text.length } : end;
      this.snapshot(start);
      this.commit(this.deleteRange(start, to));
    }
  };

  /** Pasting entries (copied from the app, or its Markdown) recreates them as entries. */
  private onPaste = (e: ClipboardEvent) => {
    const data = e.clipboardData;
    const sel = this.readSelection();
    if (!data || !sel) return;
    const pasted = linesFromJson(data.getData(LINES_MIME)) ?? linesFromText(data.getData('text/plain'));
    if (!pasted) return; // ordinary text: the regular paste below
    e.preventDefault();
    this.snapshot(sel.start);
    const at = this.deleteRange(sel.start, sel.end);
    const line = this.lines[at.index];
    const fresh = pasted.map((p) => newLine({ ...p, indent: line.indent + p.indent }));
    const head = line.text.slice(0, at.offset);
    const tail = line.text.slice(at.offset);
    if (!line.text) this.lines.splice(at.index, 1, ...fresh);
    else if (!head) this.lines.splice(at.index, 0, ...fresh);
    else {
      line.text = head;
      const rest = tail ? [newLine({ type: line.type, indent: line.indent, text: tail })] : [];
      this.lines.splice(at.index + 1, 0, ...fresh, ...rest);
    }
    // Caret at the end of the last pasted line that is not folded away.
    const hidden = hiddenMask(this.lines);
    let last = this.lines.indexOf(fresh[fresh.length - 1]);
    while (last > 0 && hidden[last]) last--;
    this.commit({ index: last, offset: this.lines[last].text.length });
  };

  /** Safety net: the caret may only live inside a line's text, never in the gutter. */
  private onSelectionChange = () => {
    const sel = document.getSelection();
    if (sel && !sel.isCollapsed && sel.anchorNode && this.root.contains(sel.anchorNode)) {
      setSelection(this.selectedLines());
      return;
    }
    if (!sel || !sel.isCollapsed || !sel.anchorNode || !this.root.contains(sel.anchorNode)) return;
    // A caret back in the text (typing, tapping a line) ends the stored selection.
    setSelection(null);
    const node = sel.anchorNode;
    const el = node instanceof Element ? node : node.parentElement;
    if (el?.closest('.line-text')) return;
    let index = this.lineIndexOf(node);
    if (index < 0) index = node === this.root ? Math.min(sel.anchorOffset, this.lines.length - 1) : 0;
    this.placeCaret({ index, offset: 0 });
  };

  private onCompStart = () => {
    this.composing = true;
  };
  /** Resolves finished due expressions up to `upTo` in one line; returns where `upTo` moved, or null. */
  private resolveDueAt(index: number, upTo: number): number | null {
    const line = this.lines[index];
    const r = resolveDue(line.text, todayIso(), dueView.order, dueView.firstDay, upTo);
    if (!r) return null;
    line.text = r.text;
    return upTo + r.shift;
  }

  private lineDone(line: Line | undefined) {
    if (line && (line.type === 'task' || line.type === 'event') && line.text.trim().length >= 3) this.onLineDone?.({ ...line });
  }

  /** Shows (or with null removes) the "Link it?" chip under a line. */
  setSuggestion(lineId: string, s: { sourceId: string; text: string } | null) {
    const i = this.lines.findIndex((l) => l.id === lineId);
    const el = this.root.children[i] as HTMLElement | undefined;
    el?.querySelector(':scope > .link-chip')?.remove();
    if (!s || i < 0) return void this.suggestions.delete(lineId);
    this.suggestions.set(lineId, s);
    el?.append(linkChip(s.text));
  }

  /** Leaving the editor finishes any due date still being written. */
  private onBlur = () => {
    const sel = this.readSelection();
    if (sel) this.lineDone(this.lines[sel.start.index]);
    let changed = false;
    this.lines.forEach((l, i) => {
      if (this.resolveDueAt(i, l.text.length) !== null) changed = true;
    });
    if (!changed) return;
    this.renderAll();
    this.emit();
  };

  private onDecorDown = (e: MouseEvent) => {
    if ((e.target as Element).closest?.('.due, .sort-btn, .link-chip')) e.preventDefault();
  };

  private onDecorClick = (e: MouseEvent) => {
    const target = e.target as Element;
    const answer = target.closest?.<HTMLElement>('.link-chip [data-act]');
    if (answer) {
      e.preventDefault();
      const id = answer.closest<HTMLElement>('.line')?.dataset.id;
      const s = id && this.suggestions.get(id);
      if (!id || !s) return;
      this.setSuggestion(id, null);
      this.onLinkAnswer?.(id, s.sourceId, answer.dataset.act === 'link');
      return;
    }
    const pill = target.closest?.<HTMLElement>('.due');
    const sort = target.closest?.('.sort-btn');
    if (!pill && !sort) return;
    e.preventDefault();
    const index = this.lineIndexOf(target);
    if (index < 0) return;
    if (sort) return this.sortAt(index);
    this.pickDate(index, pill!);
  };

  /** Sorts the list starting at this line by date (the user's tap). Undo puts it back. */
  private sortAt(index: number) {
    const run = dateRuns(this.lines).find((r) => r.items[0] === index);
    if (!run) return;
    this.snapshot(this.readSelection()?.start ?? { index, offset: 0 });
    this.lines = sortRun(this.lines, run);
    this.renderAll();
    this.emit();
  }

  /** Tapping a date pill opens the system date picker to change it. */
  private pickDate(index: number, pill: HTMLElement) {
    const id = this.lines[index].id;
    const nth = [...(this.root.children[index]?.querySelectorAll('.due') ?? [])].indexOf(pill);
    const r = pill.getBoundingClientRect();
    const input = document.createElement('input');
    input.type = 'date';
    input.className = 'due-picker';
    input.value = pill.dataset.iso ?? '';
    input.setAttribute('aria-label', t.due.change);
    Object.assign(input.style, { left: `${r.left}px`, top: `${r.top}px`, width: `${r.width}px`, height: `${r.height}px` });
    document.body.append(input);
    input.addEventListener('change', () => input.value && this.setDue(id, nth, input.value));
    input.addEventListener('blur', () => window.setTimeout(() => input.remove(), 0));
    try {
      input.focus();
      input.showPicker();
    } catch {
      input.click();
    }
  }

  private setDue(id: string, nth: number, iso: string) {
    const i = this.lines.findIndex((l) => l.id === id);
    if (i < 0) return;
    let n = -1;
    const text = this.lines[i].text.replace(DUE_TOKEN, (m) => (++n === nth ? `due:${iso}` : m));
    if (text === this.lines[i].text) return;
    this.snapshot({ index: i, offset: 0 });
    this.lines[i] = { ...this.lines[i], text };
    const textEl = this.root.children[i]?.querySelector<HTMLElement>('.line-text');
    if (textEl) fillText(textEl, text);
    this.refreshDecor();
    this.emit();
  }

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
  /** Settings › Event states. */
  eventStates?: boolean;
  /** Receives a function that places the caret at the end of a line (or of the page), for taps on empty space. */
  focusRef?: MutableRefObject<((lineId?: string) => void) | null>;
  /** Settings › Reverse swipe directions. */
  reverseSwipes?: boolean;
  /** Phase 4b: an open item this finished line looks like a rewrite of (suggestion only). */
  findRewrite?: (line: Line) => Promise<{ sourceId: string; text: string } | null>;
  /** The user tapped "Link it" (true) or dismissed the suggestion (false). */
  onLinkAnswer?: (lineId: string, sourceId: string, link: boolean) => void;
}

export function LineEditor({
  initial,
  onChange,
  autoFocus,
  className,
  label,
  eventStates = true,
  focusRef,
  reverseSwipes = false,
  findRewrite,
  onLinkAnswer,
}: Props) {
  const host = useRef<HTMLDivElement>(null);
  const core = useRef<LineEditorCore | null>(null);
  const [menu, setMenu] = useState<{ id: string; anchor: DOMRect } | null>(null);
  const [toast, setToast] = useState(0);
  const [linked, setLinked] = useState(0);
  const find = useRef(findRewrite);
  find.current = findRewrite;
  const answer = useRef(onLinkAnswer);
  answer.current = onLinkAnswer;
  const [marked, setMarked] = useState<{ n: number; mark: Mark | null } | null>(null);

  useEffect(() => {
    const c = new LineEditorCore(host.current!, initial, onChange, className);
    core.current = c;
    c.eventStates = eventStates;
    c.reverseSwipes = reverseSwipes;
    c.onLineDone = (line) =>
      void find.current?.(line).then((s) => {
        if (s && core.current === c) c.setSuggestion(line.id, s);
      });
    c.onLinkAnswer = (lineId, sourceId, link) => {
      answer.current?.(lineId, sourceId, link);
      if (link) setLinked((n) => n + 1);
    };
    c.onMark = (mark) => setMarked((m) => ({ n: (m?.n ?? 0) + 1, mark }));
    c.onMenu = (id, anchor) => setMenu({ id, anchor });
    if (label) host.current!.setAttribute('aria-label', label);
    if (focusRef) focusRef.current = (lineId) => c.focusEnd(lineId);
    if (autoFocus) c.focusEnd();
    return () => {
      if (focusRef) focusRef.current = null;
      core.current = null;
      c.destroy();
    };
    // The editor owns its state after mount.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  useEffect(() => {
    if (core.current) core.current.eventStates = eventStates;
  }, [eventStates]);
  useEffect(() => {
    if (core.current) core.current.reverseSwipes = reverseSwipes;
  }, [reverseSwipes]);

  const closeMenu = useCallback(() => setMenu(null), []);
  const hideToast = useCallback(() => setToast(0), []);
  const hideMark = useCallback(() => setMarked(null), []);
  const line = menu ? core.current?.lineById(menu.id) : undefined;
  const actions = useMemo<MenuActions | null>(
    () =>
      menu && {
        patch: (patch) => {
          const before = core.current?.lineById(menu.id)?.state;
          core.current?.patchLine(menu.id, patch);
          const mark = patch.state === 'migrated' || patch.state === 'scheduled' ? patch.state : null;
          if (mark && before !== mark) setMarked((m) => ({ n: (m?.n ?? 0) + 1, mark }));
        },
        shift: (delta) => core.current?.shiftLine(menu.id, delta),
        remove: () => {
          core.current?.deleteLine(menu.id);
          setToast((n) => n + 1);
        },
        close: closeMenu,
      },
    [menu, closeMenu],
  );

  return (
    <>
      <div ref={host} />
      {menu && line && actions && <BulletMenu line={line} anchor={menu.anchor} eventStates={eventStates} actions={actions} />}
      {toast > 0 && <UndoToast key={toast} onUndo={() => core.current?.undo()} onDone={hideToast} />}
      {linked > 0 && <StatusToast key={linked} text={t.link.linked} onDone={() => setLinked(0)} />}
      {marked && <MarkToast key={marked.n} mark={marked.mark} onUndo={() => core.current?.undo()} onDone={hideMark} />}
    </>
  );
}

function sortButton(): HTMLElement {
  const b = document.createElement('span');
  b.className = 'sort-btn';
  b.contentEditable = 'false';
  b.setAttribute('role', 'button');
  b.setAttribute('aria-label', t.due.sort);
  b.title = t.due.sort;
  b.innerHTML =
    '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M7 4v16M3.5 16.5 7 20l3.5-3.5M13 6h8M13 11h6M13 16h4"/></svg>';
  return b;
}

/** "Looks like the open item … Link it?": a quiet, dismissible suggestion under a line (Phase 4b). */
function linkChip(text: string): HTMLElement {
  const chip = document.createElement('div');
  chip.className = 'link-chip';
  chip.contentEditable = 'false';
  chip.setAttribute('role', 'group');
  const label = document.createElement('span');
  label.className = 'link-text';
  label.textContent = text;
  const link = document.createElement('button');
  link.type = 'button';
  link.dataset.act = 'link';
  link.textContent = t.link.action;
  const no = document.createElement('button');
  no.type = 'button';
  no.dataset.act = 'dismiss';
  no.className = 'link-dismiss';
  no.setAttribute('aria-label', t.link.dismiss);
  no.innerHTML =
    '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>';
  chip.append(label, link, no);
  return chip;
}

function StatusToast({ text, onDone }: { text: string; onDone: () => void }) {
  useEffect(() => {
    const id = window.setTimeout(onDone, 3000);
    return () => window.clearTimeout(id);
  }, [onDone]);
  return (
    <div className="undo-toast" role="status">
      <span>{text}</span>
    </div>
  );
}
