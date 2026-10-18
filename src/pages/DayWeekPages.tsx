import { useEffect } from 'react';
import { addDays, fmt, todayIso, weekKeyStart, type Weekday } from '../dates';
import { periodLog, useSettings } from '../data/repo';
import { t } from '../i18n/en';
import { anchorWithin, flash, setAnchor, takeFrom } from './nav';
import { PageEditor } from './PageEditor';
import { PageFooter, TimeHeader } from './TimeHeader';
// Week strip hidden at Fernando's request (felt like a digital note taker). Kept for later.
// import { WeekStrip } from './WeekStrip';

export function DayPage({ iso }: { iso: string }) {
  const settings = useSettings();
  const firstDay = settings.firstDayOfWeek as Weekday;
  setAnchor(iso);
  const log = periodLog('daily', iso, firstDay);
  const isToday = iso === todayIso();
  return (
    <main className="page page-time">
      <TimeHeader level="day" periodKey={iso} anchor={iso} />
      {/* <WeekStrip weekKey={weekKey(iso, firstDay)} firstDay={firstDay} selected={iso} /> */}
      <p className="eyebrow">{isToday ? t.pages.today : fmt(iso, { weekday: 'long' })}</p>
      <h1>{fmt(iso, isToday ? { weekday: 'long', month: 'short', day: 'numeric' } : { month: 'long', day: 'numeric', year: 'numeric' })}</h1>
      <PageEditor key={log.id} log={log} autoFocus label={log.title} />
      <PageFooter />
    </main>
  );
}

export function WeekPage({ weekKey: key }: { weekKey: string }) {
  const settings = useSettings();
  const firstDay = settings.firstDayOfWeek as Weekday;
  const start = weekKeyStart(key, firstDay);
  const end = addDays(start, 6);
  const anchor = anchorWithin(start, end);
  const log = periodLog('weekly', key, firstDay);
  useEffect(() => {
    const from = takeFrom();
    if (from) flash(from);
  }, [key]);
  const sameMonth = start.slice(0, 7) === end.slice(0, 7);
  const range = sameMonth
    ? `${fmt(start, { month: 'short', day: 'numeric' })} – ${fmt(end, { day: 'numeric' })}`
    : `${fmt(start, { month: 'short', day: 'numeric' })} – ${fmt(end, { month: 'short', day: 'numeric' })}`;
  return (
    <main className="page page-time">
      <TimeHeader level="week" periodKey={key} anchor={anchor} />
      {/* {settings.activeLogs.daily && <WeekStrip weekKey={key} firstDay={firstDay} />} */}
      <p className="eyebrow">
        {t.pages.week} {Number(key.split('-W')[1])}
      </p>
      <h1>{range}</h1>
      <PageEditor key={log.id} log={log} autoFocus label={log.title} />
      <PageFooter />
    </main>
  );
}
