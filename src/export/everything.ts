// Settings › Backup › Export everything as Markdown: every written page in one
// readable file. Years, then Months, Weeks and Days, oldest first, then the
// collections by name. The JSON export stays the restorable backup.
import type { Weekday } from '../dates';
import { writtenPages } from '../data/repo';
import type { Log } from '../data/types';
import { toMarkdown, type GlyphStyle } from './format';
import { buildPageDoc, type PageRef } from './pageDoc';

const KIND_ORDER = ['future', 'monthly', 'weekly', 'daily'] as const;

export function orderPages(logIds: string[], collections: Log[]): PageRef[] {
  const time = KIND_ORDER.flatMap((kind) =>
    logIds
      .filter((id) => id.startsWith(`${kind}:`))
      .map((id) => id.slice(kind.length + 1))
      .sort()
      .map((key): PageRef => ({ kind, key })),
  );
  const written = new Set(logIds);
  const cols = collections
    .filter((c) => c.kind === 'collection' && written.has(c.id))
    .sort((a, b) => a.title.localeCompare(b.title, 'en'))
    .map((c): PageRef => ({ kind: 'collection', id: c.id, title: c.title }));
  return [...time, ...cols];
}

export async function everythingMarkdown(style: GlyphStyle, firstDay: Weekday): Promise<string> {
  const { logIds, collections } = await writtenPages();
  const docs = await Promise.all(orderPages(logIds, collections).map((p) => buildPageDoc(p, firstDay)));
  return docs
    .filter((d) => d.sections.some((s) => s.lines.length))
    .map((d) => toMarkdown(d, style))
    .join('\n');
}
