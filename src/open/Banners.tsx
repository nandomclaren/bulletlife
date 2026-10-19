// Quiet in-app banners (CLAUDE.md 5): the set-up banner for this week or
import { usePane } from '../pages/pane';
// month, and Close the day in the evening. Both are dismissible and only
// open things up; nothing is written except the explicit "Set up".
import { useEffect, useState } from 'react';
import { addDays, fmt, monthOf, weekKey, type Weekday } from '../dates';
import { daysSinceExport, exportReminderDue } from '../data/backup';
import { exportEverything, periodLog, setUpPeriod, useHasEntries, usePeriodsSetUp, useSettings, type LogRef } from '../data/repo';
import { exportFile } from '../export/actions';
import { t } from '../i18n/en';
import { openPanel } from './panelStore';
import { useToday } from './useOpenItems';

const read = (k: string) => {
  try {
    return localStorage.getItem(k) === '1';
  } catch {
    return false;
  }
};
const write = (k: string) => {
  try {
    localStorage.setItem(k, '1');
  } catch {
    // dismissed for this session only
  }
};

function useNow(): string {
  const [now, setNow] = useState(() => new Date().toTimeString().slice(0, 5));
  useEffect(() => {
    const tick = () => setNow(new Date().toTimeString().slice(0, 5));
    const id = window.setInterval(tick, 30_000);
    document.addEventListener('visibilitychange', tick);
    return () => {
      window.clearInterval(id);
      document.removeEventListener('visibilitychange', tick);
    };
  }, []);
  return now;
}

/** Shown on pages of the current period (today's Day, this Week, this Month). */
export function Banners({ current }: { current: boolean }) {
  const { navigate, secondary } = usePane();
  const settings = useSettings();
  const today = useToday();
  const now = useNow();
  const firstDay = settings.firstDayOfWeek as Weekday;
  const [dismissed, setDismissed] = useState(0);

  const candidates: LogRef[] = [];
  if (settings.activeLogs.monthly) candidates.push(periodLog('monthly', monthOf(today), firstDay));
  if (settings.activeLogs.weekly) candidates.push(periodLog('weekly', weekKey(today, firstDay), firstDay));
  const setUp = usePeriodsSetUp(candidates.map((c) => c.id));
  void dismissed;

  const hasEntries = useHasEntries();
  // The second pane is for reading only.
  if (secondary || !current || !setUp) return null;

  // Backup reminder: a full export to keep off the device (iCloud Drive). Dismissing waits 3 days.
  const snoozed = (() => {
    try {
      return Number(localStorage.getItem('banner.export.snoozedUntil') ?? 0) > Date.now();
    } catch {
      return false;
    }
  })();
  const showExport = settings.exportReminder && !snoozed && exportReminderDue(settings.lastExportAt, new Date(), !!hasEntries);

  const pendingSetup = settings.setupBanner ? candidates.find((c) => !setUp.has(c.id) && !read(`banner.setup.${c.id}`)) : undefined;
  const closeKey = `banner.closeDay.${today}`;
  const showClose = settings.closeDay && settings.activeLogs.daily && now >= settings.closeDayAt && !read(closeKey);

  return (
    <>
      {pendingSetup && (
        <Banner
          text={
            pendingSetup.kind === 'weekly'
              ? t.banners.weekNotSetUp(Number(pendingSetup.id.split('-W')[1]))
              : t.banners.monthNotSetUp(fmt(`${monthOf(today)}-01`, { month: 'long' }))
          }
          action={pendingSetup.kind === 'weekly' ? t.banners.setUpWeek : t.banners.setUpMonth}
          onAction={async () => {
            await setUpPeriod(pendingSetup);
            navigate(pendingSetup.kind === 'weekly' ? `/week/${pendingSetup.id.slice('weekly:'.length)}` : `/month/${monthOf(today)}`);
            openPanel('all');
          }}
          onDismiss={() => {
            write(`banner.setup.${pendingSetup.id}`);
            setDismissed((n) => n + 1);
          }}
        />
      )}
      {showExport && (
        <Banner
          text={t.banners.exportStale(daysSinceExport(settings.lastExportAt, new Date()))}
          action={t.banners.exportNow}
          onAction={async () => {
            const { name, text } = await exportEverything();
            await exportFile(name, text, 'application/json');
          }}
          onDismiss={() => {
            try {
              localStorage.setItem('banner.export.snoozedUntil', String(Date.now() + 3 * 86_400_000));
            } catch {
              // shown again next time
            }
            setDismissed((n) => n + 1);
          }}
        />
      )}
      {showClose && (
        <Banner
          text={t.banners.closeDayHint}
          action={t.banners.closeDay}
          onAction={() => {
            write(closeKey);
            setDismissed((n) => n + 1);
            navigate(`/day/${addDays(today, 1)}`);
            openPanel('today');
          }}
          onDismiss={() => {
            write(closeKey);
            setDismissed((n) => n + 1);
          }}
        />
      )}
    </>
  );
}

function Banner({ text, action, onAction, onDismiss }: { text: string; action: string; onAction: () => void; onDismiss: () => void }) {
  return (
    <div className="banner" role="note">
      <span className="banner-text">{text}</span>
      <button className="banner-action" onClick={onAction}>
        {action}
      </button>
      <button className="banner-dismiss" aria-label={t.banners.dismiss} onClick={onDismiss}>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" aria-hidden>
          <path d="M6 6l12 12M18 6L6 18" />
        </svg>
      </button>
    </div>
  );
}
