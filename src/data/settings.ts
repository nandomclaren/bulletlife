// Pure rules for Settings (unit tested).
import type { Settings } from './types';

export type TimeLog = keyof Settings['activeLogs'];

/**
 * Turns one time log on or off. At least one of Month, Week and Day must stay
 * on (CLAUDE.md 3.2): migrating needs a source and a destination besides the
 * Year. Returns null when the change is not allowed.
 */
export function toggleActiveLog(active: Settings['activeLogs'], log: TimeLog): Settings['activeLogs'] | null {
  const next = { ...active, [log]: !active[log] };
  return next.monthly || next.weekly || next.daily ? next : null;
}

/** Whether this log is the last one on (its switch must be locked). */
export function isLastActive(active: Settings['activeLogs'], log: TimeLog): boolean {
  return active[log] && toggleActiveLog(active, log) === null;
}
