import { useEffect, useState, type ReactNode } from 'react';
import { t } from '../i18n/en';

export interface EditorApi {
  indent(): void;
  outdent(): void;
  togglePriority(): void;
}

const coarse = () => window.matchMedia('(pointer: coarse)').matches;

const isIOS = () => /iPhone|iPad/.test(navigator.userAgent) || (/Macintosh/.test(navigator.userAgent) && navigator.maxTouchPoints > 1);

// iOS always shows its own form bar (^ v ✓) above the keyboard and web apps
// cannot hide it; it floats over the bottom of the visual viewport. Sit above it.
const IOS_FORM_BAR = 58;
const SETTLE_MS = 180;

// Pinned above the keyboard while the editor has focus. Hidden while the
// keyboard or page is moving, so it never visibly chases the viewport.
export function KeyboardBar({ api, visible }: { api: EditorApi | null; visible: boolean }) {
  const [bottom, setBottom] = useState(0);
  const [settled, setSettled] = useState(true);

  useEffect(() => {
    const vv = window.visualViewport;
    if (!vv) return;
    let timer = 0;
    const update = () => {
      setSettled(false);
      window.clearTimeout(timer);
      timer = window.setTimeout(() => {
        const keyboard = Math.max(0, window.innerHeight - (vv.offsetTop + vv.height));
        setBottom(keyboard + (keyboard > 0 && isIOS() ? IOS_FORM_BAR : 0));
        setSettled(true);
      }, SETTLE_MS);
    };
    update();
    vv.addEventListener('resize', update);
    vv.addEventListener('scroll', update);
    return () => {
      window.clearTimeout(timer);
      vv.removeEventListener('resize', update);
      vv.removeEventListener('scroll', update);
    };
  }, []);

  if (!visible || !api || !coarse()) return null;

  return (
    <div className={`kb-bar${settled ? '' : ' is-moving'}`} style={{ bottom }} role="toolbar" aria-label={t.editor.toolbar}>
      <BarButton label={t.editor.outdent} onPress={() => api.outdent()}>
        ⇤
      </BarButton>
      <BarButton label={t.editor.indent} onPress={() => api.indent()}>
        ⇥
      </BarButton>
      <BarButton label={t.editor.priority} onPress={() => api.togglePriority()}>
        ★
      </BarButton>
    </div>
  );
}

function BarButton({ label, onPress, children }: { label: string; onPress: () => void; children: ReactNode }) {
  return (
    <button
      className="kb-btn"
      aria-label={label}
      // Never take focus from the editor.
      onMouseDown={(e) => e.preventDefault()}
      onTouchEnd={(e) => {
        e.preventDefault();
        onPress();
      }}
      onClick={onPress}
    >
      {children}
    </button>
  );
}
