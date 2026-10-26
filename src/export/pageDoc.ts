// Builds the exportable document of a page from the stored entries (never
// from the screen), so collapsed children are always included.
import { addDays, addMonths, fmt, monthDays, weekKeyStart, type Weekday } from '../dates';
import { loadLines, periodLog } from '../data/repo';
import { t } from '../i18n/en';
import type { ExportDoc } from './format';

export type PageRef = { kind: 'daily' | 'weekly' | 'monthly' | 'future'; key: string } | { kind: 'collection'; id: string; title: string };

export async function buildPageDoc(page: PageRef, firstDay: Weekday): Promise<ExportDoc> {
  switch (page.kind) {
    case 'daily':
      return {
        title: fmt(page.key, { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' }),
        sections: [{ lines: await loadLines(`daily:${page.key}`) }],
      };
    case 'weekly': {
      const start = weekKeyStart(page.key, firstDay);
      const end = addDays(start, 6);
      const range = `${fmt(start, { month: 'short', day: 'numeric' })} – ${fmt(end, { month: 'short', day: 'numeric', year: 'numeric' })}`;
      return {
        title: `${t.pages.week} ${Number(page.key.split('-W')[1])} · ${range}`,
        sections: [{ lines: await loadLines(periodLog('weekly', page.key, firstDay).id) }],
      };
    }
    case 'monthly': {
      const id = `monthly:${page.key}`;
      const days = await Promise.all(
        monthDays(page.key).map(async (iso) => ({
          heading: fmt(iso, { day: 'numeric', weekday: 'short' }).replace(/^(\w+) (\d+)$/, '$2 $1'),
          lines: await loadLines(id, iso),
        })),
      );
      return {
        title: fmt(`${page.key}-01`, { month: 'long', year: 'numeric' }),
        sections: [...days, { heading: t.pages.monthTasks, lines: await loadLines(id) }],
      };
    }
    case 'future': {
      const id = `future:${page.key}`;
      const months = Array.from({ length: 12 }, (_, i) => addMonths(`${page.key}-01`, i));
      return {
        title: page.key,
        sections: await Promise.all(months.map(async (ym) => ({ heading: fmt(`${ym}-01`, { month: 'long' }), lines: await loadLines(id, ym) }))),
      };
    }
    case 'collection':
      return { title: page.title, sections: [{ lines: await loadLines(page.id) }] };
  }
}
