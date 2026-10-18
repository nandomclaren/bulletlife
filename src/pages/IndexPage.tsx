// Index (CLAUDE.md 3.1): always on. The current Year and the collections.
import { useState } from 'react';
import { todayIso, yearOf, type Weekday } from '../dates';
import { createCollection, useCollections, useSettings } from '../data/repo';
import { t } from '../i18n/en';
import { navigate } from '../router';
import { finestLevel, pathFor, setAnchor } from './nav';
import { CalendarIcon } from './TimeHeader';

export function IndexPage() {
  const collections = useCollections();
  const settings = useSettings();
  const firstDay = settings.firstDayOfWeek as Weekday;
  const [naming, setNaming] = useState(false);
  const [name, setName] = useState('');
  const year = yearOf(todayIso());

  const goTo = (iso: string) => {
    setAnchor(iso);
    navigate(pathFor(finestLevel(settings), iso, firstDay));
  };

  return (
    <main className="page page-index">
      {/* Same header as the time pages: Today and the calendar sit in the same
          place. The ‹ › slots are kept empty (there is no previous Index). */}
      <header className="time-header">
        <button className="crumb index-back" onClick={() => (history.length > 1 ? history.back() : navigate('/'))}>
          ‹ {t.nav.back}
        </button>
        <div className="crumbs" />
        <div className="header-actions">
          <span className="icon-btn-quiet" aria-hidden />
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
      </ul>

      <section className="index-section">
        <h2 className="section-title">{t.index.collections}</h2>
        {collections?.length === 0 && !naming && <p className="muted">{t.index.noCollections}</p>}
        <ul className="index-list">
          {collections?.map((c) => (
            <li key={c.id}>
              <button className="index-link" onClick={() => navigate(`/collection/${encodeURIComponent(c.id)}`)}>
                {c.title || t.index.untitled}
              </button>
            </li>
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
