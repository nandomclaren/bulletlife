// Index (CLAUDE.md 3.1): always on, derived from the logs, never stored.
import { useState } from 'react';
import { fmt, weekKey, type Weekday } from '../dates';
import { createCollection, useCollections, useSettings, useWrittenTimeLogs } from '../data/repo';
import type { Log } from '../data/types';
import { t } from '../i18n/en';
import { navigate } from '../router';
import { setAnchor } from './nav';

export function IndexPage() {
  const collections = useCollections();
  const logs = useWrittenTimeLogs();
  const settings = useSettings();
  const [naming, setNaming] = useState(false);
  const [name, setName] = useState('');

  const years = groupByYear(logs ?? []);

  return (
    <main className="page page-index">
      <button className="link" onClick={() => (history.length > 1 ? history.back() : navigate('/'))}>
        ‹ {t.nav.back}
      </button>
      <h1>{t.index.title}</h1>

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

      <section className="index-section">
        <h2 className="section-title">{t.index.logs}</h2>
        {logs?.length === 0 && <p className="muted">{t.index.noLogs}</p>}
        {years.map(([year, items]) => (
          <div key={year} className="index-year">
            <h3 className="index-year-title">{year}</h3>
            <ul className="index-list">
              {items.map((l) => (
                <li key={l.id}>
                  <button className="index-link" onClick={() => open(l, settings.firstDayOfWeek as Weekday)}>
                    <span className="index-kind">{t.index.kinds[l.kind as Exclude<Log['kind'], 'collection'>]}</span>
                    {describe(l)}
                  </button>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </section>

      <footer className="page-footer">
        <button className="link" onClick={() => navigate('/settings')}>
          {t.index.settings}
        </button>
      </footer>
    </main>
  );
}

function groupByYear(logs: Log[]): Array<[string, Log[]]> {
  const map = new Map<string, Log[]>();
  for (const l of logs) {
    const y = (l.periodStart ?? '').slice(0, 4);
    if (!map.has(y)) map.set(y, []);
    map.get(y)!.push(l);
  }
  return [...map.entries()];
}

function describe(l: Log): string {
  const start = l.periodStart!;
  switch (l.kind) {
    case 'future':
      return start.slice(0, 4);
    case 'monthly':
      return fmt(start, { month: 'long' });
    case 'weekly':
      return `${l.title} · ${fmt(start, { month: 'short', day: 'numeric' })} – ${fmt(l.periodEnd!, { month: 'short', day: 'numeric' })}`;
    default:
      return fmt(start, { weekday: 'short', month: 'short', day: 'numeric' });
  }
}

function open(l: Log, firstDay: Weekday) {
  const start = l.periodStart!;
  setAnchor(start);
  if (l.kind === 'future') navigate(`/year/${start.slice(0, 4)}`);
  else if (l.kind === 'monthly') navigate(`/month/${start.slice(0, 7)}`);
  else if (l.kind === 'weekly') navigate(`/week/${weekKey(start, firstDay)}`);
  else navigate(`/day/${start}`);
}
