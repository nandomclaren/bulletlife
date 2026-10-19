// The Open items panel (CLAUDE.md 4): everything that is loose, grouped by
// the page it came from, oldest first. It shows and asks; the only writes are
// single-entry state marks and "I wrote it there". No bulk actions, no copy,
// no drag to a page: rewriting by hand is the point.
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { entriesToLines } from '../data/convert';
import { ageLabel, groupItems, groupLabel, sourceLabel, sourcePath, stateful, withKept, type Mark, type OpenItem } from '../data/openItems';
import { confirmPlaced, markEntry, useCollections, useSettings } from '../data/repo';
import type { Entry } from '../data/types';
import { BulletMenu, type MenuActions } from '../editor/BulletMenu';
import { attachGutter } from '../editor/gutter';
import { nextState, type Line } from '../editor/lines';
import { buildGutter, fillText, lineClass } from '../editor/render';
import { attachSwipe } from '../editor/swipe';
import { t } from '../i18n/en';
import { flashEntry } from '../pages/nav';
import { navigate } from '../router';
import { MarkToast } from './MarkToast';
import { closePanel, setPanelFilter, usePanel } from './panelStore';
import { useOpenItems, useToday } from './useOpenItems';

const DOCKED = '(min-width: 1000px)';

export function OpenItemsPanel() {
  const panel = usePanel();
  // Keep it mounted for the closing animation.
  const [shown, setShown] = useState(panel.open);
  useEffect(() => {
    if (panel.open) setShown(true);
    else {
      const id = window.setTimeout(() => setShown(false), 200);
      return () => window.clearTimeout(id);
    }
  }, [panel.open]);
  if (!shown) return null;
  return <Panel closing={!panel.open} filter={panel.filter} />;
}

function useDocked() {
  const [docked, setDocked] = useState(() => matchMedia(DOCKED).matches);
  useEffect(() => {
    const mq = matchMedia(DOCKED);
    const on = () => setDocked(mq.matches);
    mq.addEventListener('change', on);
    return () => mq.removeEventListener('change', on);
  }, []);
  return docked;
}

function Panel({ closing, filter }: { closing: boolean; filter: 'all' | 'today' }) {
  const data = useOpenItems(filter);
  const settings = useSettings();
  const collections = useCollections();
  const today = useToday();
  const docked = useDocked();
  const list = useRef<HTMLDivElement>(null);
  const sheet = useRef<HTMLElement>(null);
  const [kept, setKept] = useState(() => new Map<string, OpenItem>());
  const [menu, setMenu] = useState<{ id: string; anchor: DOMRect } | null>(null);
  const [marked, setMarked] = useState<{
    n: number;
    mark: Mark | null;
    entry: Entry;
  } | null>(null);

  // Docked beside the page on a wide screen: the page stays visible and editable.
  useLayoutEffect(() => {
    const root = document.documentElement;
    root.classList.toggle('panel-docked', docked && !closing);
    return () => root.classList.remove('panel-docked');
  }, [docked, closing]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && !menu && closePanel();
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [menu]);

  const byId = useMemo(() => new Map((data?.entries ?? []).map((e) => [e.id, e])), [data]);
  const items = useMemo(() => (data ? withKept(data.items, kept, byId) : []), [data, kept, byId]);
  const groups = useMemo(() => groupItems(items), [items]);
  const titles = useMemo(() => new Map((collections ?? []).map((c) => [c.id, c.title])), [collections]);

  const itemsRef = useRef(items);
  itemsRef.current = items;
  const settingsRef = useRef(settings);
  settingsRef.current = settings;
  const keep = useCallback((id: string) => {
    const item = itemsRef.current.find((i) => i.entry.id === id);
    if (item) setKept((k) => (k.has(id) ? k : new Map(k).set(id, item)));
  }, []);
  const entryOf = (id: string) => itemsRef.current.find((i) => i.entry.id === id)?.entry;

  const mark = useCallback(
    (id: string, m: Mark) => {
      const e = entryOf(id);
      if (!e || !stateful(e, settingsRef.current.eventStates)) return;
      keep(id);
      const next = e.state === m ? 'open' : m;
      void markEntry(id, next);
      setMarked((x) => ({
        n: (x?.n ?? 0) + 1,
        mark: next === 'open' ? null : m,
        entry: e,
      }));
    },
    [keep],
  );

  // Same gestures as on the page: tap the bullet, long press / right click for the menu, swipe for > and <.
  useEffect(() => {
    const root = list.current;
    if (!root) return;
    const detachGutter = attachGutter(root, {
      bullet: (id) => {
        const e = entryOf(id);
        if (!e || !stateful(e, settingsRef.current.eventStates)) return;
        keep(id);
        void markEntry(id, nextState(e.state));
      },
      chevron: () => {},
      menu: (id, anchor) => setMenu({ id, anchor }),
    });
    const detachSwipe = attachSwipe(root, {
      canSwipe: (id) => {
        const e = entryOf(id);
        return !!e && stateful(e, settingsRef.current.eventStates);
      },
      current: (id) => entryOf(id)?.state,
      commit: mark,
      reverse: () => settingsRef.current.reverseSwipes,
    });
    return () => {
      detachGutter();
      detachSwipe();
    };
  }, [keep, mark, today, data !== undefined]); // eslint-disable-line react-hooks/exhaustive-deps

  // iPhone: swipe the sheet to the right (outside the rows) to close it.
  useEffect(() => {
    const el = sheet.current;
    if (!el || docked) return;
    let start: { x: number; y: number; id: number } | null = null;
    const down = (e: PointerEvent) => {
      if (e.pointerType !== 'touch' || (e.target as Element).closest('.open-row, button')) return;
      start = { x: e.clientX, y: e.clientY, id: e.pointerId };
    };
    const move = (e: PointerEvent) => {
      if (!start || e.pointerId !== start.id) return;
      const dx = e.clientX - start.x;
      if (Math.abs(e.clientY - start.y) > Math.abs(dx)) return void ((start = null), el.style.removeProperty('transform'));
      if (dx > 0) el.style.transform = `translateX(${dx}px)`;
    };
    const up = (e: PointerEvent) => {
      if (!start || e.pointerId !== start.id) return;
      const dx = e.clientX - start.x;
      start = null;
      el.style.removeProperty('transform');
      if (dx > 80) closePanel();
    };
    el.addEventListener('pointerdown', down);
    el.addEventListener('pointermove', move);
    el.addEventListener('pointerup', up);
    el.addEventListener('pointercancel', up);
    return () => {
      el.removeEventListener('pointerdown', down);
      el.removeEventListener('pointermove', move);
      el.removeEventListener('pointerup', up);
      el.removeEventListener('pointercancel', up);
    };
  }, [docked]);

  const open = (item: OpenItem) => {
    navigate(sourcePath(item.source));
    flashEntry(item.entry.id);
    if (!docked) closePanel();
  };

  const menuEntry = menu ? entryOf(menu.id) : undefined;
  const menuActions = useMemo<MenuActions | null>(
    () =>
      menu && {
        patch: (p) => {
          if (!p.state) return;
          const e = entryOf(menu.id);
          if (p.state === 'migrated' || p.state === 'scheduled') {
            if (e?.state !== p.state) mark(menu.id, p.state);
          } else {
            keep(menu.id);
            void markEntry(menu.id, p.state);
          }
        },
        shift: () => {},
        remove: () => {},
        close: () => setMenu(null),
      },
    [menu, keep, mark], // eslint-disable-line react-hooks/exhaustive-deps
  );
  const hideMark = useCallback(() => setMarked(null), []);

  return (
    <>
      {!docked && <div className={`open-backdrop${closing ? ' closing' : ''}`} onClick={closePanel} />}
      <aside ref={sheet} className={`open-panel${docked ? ' docked' : ' sheet'}${closing ? ' closing' : ''}`} aria-label={t.open.title}>
        <header className="open-head">
          <h2>{filter === 'today' ? t.open.today : t.open.title}</h2>
          <button className="icon-btn-quiet open-close" aria-label={t.open.close} onClick={closePanel}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden>
              <path d="M6 6l12 12M18 6L6 18" />
            </svg>
          </button>
        </header>
        <div className="open-body">
          {data && !items.length && <p className="open-empty">{filter === 'today' ? t.open.emptyToday : t.open.empty}</p>}
          <div ref={list} className="editor open-list">
            {groups.map((g) => {
              const age = g.id === 'due' || g.source.kind === 'collection' ? '' : ageLabel(g.source.end, today);
              return (
                <section key={g.id} className="open-group">
                  <h3 className="open-group-title">
                    {groupLabel(g, titles.get(g.source.logId))}
                    {age && <span className="open-age"> · {age}</span>}
                  </h3>
                  {g.items.map((item) => (
                    <Row
                      key={item.entry.id}
                      item={item}
                      origin={g.id === 'due' ? sourceLabel(item.source, item.entry.slot, titles.get(item.source.logId)) : undefined}
                      onOpen={() => open(item)}
                      onWrote={() => {
                        keep(item.entry.id);
                        void confirmPlaced(item.entry.id);
                      }}
                    />
                  ))}
                </section>
              );
            })}
          </div>
          {filter === 'today' && (
            <button className="link open-all" onClick={() => setPanelFilter('all')}>
              {t.open.showAll}
            </button>
          )}
        </div>
      </aside>
      {menu && menuEntry && menuActions && (
        <BulletMenu line={toLine(menuEntry)} anchor={menu.anchor} eventStates={settings.eventStates} actions={menuActions} statesOnly />
      )}
      {marked && <MarkToast key={marked.n} mark={marked.mark} onUndo={() => void markEntry(marked.entry.id, marked.entry.state)} onDone={hideMark} />}
    </>
  );
}

function Row({
  item,
  origin,
  onOpen,
  onWrote,
}: {
  item: OpenItem;
  /** In the Due group: the page the item lives on. */
  origin?: string;
  onOpen: () => void;
  onWrote: () => void;
}) {
  const line = toLine(item.entry);
  const { state } = item.entry;
  const unplaced = (state === 'migrated' || state === 'scheduled') && item.entry.placement?.status === 'pending';
  const placed = item.entry.placement?.status === 'placed';
  return (
    <div className={`${lineClass(line, { color: line.type, hasChildren: false, hidden: false })} open-row`} data-id={line.id}>
      <span className="gutter-host" ref={(el) => el?.replaceChildren(buildGutter(document, line, false))} />
      <div className="line-text">
        <button
          className="open-text"
          onClick={onOpen}
          ref={(el) => {
            if (el) fillText(el, line.text || '…');
          }}
        />
        {origin && <span className="open-meta">{origin}</span>}
        {unplaced && (
          <span className="open-meta">
            {t.open.notWritten[state as Mark]}
            <button className="open-wrote" onClick={onWrote}>
              {t.open.wroteIt}
            </button>
          </span>
        )}
        {placed && <span className="open-meta">✓ {t.open.wroteIt}</span>}
      </div>
    </div>
  );
}

function toLine(e: Entry): Line {
  return { ...entriesToLines([{ ...e, parentId: null }])[0], collapsed: false };
}
