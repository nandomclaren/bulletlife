// Binds one editor to one (log, slot) in the repository: loads once, saves
// shortly after each change, and flushes when leaving the page or the app.
import { useEffect, useRef, useState } from 'react';
import { LineEditor } from '../editor/LineEditor';
import type { Line } from '../editor/lines';
import { loadLines, saveLines, type LogRef } from '../data/repo';

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
  const pending = useRef<Line[] | null>(null);
  const timer = useRef(0);
  const logRef = useRef(log);
  logRef.current = log;

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

  if (!initial) return <div className={compact ? 'editor-loading compact' : 'editor-loading'} />;

  return (
    <LineEditor
      initial={initial}
      autoFocus={autoFocus}
      className={compact ? 'compact' : ''}
      label={label}
      onChange={(lines) => {
        pending.current = lines;
        window.clearTimeout(timer.current);
        timer.current = window.setTimeout(() => {
          pending.current = null;
          void saveLines(logRef.current, slot, lines);
        }, SAVE_DELAY);
      }}
    />
  );
}
