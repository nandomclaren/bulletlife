import { fmt, todayIso, weekDays, type Weekday } from '../dates';
import { periodLog, useLogsWithContent } from '../data/repo';
import { t } from '../i18n/en';
import { navigate } from '../router';
import { setAnchor } from './nav';

interface Props {
  weekKey: string;
  firstDay: Weekday;
  selected?: string;
}

/** Seven tappable days; a dot marks days that already have entries. */
export function WeekStrip({ weekKey, firstDay, selected }: Props) {
  const days = weekDays(weekKey, firstDay);
  const filled = useLogsWithContent(days.map((d) => periodLog('daily', d, firstDay).id));
  const today = todayIso();
  return (
    <ol className="week-strip">
      {days.map((d) => {
        const has = filled.has(`daily:${d}`);
        return (
          <li key={d} id={`strip-${d}`}>
            <button
              className={`strip-day${d === today ? ' is-today' : ''}${d === selected ? ' is-selected' : ''}`}
              aria-label={`${fmt(d, { weekday: 'long', month: 'long', day: 'numeric' })}${has ? `, ${t.pages.hasContent}` : ''}`}
              aria-current={d === selected ? 'date' : undefined}
              onClick={() => {
                setAnchor(d);
                navigate(`/day/${d}`);
              }}
            >
              <span className="strip-initial">{fmt(d, { weekday: 'narrow' })}</span>
              <span className="strip-num">{fmt(d, { day: 'numeric' })}</span>
              <span className={`strip-dot${has ? ' on' : ''}`} aria-hidden />
            </button>
          </li>
        );
      })}
    </ol>
  );
}
