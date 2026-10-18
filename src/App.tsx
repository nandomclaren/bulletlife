import { useEffect } from 'react';
import { todayIso, type Weekday } from './dates';
import { useSettings } from './data/repo';
import { DayPage, WeekPage } from './pages/DayWeekPages';
import { MonthPage, YearPage } from './pages/MonthYearPages';
import { finestLevel, pathFor } from './pages/nav';
import { replace, restoreScroll, usePath } from './router';
import { SettingsPage } from './SettingsPage';
import { SpikePage } from './spike/SpikePage';

export function App() {
  const path = usePath();
  useEffect(restoreScroll, [path]);

  let m: RegExpMatchArray | null;
  if ((m = path.match(/^\/day\/(\d{4}-\d{2}-\d{2})$/))) return <DayPage key={m[1]} iso={m[1]} />;
  if ((m = path.match(/^\/week\/(\d{4}-W\d{2})$/))) return <WeekPage key={m[1]} weekKey={m[1]} />;
  if ((m = path.match(/^\/month\/(\d{4}-\d{2})$/))) return <MonthPage key={m[1]} ym={m[1]} />;
  if ((m = path.match(/^\/year\/(\d{4})$/))) return <YearPage key={m[1]} year={m[1]} />;
  if (path === '/settings') return <SettingsPage />;
  if (path === '/check') return <SpikePage />;
  return <Home />;
}

/** Opening the app lands on today's finest active log, ready to type (principle 5). */
function Home() {
  const settings = useSettings();
  useEffect(() => {
    replace(pathFor(finestLevel(settings), todayIso(), settings.firstDayOfWeek as Weekday));
  }, [settings]);
  return null;
}
