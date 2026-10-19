// Index (CLAUDE.md 3.1): always on. The current Year and the collections.
import { usePane } from './pane';
import { useState } from 'react';
import { todayIso, yearOf, type Weekday } from '../dates';
import { createCollection, setCollectionPinned, useCollections, useSettings } from '../data/repo';
import type { Log } from '../data/types';
import { openSearch } from '../search/store';
import { SearchIcon } from '../search/SearchDialog';
import { t } from '../i18n/en';
import { finestLevel, pathFor } from './nav';
import { CalendarIcon } from './TimeHeader';

export function IndexPage() {
  const { navigate, setAnchor, back } = usePane();
  const collections = useCollections();
  const settings = useSettings();
  const firstDay = settings.firstDayOfWeek as Weekday;
  const [naming, setNaming] = useState(false);
  const [name, setName] = useState('');
  const year = yearOf(todayIso());
  const pinned = (collections ?? []).filter((c) => c.pinned);
  const others = (collections ?? []).filter((c) => !c.pinned);

  const goTo = (iso: string) => {
    setAnchor(iso);
    navigate(pathFor(finestLevel(settings), iso, firstDay));
  };

  return (
    <main className="page page-index">
      {/* Same header as the time pages: Today and the calendar sit in the same
          place. The ‹ › slots are kept empty (there is no previous Index). */}
      <header className="time-header">
        <button className="crumb index-back" onClick={back}>
          ‹ {t.nav.back}
        </button>
        <div className="crumbs" />
        <div className="header-actions">
          <button className="icon-btn-quiet" aria-label={t.index.search} onClick={openSearch}>
            <SearchIcon />
          </button>
          <button className="today-btn" onClick={() => goTo(todayIso())}>
            {t.nav.today}
          </button>
          <span className="icon-btn-quiet" aria-hidden />
          <label className="icon-btn-quiet date-pick" aria-label={t.nav.pickDate}>
            <CalendarIcon />
            <input type="date" value={todayIso()} onChange={(e) => e.currentTarget.value && goTo(e.currentTarget.value)} />
          </label>
        </div>
      </header>

      <h1>{t.index.title}</h1>

      {/* The Year (future log) is always on: the current one is always listed,
          even before anything is written in it. Nothing is stored for this.
          Other years: ‹ › on the Year page, or the calendar. */}
      <ul className="index-list index-pinned">
        <li>
          <button className="index-link" onClick={() => (setAnchor(todayIso()), navigate(`/year/${year}`))}>
            <span className="index-kind">{t.index.kinds.future}</span>
            {year}
          </button>
        </li>
        {pinned.map((c) => (
          <CollectionRow key={c.id} c={c} />
        ))}
      </ul>

      <section className="index-section">
        <h2 className="section-title">{t.index.collections}</h2>
        {collections?.length === 0 && !naming && <p className="muted">{t.index.noCollections}</p>}
        <ul className="index-list">
          {others.map((c) => (
            <CollectionRow key={c.id} c={c} />
          ))}
        </ul>
        {naming ? (
          <form
            className="row new-collection"
            onSubmit={async (e) => {
              e.preventDefault();
              const title = name.trim();
              if (!title) return;
              const id = await createCollection(title);
              navigate(`/collection/${encodeURIComponent(id)}`);
            }}
          >
            <input
              className="field"
              autoFocus
              placeholder={t.index.namePlaceholder}
              value={name}
              onChange={(e) => setName(e.target.value)}
              enterKeyHint="done"
            />
            <button className="btn" disabled={!name.trim()}>
              {t.index.create}
            </button>
            <button type="button" className="btn btn-quiet" onClick={() => (setNaming(false), setName(''))}>
              {t.index.cancel}
            </button>
          </form>
        ) : (
          <button className="link add-link" onClick={() => setNaming(true)}>
            + {t.index.newCollection}
          </button>
        )}
      </section>

      <footer className="page-footer index-footer">
        <button className="link" onClick={() => navigate('/settings')}>
          {t.index.settings}
        </button>
      </footer>
    </main>
  );
}

function CollectionRow({ c }: { c: Log }) {
  const { navigate } = usePane();
  const name = c.title || t.index.untitled;
  return (
    <li className="index-row">
      <button className="index-link" onClick={() => navigate(`/collection/${encodeURIComponent(c.id)}`)}>
        {c.pinned && <span className="index-kind">{t.index.pinned}</span>}
        {name}
      </button>
      <button
        className={`icon-btn-quiet pin-btn${c.pinned ? ' is-pinned' : ''}`}
        aria-label={c.pinned ? t.index.unpin(name) : t.index.pin(name)}
        aria-pressed={!!c.pinned}
        onClick={() => void setCollectionPinned(c.id, !c.pinned)}
      >
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinejoin="round" aria-hidden>
          <path d="M9 3h6l-1 6 4 4H6l4-4-1-6ZM12 13v8" strokeLinecap="round" />
        </svg>
      </button>
    </li>
  );
}
