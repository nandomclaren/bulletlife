// Data model (CLAUDE.md section 9).
import type { LineState, LineType } from '../editor/lines';

export type EntryType = LineType;
export type EntryState = LineState;
export type Signifier = 'priority' | 'inspiration' | 'explore';

export interface Entry {
  id: string;
  logId: string;
  /** Fixed layout row: 'YYYY-MM-DD' in a Month, 'YYYY-MM' in a Year. '' when the entry lives in the page body. */
  slot: string;
  parentId: string | null;
  order: string;
  type: EntryType;
  state: EntryState;
  text: string;
  signifiers: Signifier[];
  collapsed: boolean;
  dueDate?: string;
  placement?: { status: 'pending' | 'placed'; placedEntryId?: string; confirmedAt?: string };
  createdAt: string;
  updatedAt: string;
}

export type LogKind = 'future' | 'monthly' | 'weekly' | 'daily' | 'collection';

export interface Log {
  /** Time logs use deterministic ids ('daily:2026-10-18') so two offline devices never create duplicates. */
  id: string;
  kind: LogKind;
  title: string;
  periodStart?: string;
  periodEnd?: string;
  createdAt: string;
  updatedAt: string;
}

export interface Settings {
  activeLogs: { monthly: boolean; weekly: boolean; daily: boolean };
  eventStates: boolean;
  firstDayOfWeek: 0 | 1;
}

export const DEFAULT_SETTINGS: Settings = {
  activeLogs: { monthly: true, weekly: true, daily: true },
  eventStates: true,
  firstDayOfWeek: 1,
};
