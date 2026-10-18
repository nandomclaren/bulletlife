import { useEffect, useRef, useState } from 'react';
import { t } from '../i18n/en';

export type BulletType = 'task' | 'event' | 'note';
export type BulletState = 'open' | 'done' | 'cancelled';

const LONG_PRESS_MS = 500;
const MOVE_TOLERANCE = 10;
const NEXT: Record<BulletState, BulletState> = { open: 'done', done: 'cancelled', cancelled: 'open' };

function glyph(type: BulletType, state: BulletState) {
  if (type === 'note') return '–';
  if (state === 'done') return '×';
  return type === 'task' ? '•' : '○';
}

interface Props {
  type: BulletType;
  state: BulletState;
  onState: (s: BulletState) => void;
  onMenu?: (openedBy: string) => void;
}

// Long press is built from Pointer Events because iOS Safari fires no
// contextmenu on long press. Right click / Ctrl-click use contextmenu.
export function Bullet({ type, state, onState, onMenu }: Props) {
  const [menuOpen, setMenuOpen] = useState(false);
  const timer = useRef<number | null>(null);
  const start = useRef<{ x: number; y: number } | null>(null);
  const suppressClick = useRef(false);

  const clear = () => {
    if (timer.current != null) window.clearTimeout(timer.current);
    timer.current = null;
  };
  useEffect(() => clear, []);

  const openMenu = (by: string) => {
    setMenuOpen(true);
    onMenu?.(by);
  };

  const label = `${t.bullets[type]}${type === 'note' ? '' : `, ${t.bullets.states[state]}`}`;

  return (
    <span className="bullet-wrap">
      <button
        className="bullet"
        aria-label={label}
        onPointerDown={(e) => {
          if (e.pointerType === 'mouse' && e.button !== 0) return;
          start.current = { x: e.clientX, y: e.clientY };
          suppressClick.current = false;
          clear();
          timer.current = window.setTimeout(() => {
            suppressClick.current = true;
            openMenu(`long press (${e.pointerType})`);
          }, LONG_PRESS_MS);
        }}
        onPointerMove={(e) => {
          const s = start.current;
          if (s && Math.hypot(e.clientX - s.x, e.clientY - s.y) > MOVE_TOLERANCE) clear();
        }}
        onPointerUp={clear}
        onPointerCancel={clear}
        onContextMenu={(e) => {
          e.preventDefault();
          clear();
          suppressClick.current = true;
          openMenu(e.ctrlKey ? 'ctrl-click' : 'right click');
        }}
        onClick={() => {
          if (suppressClick.current) {
            suppressClick.current = false;
            return;
          }
          if (type !== 'note') onState(NEXT[state]);
        }}
      >
        <span className="glyph" aria-hidden>
          {glyph(type, state)}
        </span>
      </button>
      {menuOpen && (
        <div className="menu" role="menu">
          {type !== 'note' && (
            <>
              <button role="menuitem" onClick={() => (onState('done'), setMenuOpen(false))}>
                {t.checks.longPress.complete}
              </button>
              <button role="menuitem" onClick={() => (onState('cancelled'), setMenuOpen(false))}>
                {t.checks.longPress.cancel}
              </button>
            </>
          )}
          <button role="menuitem" onClick={() => setMenuOpen(false)}>
            {t.checks.longPress.close}
          </button>
        </div>
      )}
    </span>
  );
}
