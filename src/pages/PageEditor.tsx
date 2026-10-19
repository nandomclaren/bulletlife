// Binds one editor to one (log, slot) in the repository: loads once, saves
// shortly after each change, and flushes when leaving the page or the app.
import { useEffect, useRef, useState } from 'react';
import { LineEditor } from '../editor/LineEditor';
import type { Line } from '../editor/lines';
import { flushAll, registerFlush } from './flush';
import { dismissLink, findRewriteOf, linkRewrite, loadLines, saveLines, useEntriesStamp, useSettings, type LogRef } from '../data/repo';
import { sourceLabel } from '../data/openItems';
import { t } from '../i18n/en';

const SAVE_DELAY = 400;
/** Remote changes wait until the user has stopped typing for this long. */
const TYPING_PAUSE = 2500;

interface Props {
  log: LogRef;
  slot?: string;
  autoFocus?: boolean;
  compact?: boolean;
  label?: string;
}

export function PageEditor({ log, slot = '', autoFocus, compact, label }: Props) {
  const [initial, setInitial] = useState<Line[] | null>(null);
  const settings = useSettings();
  const { eventStates } = settings;
  const pending = useRef<Line[] | null>(null);
  const timer = useRef(0);
  const logRef = useRef(log);
  logRef.current = log;
  const focusAt = useRef<((lineId?: string) => void) | null>(null);
  const area = useRef<HTMLDivElement>(null);
  const shown = useRef<Line[] | null>(null);
  /** What this editor last loaded or saved: the base for "what did I change". */
  const base = useRef<Line[]>([]);
  const [version, setVersion] = useState(0);
  const lastInput = useRef(0);
  const stamp = useEntriesStamp(log.id, slot);

  // Saves only what this editor changed since its base, then moves the base.
  const save = (lines: Line[]) => {
    const from = base.current;
    base.current = lines;
    return saveLines(logRef.current, slot, lines, from);
  };

  useEffect(() => {
    let alive = true;
    void loadLines(log.id, slot).then((lines) => {
      if (!alive) return;
      shown.current = lines;
      base.current = lines;
      setInitial(lines);
    });
    return () => {
      alive = false;
    };
  }, [log.id, slot]);

  useEffect(() => {
    const flush = async () => {
      window.clearTimeout(timer.current);
      const lines = pending.current;
      pending.current = null;
      if (lines) await save(lines);
    };
    const unregister = registerFlush(flush);
    const onHide = () => document.visibilityState === 'hidden' && flush();
    window.addEventListener('pagehide', flush);
    document.addEventListener('visibilitychange', onHide);
    return () => {
      window.removeEventListener('pagehide', flush);
      document.removeEventListener('visibilitychange', onHide);
      unregister();
      void flush();
    };
  }, [slot]);

  // Entries changed underneath (sync from the other device): reload, but
  // never while the user is typing here; wait for a short pause instead.
  // Our own saves reload to the same lines and change nothing.
  const refresh = useRef<() => void>(() => {});
  refresh.current = () => {
    if (!shown.current) return;
    const idle = Date.now() - lastInput.current;
    if (pending.current || idle < TYPING_PAUSE) {
      window.setTimeout(() => refresh.current(), TYPING_PAUSE - Math.min(idle, TYPING_PAUSE) + 50);
      return;
    }
    void loadLines(log.id, slot).then((lines) => {
      if (pending.current || sameLines(lines, shown.current)) return;
      const hadFocus = !!area.current?.contains(document.activeElement);
      shown.current = lines;
      base.current = lines;
      setInitial(lines);
      setVersion((v) => v + 1);
      if (hadFocus) requestAnimationFrame(() => focusAt.current?.());
    });
  };
  useEffect(() => {
    if (stamp !== undefined) refresh.current();
  }, [stamp]);

  if (!initial) return <div className={`editor-area${compact ? ' compact' : ''}`} />;

  return (
    // The whole free area around the lines is a tap target: a tap below the
    // text puts the caret at the end (the first line of an empty page); a tap
    // in a line's margin puts it at the end of that line.
    <div
      ref={area}
      className={`editor-area${compact ? ' compact' : ''}`}
      onClick={(e) => {
        const target = e.target as Element;
        if (target.closest('.line-text, .bullet, .chevron')) return;
        focusAt.current?.(target.closest<HTMLElement>('.line')?.dataset.id);
      }}
    >
      <LineEditor
        key={version}
        initial={initial}
        autoFocus={autoFocus}
        className={compact ? 'compact' : ''}
        label={label}
        eventStates={eventStates}
        focusRef={focusAt}
        reverseSwipes={settings.reverseSwipes}
        findRewrite={async (line) => {
          const found = await findRewriteOf(line.id, line.text, log.id, settings);
          if (!found) return null;
          const { item, collectionTitle } = found;
          const origin = sourceLabel(item.source, item.entry.slot, collectionTitle);
          const plain = item.entry.text.replace(/\s*due:\d{4}-\d{2}-\d{2}/g, '').trim();
          const short = plain.length > 48 ? `${plain.slice(0, 46)}…` : plain;
          return { sourceId: item.entry.id, text: t.link.prompt(short, origin) };
        }}
        onLinkAnswer={(lineId, sourceId, link) => {
          if (link) void flushAll().then(() => linkRewrite(sourceId, lineId));
          else dismissLink(lineId, sourceId);
        }}
        onChange={(lines) => {
          shown.current = lines;
          lastInput.current = Date.now();
          pending.current = lines;
          window.clearTimeout(timer.current);
          timer.current = window.setTimeout(() => {
            pending.current = null;
            void save(lines);
          }, SAVE_DELAY);
        }}
      />
    </div>
  );
}

function sameLines(a: Line[], b: Line[] | null) {
  if (!b || a.length !== b.length) return false;
  return a.every((l, i) => {
    const o = b[i];
    return (
      l.id === o.id &&
      l.text === o.text &&
      l.type === o.type &&
      l.state === o.state &&
      l.indent === o.indent &&
      l.collapsed === o.collapsed &&
      !!l.priority === !!o.priority &&
      !!l.inspiration === !!o.inspiration &&
      !!l.explore === !!o.explore
    );
  });
}
