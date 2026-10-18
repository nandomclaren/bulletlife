import { fmt, monthOf, todayIso, weekKey, yearOf, type Weekday } from '../dates';
import { useSettings, useSync } from '../data/repo';
import { t } from '../i18n/en';
import { navigate } from '../router';
import { activeLevels, goUp, pathFor, setAnchor, stepKey, type Level } from './nav';

const ORDER: Level[] = ['year', 'month', 'week', 'day'];

interface Props {
  level: Level;
  /** Period key of this page: '2026', '2026-10', '2026-W43' or '2026-10-18'. */
  periodKey: string;
  /** The anchor day this page is showing. */
  anchor: string;
}

/** Breadcrumb (every level is one tap away), ‹ ›, Today and a date picker. */
export function TimeHeader({ level, periodKey, anchor }: Props) {
  const settings = useSettings();
  const sync = useSync();
  // Quiet: nothing when in sync or not signed in; a small ring only when offline or paused.
  const attention = sync.kind === 'offline' || sync.kind === 'error' ? sync.kind : null;
  const firstDay = settings.firstDayOfWeek as Weekday;
  const levels = activeLevels(settings);


  const label = (l: Level) => {
    switch (l) {
      case 'year':
        return yearOf(anchor);
      case 'month':
        return fmt(anchor, { month: 'short' });
      case 'week':
        return `${t.nav.weekShort} ${Number(weekKey(anchor, firstDay).split('-W')[1])}`;
      case 'day':
        return fmt(anchor, { day: 'numeric' });
    }
  };

  const go = (l: Level) => {
    if (l === level) return;
    const path = pathFor(l, anchor, firstDay);
    // Going up: the destination scrolls to where we came from.
    if (ORDER.indexOf(l) < ORDER.indexOf(level)) goUp(path, fromId(level, periodKey, l, anchor));
    else navigate(path);
  };

  const step = (n: number) => navigate(`/${level}/${stepKey(level, periodKey, n, firstDay)}`);

  return (
    <header className="time-header">
      <button
        className="icon-btn-quiet index-btn"
        aria-label={attention ? `${t.nav.index}, ${t.sync.indicator[attention]}` : t.nav.index}
        onClick={() => navigate('/index')}
      >
        <IndexIcon />
        {attention && <span className={`sync-badge sync-${attention}`} aria-hidden />}
      </button>
      <nav className="crumbs" aria-label={t.nav.path}>
        {levels.map((l, i) => (
          <span key={l} className="crumb-wrap">
            {i > 0 && <span className="crumb-sep" aria-hidden>›</span>}
            <button
              className={`crumb${l === level ? ' is-current' : ''}`}
              aria-current={l === level ? 'page' : undefined}
              onClick={() => go(l)}
            >
              {label(l)}
            </button>
          </span>
        ))}
      </nav>
      <div className="header-actions">
        <button className="icon-btn-quiet" aria-label={t.nav.previous} onClick={() => step(-1)}>
          ‹
        </button>
        <button
          className="today-btn"
          onClick={() => {
            const today = todayIso();
            setAnchor(today);
            navigate(pathFor(level, today, firstDay));
          }}
        >
          {t.nav.today}
        </button>
        <button className="icon-btn-quiet" aria-label={t.nav.next} onClick={() => step(1)}>
          ›
        </button>
        <label className="icon-btn-quiet date-pick" aria-label={t.nav.pickDate}>
          <CalendarIcon />
          <input
            type="date"
            value={anchor}
            onChange={(e) => {
              const iso = e.currentTarget.value;
              if (!iso) return;
              setAnchor(iso);
              navigate(pathFor(level, iso, firstDay));
            }}
          />
        </label>
      </div>
    </header>
  );
}

/** Element id the parent page should scroll to when we go up from here. */
function fromId(level: Level, periodKey: string, target: Level, anchor: string): string {
  if (target === 'year') return `year-month-${monthOf(anchor)}`;
  if (target === 'month' && level === 'day') return `month-day-${periodKey}`;
  if (target === 'month' && level === 'week') return `month-day-${anchor}`;
  return '';
}

export function CalendarIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" aria-hidden>
      <rect x="3.5" y="5" width="17" height="15.5" rx="2.5" />
      <path d="M3.5 9.5h17M8 3v4M16 3v4" strokeLinecap="round" />
    </svg>
  );
}


/** Quiet link at the foot of time pages until the Index menu exists. */
export function PageFooter() {
  return (
    <footer className="page-footer">
      <button className="link" onClick={() => navigate('/settings')}>
        {t.nav.settings}
      </button>
    </footer>
  );
}

function IndexIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" aria-hidden>
      <path d="M8 6.5h12M8 12h12M8 17.5h12" />
      <circle cx="4" cy="6.5" r="0.9" fill="currentColor" />
      <circle cx="4" cy="12" r="0.9" fill="currentColor" />
      <circle cx="4" cy="17.5" r="0.9" fill="currentColor" />
    </svg>
  );
}
