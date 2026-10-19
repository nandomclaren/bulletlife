// Menu for one entry, opened by a long press or right click on its bullet.
// Every action applies to this single entry (CLAUDE.md principle 1).
import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { t } from '../i18n/en';
import { hasStates, type Line, type LineState, type LineType } from './lines';

export interface MenuActions {
  patch: (patch: Partial<Line>) => void;
  shift: (delta: 1 | -1) => void;
  remove: () => void;
  close: () => void;
}

const TYPES: Array<Exclude<LineType, 'heading'>> = ['task', 'event', 'note', 'text'];
const STATES: LineState[] = ['open', 'done', 'cancelled', 'migrated', 'scheduled'];
const MARGIN = 8;

export function BulletMenu({
  line,
  anchor,
  eventStates,
  actions,
  statesOnly,
}: {
  line: Line;
  anchor: DOMRect;
  eventStates: boolean;
  actions: MenuActions;
  /** The Open items panel only marks states (CLAUDE.md 4.3). */
  statesOnly?: boolean;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState<{ left: number; top: number } | null>(null);

  // Place below the bullet, or above it when there is no room; never off screen.
  useLayoutEffect(() => {
    const el = ref.current!;
    const vw = window.innerWidth;
    const vh = window.visualViewport?.height ?? window.innerHeight;
    const { width, height } = el.getBoundingClientRect();
    const left = Math.min(Math.max(MARGIN, anchor.left - 12), vw - width - MARGIN);
    const below = anchor.bottom + 6;
    const top = below + height + MARGIN <= vh ? below : Math.max(MARGIN, anchor.top - height - 6);
    setPos({ left, top });
  }, [anchor]);

  useEffect(() => {
    const onDown = (e: PointerEvent) => !ref.current?.contains(e.target as Node) && actions.close();
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && actions.close();
    const onScroll = (e: Event) => !ref.current?.contains(e.target as Node) && actions.close();
    document.addEventListener('pointerdown', onDown, true);
    document.addEventListener('keydown', onKey);
    window.addEventListener('scroll', onScroll, true);
    return () => {
      document.removeEventListener('pointerdown', onDown, true);
      document.removeEventListener('keydown', onKey);
      window.removeEventListener('scroll', onScroll, true);
    };
  }, [actions]);

  const done = (fn: () => void) => () => {
    fn();
    actions.close();
  };
  const stateful = hasStates(line.type, eventStates);
  const bulleted = line.type !== 'text' && line.type !== 'heading';

  return createPortal(
    <div
      ref={ref}
      className="bullet-menu"
      role="menu"
      aria-label={t.menu.label}
      style={pos ? { left: pos.left, top: pos.top } : { visibility: 'hidden', left: 0, top: 0 }}
      // Keep the editor's focus and caret on the Mac.
      onMouseDown={(e) => e.preventDefault()}
    >
      {!statesOnly && (
        <Section title={t.menu.type}>
          {TYPES.map((type) => (
            <Chip
              key={type}
              active={line.type === type}
              onClick={done(() =>
                actions.patch(
                  type === line.type
                    ? {}
                    : {
                        type,
                        state: 'open',
                        ...(type === 'text'
                          ? {
                              priority: false,
                              inspiration: false,
                              explore: false,
                            }
                          : {}),
                      },
                ),
              )}
            >
              <Glyph type={type} state="open" />
              {t.menu.types[type]}
            </Chip>
          ))}
        </Section>
      )}

      {stateful && (
        <Section title={t.menu.state}>
          {STATES.map((state) => (
            <Chip key={state} active={line.state === state} onClick={done(() => actions.patch({ state }))}>
              <Glyph type={line.type} state={state} />
              {t.menu.states[state]}
            </Chip>
          ))}
        </Section>
      )}

      {bulleted && !statesOnly && (
        <Section title={t.menu.signifiers}>
          <Chip active={!!line.priority} onClick={done(() => actions.patch({ priority: !line.priority }))}>
            <span className="chip-mark">*</span>
            {t.menu.priority}
          </Chip>
          <Chip active={!!line.inspiration} onClick={done(() => actions.patch({ inspiration: !line.inspiration }))}>
            <span className="chip-mark">!</span>
            {t.menu.inspiration}
          </Chip>
          <Chip active={!!line.explore} onClick={done(() => actions.patch({ explore: !line.explore }))}>
            <span className="chip-mark chip-eye" aria-hidden />
            {t.menu.explore}
          </Chip>
        </Section>
      )}

      {!statesOnly && (
        <div className="menu-actions">
          <button role="menuitem" onClick={done(() => actions.shift(-1))} disabled={line.indent === 0}>
            {t.menu.outdent}
          </button>
          <button role="menuitem" onClick={done(() => actions.shift(1))}>
            {t.menu.indent}
          </button>
          <button role="menuitem" className="menu-delete" onClick={done(actions.remove)}>
            {t.menu.delete}
          </button>
        </div>
      )}
    </div>,
    document.body,
  );
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="menu-section" role="group" aria-label={title}>
      <div className="menu-section-title">{title}</div>
      <div className="menu-chips">{children}</div>
    </div>
  );
}

function Chip({ active, onClick, children }: { active: boolean; onClick: () => void; children: ReactNode }) {
  return (
    <button role="menuitemradio" aria-checked={active} className="menu-chip" onClick={onClick}>
      {children}
    </button>
  );
}

/** Small bullet preview, colored like the entry type. */
function Glyph({ type, state }: { type: LineType; state: LineState }) {
  const cls =
    type === 'text' || type === 'heading'
      ? 'g-none'
      : type === 'note'
        ? 'g-dash'
        : state === 'done'
          ? 'g-cross'
          : state === 'migrated'
            ? 'g-gt'
            : state === 'scheduled'
              ? 'g-lt'
              : type === 'task'
                ? 'g-dot'
                : 'g-ring';
  const struck = state === 'cancelled' && (type === 'task' || type === 'event') ? ' g-cancel' : '';
  return <span className={`chip-glyph ${cls}${struck} c-${type}`} aria-hidden />;
}

/** Bottom toast with Undo after a delete. */
export function UndoToast({ onUndo, onDone }: { onUndo: () => void; onDone: () => void }) {
  useEffect(() => {
    const timer = window.setTimeout(onDone, 5000);
    return () => window.clearTimeout(timer);
  }, [onDone]);
  return createPortal(
    <div className="undo-toast" role="status">
      <span>{t.menu.deleted}</span>
      <button
        onMouseDown={(e) => e.preventDefault()}
        onClick={() => {
          onUndo();
          onDone();
        }}
      >
        {t.menu.undo}
      </button>
    </div>,
    document.body,
  );
}
