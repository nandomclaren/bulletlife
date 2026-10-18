import { useEffect, useState, type ReactNode } from 'react';
import { t } from '../i18n/en';

export interface EditorApi {
  indent(): void;
  outdent(): void;
  togglePriority(): void;
}

const coarse = () => window.matchMedia('(pointer: coarse)').matches;

// Sits right above the iOS keyboard while the editor has focus.
export function KeyboardBar({ api, visible }: { api: EditorApi | null; visible: boolean }) {
  const [bottom, setBottom] = useState(0);

  useEffect(() => {
    const vv = window.visualViewport;
    if (!vv) return;
    const update = () => setBottom(Math.max(0, window.innerHeight - (vv.offsetTop + vv.height)));
    update();
    vv.addEventListener('resize', update);
    vv.addEventListener('scroll', update);
    return () => {
      vv.removeEventListener('resize', update);
      vv.removeEventListener('scroll', update);
    };
  }, []);

  if (!visible || !api || !coarse()) return null;

  return (
    <div className="kb-bar" style={{ bottom }} role="toolbar" aria-label={t.editor.toolbar}>
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
