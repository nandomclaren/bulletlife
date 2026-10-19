// After a > or < mark: which mark it got, and Undo. Writing the item at its
// destination is the user's own work, so the app names no destination.
import { useEffect } from 'react';
import type { Mark } from '../data/openItems';
import { t } from '../i18n/en';

export function MarkToast({ mark, onUndo, onDone }: { mark: Mark | null; onUndo: () => void; onDone: () => void }) {
  useEffect(() => {
    const id = window.setTimeout(onDone, 4500);
    return () => window.clearTimeout(id);
  }, [onDone]);
  return (
    <div className="undo-toast mark-toast" role="status">
      <span>
        {mark ? (
          <>
            <b className="mark-glyph">{mark === 'migrated' ? '>' : '<'}</b> {t.open.marked[mark]}
          </>
        ) : (
          t.open.unmarked
        )}
      </span>
      <button
        onClick={() => {
          onDone();
          onUndo();
        }}
      >
        {t.menu.undo}
      </button>
    </div>
  );
}
