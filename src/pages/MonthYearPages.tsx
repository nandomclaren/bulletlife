import { useEffect } from 'react';
import { addMonths, fmt, fromIso, monthDays, monthOf, todayIso, weekKey, type Weekday } from '../dates';
import { periodLog, useSettings } from '../data/repo';
import { t } from '../i18n/en';
import { navigate } from '../router';
import { anchorWithin, flash, setAnchor, takeFrom } from './nav';
import { PageEditor } from './PageEditor';
import { PageFooter, TimeHeader } from './TimeHeader';

/** Month: a fixed calendar rendered from the date (never stored) plus "Month tasks". */
export function MonthPage({ ym }: { ym: string }) {
  const settings = useSettings();
  const firstDay = settings.firstDayOfWeek as Weekday;
  const days = monthDays(ym);
  const anchor = anchorWithin(days[0], days[days.length - 1]);
  const log = periodLog('monthly', ym, firstDay);
  const today = todayIso();
  const isCurrent = monthOf(today) === ym;

  useEffect(() => {
    const from = takeFrom();
    if (from) flash(from);
  }, [ym]);

  const openDay = (iso: string) => {
    setAnchor(iso);
    if (settings.activeLogs.daily) navigate(`/day/${iso}`);
    else if (settings.activeLogs.weekly) navigate(`/week/${weekKey(iso, firstDay)}`);
  };

  return (
    <main className="page page-time page-month">
      <TimeHeader level="month" periodKey={ym} anchor={anchor} />
      <p className="eyebrow">{fmt(`${ym}-01`, { month: 'long' })}</p>
      <h1>{isCurrent ? t.pages.thisMonth : fmt(`${ym}-01`, { month: 'long', year: 'numeric' })}</h1>
      <div className="month-spread">
        <ol className="month-days">
          {days.map((iso, i) => {
            const d = fromIso(iso);
            const weekend = d.getDay() === 0 || d.getDay() === 6;
            const startsWeek = i > 0 && d.getDay() === firstDay;
            const wk = weekKey(iso, firstDay);
            return (
              <li key={iso} id={`month-day-${iso}`} className={`month-day${weekend ? ' weekend' : ''}${iso === today ? ' today' : ''}`}>
                {startsWeek && (
                  <div className="week-rule">
                    {settings.activeLogs.weekly && (
                      <button className="week-label" onClick={() => (setAnchor(iso), navigate(`/week/${wk}`))}>
                        {t.nav.weekShort} {Number(wk.split('-W')[1])}
                      </button>
                    )}
                  </div>
                )}
                <button
                  className="day-num"
                  aria-label={fmt(iso, { weekday: 'long', month: 'long', day: 'numeric' })}
                  onClick={() => openDay(iso)}
                  disabled={!settings.activeLogs.daily && !settings.activeLogs.weekly}
                >
                  <span className="n">{d.getDate()}</span>
                </button>
                <span className="day-initial" aria-hidden>
                  {fmt(iso, { weekday: 'narrow' })}
                </span>
                <div className="day-text">
                  <PageEditor key={`${log.id}/${iso}`} log={log} slot={iso} compact label={`${t.pages.dayRow} ${fmt(iso, { month: 'long', day: 'numeric' })}`} />
                </div>
              </li>
            );
          })}
        </ol>
        <section className="month-tasks">
          <h2 className="section-title">{t.pages.monthTasks}</h2>
          <PageEditor key={log.id} log={log} label={t.pages.monthTasks} />
        </section>
      </div>
      <PageFooter />
    </main>
  );
}

/** Year (future log): one page per calendar year, twelve generous month areas. */
export function YearPage({ year }: { year: string }) {
  const settings = useSettings();
  const firstDay = settings.firstDayOfWeek as Weekday;
  const anchor = anchorWithin(`${year}-01-01`, `${year}-12-31`);
  const log = periodLog('future', year, firstDay);
  const currentMonth = monthOf(todayIso());
  const months = Array.from({ length: 12 }, (_, i) => addMonths(`${year}-01`, i));

  useEffect(() => {
    const from = takeFrom();
    if (from) flash(from);
  }, [year]);

  return (
    <main className="page page-time page-year">
      <TimeHeader level="year" periodKey={year} anchor={anchor} />
      <h1>{year}</h1>
      {months.map((ym) => (
        <section key={ym} id={`year-month-${ym}`} className={`year-month${ym === currentMonth ? ' is-current' : ''}`}>
          <h2 className="year-month-title">
            <button
              onClick={() => {
                setAnchor(ym === currentMonth ? todayIso() : `${ym}-01`);
                navigate(settings.activeLogs.monthly ? `/month/${ym}` : `/week/${weekKey(`${ym}-01`, firstDay)}`);
              }}
            >
              {fmt(`${ym}-01`, { month: 'long' })}
            </button>
          </h2>
          <div className="year-month-area">
            <PageEditor key={`${log.id}/${ym}`} log={log} slot={ym} label={`${t.pages.monthArea} ${fmt(`${ym}-01`, { month: 'long' })}`} />
          </div>
        </section>
      ))}
      <PageFooter />
    </main>
  );
}
