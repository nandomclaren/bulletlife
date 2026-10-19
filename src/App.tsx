import { useEffect } from 'react';
import { addDays, daysInMonth, todayIso, weekKeyStart, type Weekday } from './dates';
import { useLoadedSettings } from './data/repo';
import type { Settings } from './data/types';
import { CollectionPage } from './pages/CollectionPage';
import { DayPage, WeekPage } from './pages/DayWeekPages';
import { IndexPage } from './pages/IndexPage';
import { MonthPage, YearPage } from './pages/MonthYearPages';
import { activeLevels, anchorWithin, finestLevel, pathFor, type Level } from './pages/nav';
import { replace, restoreScroll, usePath } from './router';
import { setSelection } from './export/selection';
import { OpenItemsPanel } from './open/OpenItemsPanel';
import { dueView } from './editor/render';
import { SettingsPage } from './SettingsPage';
import { SpikePage } from './spike/SpikePage';

export function App() {
  return (
    <>
      <Routes />
      <OpenItemsPanel />
    </>
  );
}

function Routes() {
  const path = usePath();
  const settings = useLoadedSettings();
  if (settings) {
    // How due dates are read and shown, for every editor.
    dueView.order = settings.dateOrder;
    dueView.firstDay = settings.firstDayOfWeek as Weekday;
  }
  useEffect(restoreScroll, [path]);
  // A selection belongs to the page it was made on.
  useEffect(() => setSelection(null), [path]);

  let m: RegExpMatchArray | null;
  if ((m = path.match(/^\/day\/(\d{4}-\d{2}-\d{2})$/))) {
    const iso = m[1];
    return guard(settings, 'day', () => iso) ?? <DayPage key={iso} iso={iso} />;
  }
  if ((m = path.match(/^\/week\/(\d{4}-W\d{2})$/))) {
    const key = m[1];
    return (
      guard(settings, 'week', (s) => {
        const start = weekKeyStart(key, s.firstDayOfWeek as Weekday);
        return anchorWithin(start, addDays(start, 6));
      }) ?? <WeekPage key={key} weekKey={key} />
    );
  }
  if ((m = path.match(/^\/month\/(\d{4}-\d{2})$/))) {
    const ym = m[1];
    return guard(settings, 'month', () => anchorWithin(`${ym}-01`, `${ym}-${daysInMonth(ym)}`)) ?? <MonthPage key={ym} ym={ym} />;
  }
  if ((m = path.match(/^\/year\/(\d{4})$/))) return <YearPage key={m[1]} year={m[1]} />;
  if ((m = path.match(/^\/collection\/([^/]+)$/))) {
    const id = decodeURIComponent(m[1]);
    return <CollectionPage key={id} id={id} />;
  }
  if (path === '/index') return <IndexPage />;
  if (path === '/settings') return <SettingsPage />;
  if (path === '/check') return <SpikePage />;
  return settings ? <Redirect to={pathFor(finestLevel(settings), todayIso(), settings.firstDayOfWeek as Weekday)} /> : null;
}

/**
 * A page of a level turned off in Settings (from history, a link, or settings
 * changed elsewhere) is replaced by the finest active level for the same date,
 * so ‹ › always step through an active log.
 */
function guard(settings: Settings | undefined, level: Level, date: (s: Settings) => string) {
  if (!settings || activeLevels(settings).includes(level)) return null;
  return <Redirect to={pathFor(finestLevel(settings), date(settings), settings.firstDayOfWeek as Weekday)} />;
}

function Redirect({ to }: { to: string }) {
  useEffect(() => replace(to), [to]);
  return null;
}
