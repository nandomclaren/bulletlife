// Prototype A: ProseMirror with a flat list of line nodes (indent as an attribute).
import { useEffect, useRef } from 'react';
import { baseKeymap, joinBackward } from 'prosemirror-commands';
import { history, redo, undo } from 'prosemirror-history';
import { InputRule, inputRules, undoInputRule } from 'prosemirror-inputrules';
import { keymap } from 'prosemirror-keymap';
import { Schema, type Node as PMNode } from 'prosemirror-model';
import { EditorState, Plugin, TextSelection, type Command, type Transaction } from 'prosemirror-state';
import { Decoration, DecorationSet, EditorView } from 'prosemirror-view';
import type { EditorApi } from '../editor/KeyboardBar';
import { attachGutter } from '../editor/gutter';
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
} from '../editor/lines';
import { buildGutter, EVENT_STATES, lineClass } from '../editor/render';

const schema = new Schema({
  nodes: {
    doc: { content: 'line+' },
    line: {
      content: 'text*',
      attrs: {
        id: { default: '' },
        type: { default: 'text' },
        state: { default: 'open' },
        indent: { default: 0 },
        collapsed: { default: false },
        priority: { default: false },
      },
      toDOM(node) {
        const line = nodeToLine(node);
        const dom = document.createElement('div');
        dom.dataset.id = line.id;
        dom.style.setProperty('--indent', String(line.indent));
        dom.className = 'line'; // derived classes come from viewPlugin decorations
        const text = document.createElement('div');
        text.className = 'line-text';
        dom.append(buildGutter(document, line, line.collapsed), text);
        return { dom, contentDOM: text };
      },
    },
    text: {},
  },
});

function nodeToLine(node: PMNode): Line {
  const a = node.attrs;
  return {
    id: a.id,
    type: a.type,
    state: a.state,
    indent: a.indent,
    collapsed: a.collapsed,
    priority: a.priority,
    text: node.textContent,
  };
}

function docToLines(doc: PMNode): Line[] {
  const lines: Line[] = [];
  doc.forEach((n) => lines.push(nodeToLine(n)));
  return lines;
}

function linesToDoc(lines: Line[]): PMNode {
  return schema.node(
    'doc',
    null,
    lines.map((l) => {
      const { text, ...attrs } = l;
      return schema.node('line', attrs, text ? schema.text(text) : undefined);
    }),
  );
}

/** Positions (before each line node) in document order. */
function linePositions(doc: PMNode): number[] {
  const pos: number[] = [];
  doc.forEach((_n, offset) => pos.push(offset));
  return pos;
}

function lineIndexAt(doc: PMNode, pos: number) {
  return doc.resolve(pos).index(0);
}

// Derived classes: inherited color, chevrons, hidden subtrees.
const viewPlugin = new Plugin({
  props: {
    decorations(state) {
      const lines = docToLines(state.doc);
      const colors = colorTypes(lines);
      const hidden = hiddenMask(lines);
      const decos: Decoration[] = [];
      state.doc.forEach((node, offset, i) => {
        const cls = lineClass(nodeToLine(node), { color: colors[i], hasChildren: hasChildren(lines, i), hidden: hidden[i] });
        decos.push(Decoration.node(offset, offset + node.nodeSize, { class: cls }));
      });
      return DecorationSet.create(state.doc, decos);
    },
  },
});

const prefixRule = new InputRule(/^(?:\* )?(?:o\.|\.|-|#)? $/, (state, match, start, end) => {
  const m = matchPrefix(match[0]);
  if (!m) return null;
  const $start = state.doc.resolve(start);
  const line = $start.parent;
  const before = $start.before();
  const type = m.type === 'text' ? line.attrs.type : m.type;
  return state.tr.delete(start, end).setNodeMarkup(before, undefined, { ...line.attrs, type, state: 'open', priority: m.priority || line.attrs.priority });
});

function setIndents(tr: Transaction, indents: number[]) {
  const positions = linePositions(tr.doc);
  tr.doc.forEach((node, _o, i) => {
    if (node.attrs.indent !== indents[i]) tr.setNodeMarkup(positions[i], undefined, { ...node.attrs, indent: indents[i] });
  });
  return tr;
}

const shift =
  (delta: 1 | -1): Command =>
  (state, dispatch) => {
    const lines = docToLines(state.doc);
    const from = lineIndexAt(state.doc, state.selection.from);
    const to = lineIndexAt(state.doc, state.selection.to);
    const indents = shiftIndent(lines, from, to, delta);
    if (!indents) return true; // swallow Tab even when not allowed
    dispatch?.(setIndents(state.tr, indents));
    return true;
  };

const enter: Command = (state, dispatch) => {
  let tr = state.tr;
  if (!state.selection.empty) tr = tr.deleteSelection();
  const $from = tr.selection.$from;
  const line = $from.parent;
  const before = $from.before();
  const attrs = line.attrs;
  if (line.content.size === 0 && attrs.type !== 'text') {
    // Enter on an empty bullet: outdent, then fall back to plain text.
    if (attrs.indent > 0) {
      const indents = shiftIndent(docToLines(tr.doc), $from.index(0), $from.index(0), -1);
      if (indents) setIndents(tr, indents);
    } else {
      tr.setNodeMarkup(before, undefined, { ...attrs, type: 'text', state: 'open', priority: false });
    }
    dispatch?.(tr.scrollIntoView());
    return true;
  }
  const fresh = { ...newLine({ type: continuationType(attrs.type), indent: attrs.indent }) } as Record<string, unknown>;
  delete fresh.text;
  if ($from.parentOffset === 0) {
    // Caret at the start: open a new line above, keep this line (and its id) intact.
    tr.insert(before, schema.node('line', fresh));
    tr.setSelection(TextSelection.create(tr.doc, before + 2 + 1)); // empty line is 2 wide
  } else {
    if (attrs.collapsed) tr.setNodeMarkup(before, undefined, { ...attrs, collapsed: false });
    tr.split(tr.selection.from, 1, [{ type: schema.nodes.line, attrs: fresh }]);
  }
  dispatch?.(tr.scrollIntoView());
  return true;
};

const backspace: Command = (state, dispatch, view) => {
  const { $from, empty } = state.selection;
  if (!empty || $from.parentOffset !== 0) return false;
  const line = $from.parent;
  if (line.attrs.type !== 'text') {
    dispatch?.(state.tr.setNodeMarkup($from.before(), undefined, { ...line.attrs, type: 'text', state: 'open', priority: false }));
    return true;
  }
  if (line.attrs.indent > 0) return shift(-1)(state, dispatch, view);
  return joinBackward(state, dispatch, view);
};

function updateLine(view: EditorView, id: string, fn: (attrs: Record<string, unknown>) => Record<string, unknown> | null) {
  const { state } = view;
  let target = -1;
  let node: PMNode | null = null;
  state.doc.forEach((n, offset) => {
    if (n.attrs.id === id) {
      target = offset;
      node = n;
    }
  });
  if (target < 0 || !node) return;
  const attrs = fn((node as PMNode).attrs);
  if (attrs) view.dispatch(state.tr.setNodeMarkup(target, undefined, attrs));
}

const cycleAtCaret: Command = (state, dispatch) => {
  const line = state.selection.$from.parent;
  if (!hasStates(line.attrs.type, EVENT_STATES)) return true;
  dispatch?.(state.tr.setNodeMarkup(state.selection.$from.before(), undefined, { ...line.attrs, state: nextState(line.attrs.state) }));
  return true;
};

const togglePriority: Command = (state, dispatch) => {
  const line = state.selection.$from.parent;
  if (line.attrs.type === 'heading') return true;
  dispatch?.(state.tr.setNodeMarkup(state.selection.$from.before(), undefined, { ...line.attrs, priority: !line.attrs.priority }));
  return true;
};

interface Props {
  initial: Line[];
  onChange: (lines: Line[]) => void;
  onApi: (api: EditorApi | null) => void;
  onFocusChange: (focused: boolean) => void;
}

export function PmEditor({ initial, onChange, onApi, onFocusChange }: Props) {
  const host = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const view = new EditorView(host.current!, {
      state: EditorState.create({
        doc: linesToDoc(initial),
        plugins: [
          history(),
          inputRules({ rules: [prefixRule] }),
          keymap({
            Enter: enter,
            Backspace: (s, d, v) => undoInputRule(s, d) || backspace(s, d, v),
            Tab: shift(1),
            'Shift-Tab': shift(-1),
            'Mod-Enter': cycleAtCaret,
            'Mod-z': undo,
            'Shift-Mod-z': redo,
            'Mod-y': redo,
          }),
          keymap(baseKeymap),
          viewPlugin,
        ],
      }),
      attributes: { class: 'editor', spellcheck: 'true', autocapitalize: 'sentences' },
      dispatchTransaction(tr) {
        const next = view.state.apply(tr);
        view.updateState(next);
        if (tr.docChanged) onChange(docToLines(next.doc));
      },
      handleDOMEvents: {
        focus: () => (onFocusChange(true), false),
        blur: () => (onFocusChange(false), false),
      },
    });

    const detach = attachGutter(view.dom as HTMLElement, {
      bullet: (id) =>
        updateLine(view, id, (a) => (hasStates(a.type as Line['type'], EVENT_STATES) ? { ...a, state: nextState(a.state as Line['state']) } : null)),
      chevron: (id) => updateLine(view, id, (a) => ({ ...a, collapsed: !a.collapsed })),
    });

    onApi({
      indent: () => shift(1)(view.state, view.dispatch),
      outdent: () => shift(-1)(view.state, view.dispatch),
      togglePriority: () => togglePriority(view.state, view.dispatch),
    });

    // Open on a fresh line at the end, ready to type.
    view.dispatch(view.state.tr.setSelection(TextSelection.atEnd(view.state.doc)));
    view.focus();

    return () => {
      detach();
      onApi(null);
      view.destroy();
    };
    // The editor owns its state after mount.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return <div ref={host} />;
}
