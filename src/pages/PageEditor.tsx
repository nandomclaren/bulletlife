// Binds one editor to one (log, slot) in the repository: loads once, saves
// shortly after each change, and flushes when leaving the page or the app.
import { useEffect, useRef, useState } from 'react';
import { LineEditor } from '../editor/LineEditor';
import type { Line } from '../editor/lines';
import { loadLines, saveLines, useSettings, type LogRef } from '../data/repo';

const SAVE_DELAY = 400;

interface Props {
  log: LogRef;
  slot?: string;
  autoFocus?: boolean;
  compact?: boolean;
  label?: string;
}

export function PageEditor({ log, slot = '', autoFocus, compact, label }: Props) {
  const [initial, setInitial] = useState<Line[] | null>(null);
  const { eventStates } = useSettings();
  const pending = useRef<Line[] | null>(null);
  const timer = useRef(0);
  const logRef = useRef(log);
  logRef.current = log;
  const focusAt = useRef<((lineId?: string) => void) | null>(null);

  useEffect(() => {
    let alive = true;
    void loadLines(log.id, slot).then((lines) => alive && setInitial(lines));
    return () => {
      alive = false;
    };
  }, [log.id, slot]);

  useEffect(() => {
    const flush = () => {
      window.clearTimeout(timer.current);
      const lines = pending.current;
      pending.current = null;
      if (lines) void saveLines(logRef.current, slot, lines);
    };
    const onHide = () => document.visibilityState === 'hidden' && flush();
    window.addEventListener('pagehide', flush);
    document.addEventListener('visibilitychange', onHide);
    return () => {
      window.removeEventListener('pagehide', flush);
      document.removeEventListener('visibilitychange', onHide);
      flush();
    };
  }, [slot]);

  if (!initial) return <div className={`editor-area${compact ? ' compact' : ''}`} />;

  return (
    // The whole free area around the lines is a tap target: a tap below the
    // text puts the caret at the end (the first line of an empty page); a tap
    // in a line's margin puts it at the end of that line.
    <div
      className={`editor-area${compact ? ' compact' : ''}`}
      onClick={(e) => {
        const target = e.target as Element;
        if (target.closest('.line-text, .bullet, .chevron')) return;
        focusAt.current?.(target.closest<HTMLElement>('.line')?.dataset.id);
      }}
    >
      <LineEditor
        initial={initial}
        autoFocus={autoFocus}
        className={compact ? 'compact' : ''}
        label={label}
        eventStates={eventStates}
        focusRef={focusAt}
        onChange={(lines) => {
          pending.current = lines;
          window.clearTimeout(timer.current);
          timer.current = window.setTimeout(() => {
            pending.current = null;
            void saveLines(logRef.current, slot, lines);
          }, SAVE_DELAY);
        }}
      />
    </div>
  );
}
