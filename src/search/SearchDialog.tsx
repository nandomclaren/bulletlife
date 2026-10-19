// Global search (CLAUDE.md 5, ⌘K): type, see every matching entry with the
// page it lives on, open it. Read-only: search never changes anything.
import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { sourceLabel, sourceOf, sourcePath } from '../data/openItems';
import { useAllEntries, useCollections, useSettings } from '../data/repo';
import { searchCollections, searchEntries } from '../data/search';
import type { Entry, Log } from '../data/types';
import type { Weekday } from '../dates';
import { DUE_TOKEN, dueLabel } from '../editor/due';
import { glyph } from '../editor/lines';
import { dueView } from '../editor/render';
import { todayIso } from '../dates';
import { t } from '../i18n/en';
import { flashEntry } from '../pages/nav';
import { navigate } from '../router';
import { closeSearch, useSearchOpen } from './store';

export function SearchDialog() {
  return useSearchOpen() ? <Dialog /> : null;
}

type Result = { kind: 'entry'; entry: Entry; ranges: Array<[number, number]> } | { kind: 'collection'; log: Log; ranges: Array<[number, number]> };

function Dialog() {
  const entries = useAllEntries();
  const collections = useCollections();
  const settings = useSettings();
  const [query, setQuery] = useState('');
  const [active, setActive] = useState(0);
  const input = useRef<HTMLInputElement>(null);
  const list = useRef<HTMLUListElement>(null);
  const titles = useMemo(() => new Map((collections ?? []).map((c) => [c.id, c.title])), [collections]);

  const results = useMemo<Result[]>(() => {
    const cols = searchCollections(collections ?? [], query).map((h) => ({ kind: 'collection' as const, log: h.item, ranges: h.ranges }));
    const hits = searchEntries(entries ?? [], query).map((h) => ({ kind: 'entry' as const, entry: h.item, ranges: h.ranges }));
    return [...cols, ...hits];
  }, [entries, collections, query]);

  useEffect(() => setActive(0), [query]);

  // Focus moves into the dialog and back where it was when it closes.
  useEffect(() => {
    const before = document.activeElement as HTMLElement | null;
    input.current?.focus();
    return () => before?.focus?.({ preventScroll: true });
  }, []);

  useEffect(() => {
    list.current?.querySelector('[aria-selected="true"]')?.scrollIntoView({ block: 'nearest' });
  }, [active]);

  const open = (r: Result) => {
    closeSearch();
    if (r.kind === 'collection') return navigate(`/collection/${encodeURIComponent(r.log.id)}`);
    navigate(sourcePath(sourceOf(r.entry.logId, settings.firstDayOfWeek as Weekday)));
    flashEntry(r.entry.id);
  };

  return createPortal(
    <div className="search-backdrop" onMouseDown={(e) => e.target === e.currentTarget && closeSearch()}>
      <div className="search-dialog" role="dialog" aria-modal="true" aria-label={t.search.title}>
        <div className="search-field">
          <SearchIcon />
          <input
            ref={input}
            type="search"
            role="combobox"
            aria-expanded={results.length > 0}
            aria-controls="search-results"
            aria-activedescendant={results.length ? `search-${active}` : undefined}
            placeholder={t.search.placeholder}
            value={query}
            enterKeyHint="search"
            autoCapitalize="off"
            autoCorrect="off"
            spellCheck={false}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Escape') closeSearch();
              else if (e.key === 'ArrowDown') (e.preventDefault(), setActive((a) => Math.min(results.length - 1, a + 1)));
              else if (e.key === 'ArrowUp') (e.preventDefault(), setActive((a) => Math.max(0, a - 1)));
              else if (e.key === 'Enter' && results[active]) (e.preventDefault(), open(results[active]));
            }}
          />
          <button className="search-cancel" onClick={closeSearch}>
            {t.search.cancel}
          </button>
        </div>
        {query.trim() && (
          <ul id="search-results" ref={list} className="search-results" role="listbox" aria-label={t.search.title}>
            {results.length === 0 && <li className="search-empty">{t.search.none}</li>}
            {results.map((r, i) => (
              <li
                key={r.kind === 'entry' ? r.entry.id : r.log.id}
                id={`search-${i}`}
                role="option"
                aria-selected={i === active}
                className="search-hit"
                onMouseMove={() => setActive(i)}
                onClick={() => open(r)}
              >
                {r.kind === 'collection' ? (
                  <>
                    <span className="search-glyph">#</span>
                    <span className="search-text">{highlight(r.log.title, r.ranges)}</span>
                    <span className="search-origin">{t.index.collections}</span>
                  </>
                ) : (
                  <>
                    <span className={`search-glyph g-${r.entry.type} gs-${r.entry.state}`} aria-hidden>
                      {r.entry.type === 'text' || r.entry.type === 'heading' ? '' : glyph(r.entry.type, r.entry.state, true)}
                    </span>
                    <span className={`search-text${r.entry.state === 'cancelled' ? ' is-cancelled' : ''}`}>{highlight(r.entry.text, r.ranges)}</span>
                    <span className="search-origin">
                      {sourceLabel(sourceOf(r.entry.logId, settings.firstDayOfWeek as Weekday), r.entry.slot, titles.get(r.entry.logId))}
                    </span>
                  </>
                )}
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>,
    document.body,
  );
}

/** Text with the matched words marked, and stored dates shown as their short label. */
function highlight(text: string, ranges: Array<[number, number]>): ReactNode[] {
  const out: ReactNode[] = [];
  let at = 0;
  const plain = (s: string, key: string) => {
    let last = 0;
    for (const m of s.matchAll(DUE_TOKEN)) {
      if (m.index > last) out.push(s.slice(last, m.index));
      out.push(
        <span key={`${key}-${m.index}`} className="search-due">
          {dueLabel(m[1], todayIso(), dueView.order)}
        </span>,
      );
      last = m.index + m[0].length;
    }
    if (last < s.length) out.push(s.slice(last));
  };
  ranges.forEach(([a, b], i) => {
    if (a < at) return;
    plain(text.slice(at, a), `p${i}`);
    out.push(<mark key={`m${i}`}>{text.slice(a, b)}</mark>);
    at = b;
  });
  plain(text.slice(at), 'end');
  return out;
}

export function SearchIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" aria-hidden>
      <circle cx="10.5" cy="10.5" r="6.5" />
      <path d="M15.5 15.5 20 20" />
    </svg>
  );
}
