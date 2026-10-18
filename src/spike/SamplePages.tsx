// Sample Month and Day pages, only to test real-URL navigation, back gestures
// and scroll restoration. The real layouts come in Phase 1.
import { useEffect } from 'react';
import { t } from '../i18n/en';
import { navigate } from '../router';

const monthLabel = new Intl.DateTimeFormat('en', { month: 'long' });
const weekdayNarrow = new Intl.DateTimeFormat('en', { weekday: 'narrow' });
const weekdayLong = new Intl.DateTimeFormat('en', { weekday: 'long' });
const dayTitle = new Intl.DateTimeFormat('en', { weekday: 'short', month: 'short', day: 'numeric' });

function parseYm(ym: string) {
  const [y, m] = ym.split('-').map(Number);
  return { y, m };
}

export function SampleMonth({ ym }: { ym: string }) {
  const { y, m } = parseYm(ym);
  const daysInMonth = new Date(y, m, 0).getDate();
  const today = new Date();
  useEffect(() => {
    // Highlight the day we came back from, if any.
    const from = sessionStorage.getItem('spike.fromDay');
    if (!from) return;
    sessionStorage.removeItem('spike.fromDay');
    document.getElementById(`day-${from}`)?.classList.add('flash');
  }, []);
  return (
    <main className="page">
      <button className="link" onClick={() => navigate('/check')}>
        ‹ {t.routes.backToChecks}
      </button>
      <p className="eyebrow">{monthLabel.format(new Date(y, m - 1, 1)).toUpperCase()}</p>
      <h1>{t.routes.month}</h1>
      <ol className="month">
        {Array.from({ length: daysInMonth }, (_, i) => {
          const d = new Date(y, m - 1, i + 1);
          const iso = `${ym}-${String(i + 1).padStart(2, '0')}`;
          const isToday = d.toDateString() === today.toDateString();
          const weekend = d.getDay() === 0 || d.getDay() === 6;
          const newWeek = d.getDay() === 1 && i > 0;
          return (
            <li key={iso} id={`day-${iso}`} className={`day${newWeek ? ' week-start' : ''}${weekend ? ' weekend' : ''}${isToday ? ' today' : ''}`}>
              <button className="day-num" onClick={() => navigate(`/day/${iso}`)}>
                {i + 1}
              </button>
              <span className="day-initial" aria-label={weekdayLong.format(d)}>
                {weekdayNarrow.format(d)}
              </span>
              <span className="day-text" />
            </li>
          );
        })}
      </ol>
    </main>
  );
}

export function SampleDay({ iso }: { iso: string }) {
  const d = new Date(`${iso}T12:00:00`);
  return (
    <main className="page">
      <button
        className="link"
        onClick={() => {
          sessionStorage.setItem('spike.fromDay', iso);
          history.back();
        }}
      >
        ‹ {t.routes.month}
      </button>
      <h1>{dayTitle.format(d)}</h1>
      <p className="lede">{t.checks.back.how}</p>
    </main>
  );
}
