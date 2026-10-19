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
  /** A period page set up explicitly ("Set up week"): the time log it stands for, e.g. 'weekly:2026-W43'. */
  periodLogId?: string;
  /** A collection pinned to the top of the Index. */
  pinned?: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface Settings {
  activeLogs: { monthly: boolean; weekly: boolean; daily: boolean };
  eventStates: boolean;
  firstDayOfWeek: 0 | 1;
  /** Settings › Date format: day or month first (due dates). */
  dateOrder: 'dmy' | 'mdy';
  /** Settings › Markdown glyph style. */
  markdownGlyphs?: 'checkboxes' | 'dots';
  /** When everything was last exported to a file on this device (ISO). */
  lastExportAt?: string;
  /** Settings › Reverse swipe directions: swipe left marks > and right marks <. */
  reverseSwipes: boolean;
  /** Settings › "Week 43 isn't set up yet" banner. */
  setupBanner: boolean;
  /** Settings › Close the day banner, and from what time ('HH:MM'). */
  closeDay: boolean;
  closeDayAt: string;
  /** Settings › Backup: a reminder when the last full export is over a week old. */
  exportReminder: boolean;
  /** Settings › number on the Open items button. */
  openCount: boolean;
}

export const DEFAULT_SETTINGS: Settings = {
  activeLogs: { monthly: true, weekly: true, daily: true },
  eventStates: true,
  firstDayOfWeek: 1,
  dateOrder: 'dmy',
  reverseSwipes: false,
  setupBanner: true,
  closeDay: true,
  closeDayAt: '20:00',
  openCount: true,
  exportReminder: true,
};
