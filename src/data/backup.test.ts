import { describe, expect, it } from 'vitest';
import { BackupError, buildBackup, exportReminderDue, parseBackup, planRestore, snapshotsToPrune } from './backup';
import type { Entry, Log } from './types';

const NOW = '2026-10-19T10:00:00.000Z';
const entry = (id: string, text: string, extra: Partial<Entry> = {}): Entry => ({
  id,
  logId: 'daily:2026-10-19',
  slot: '',
  parentId: null,
  order: 'a0',
  type: 'task',
  state: 'open',
  text,
  signifiers: [],
  collapsed: false,
  createdAt: NOW,
  updatedAt: NOW,
  ...extra,
});
const collection: Log = { id: 'collection:01A', kind: 'collection', title: 'Lidos', createdAt: NOW, updatedAt: NOW };

describe('backup', () => {
  it('round-trips through a file and drops sync-only fields', () => {
    const withSync = { ...entry('e1', 'Pay rent'), realmId: 'rlm-x', owner: 'me' } as Entry;
    const text = JSON.stringify(buildBackup([collection], [withSync], NOW));
    const back = parseBackup(text);
    expect(back.entries).toHaveLength(1);
    expect(back.entries[0]).not.toHaveProperty('realmId');
    expect(back.entries[0]).not.toHaveProperty('owner');
    expect(back.logs.map((l) => l.title)).toEqual(['Lidos']);
  });

  it('rejects files that are not ours', () => {
    expect(() => parseBackup('hello')).toThrow(BackupError);
    expect(() => parseBackup('{"app":"other","format":1}')).toThrow(BackupError);
    expect(() => parseBackup(JSON.stringify({ app: 'bullet-life', format: 99, logs: [], entries: [] }))).toThrow(BackupError);
  });

  it('restore replaces: entries not in the backup are removed, the rest written back', () => {
    const backup = buildBackup([collection], [entry('e1', 'Pay rent')], NOW);
    const current = {
      logs: [collection, { ...collection, id: 'collection:02B', title: 'New' }],
      entries: [entry('e1', 'Pay rent (edited)'), entry('e2', 'Later entry')],
    };
    const plan = planRestore(current, backup);
    expect(plan.putEntries.map((e) => e.text)).toEqual(['Pay rent']);
    expect(plan.removeEntries).toEqual(['e2']);
    expect(plan.removeLogs).toEqual(['collection:02B']);
  });

  it('reminds to export after a week, or when never exported, only if there is something written', () => {
    const now = new Date('2026-10-19T10:00:00Z');
    expect(exportReminderDue(undefined, now, true)).toBe(true);
    expect(exportReminderDue(undefined, now, false)).toBe(false);
    expect(exportReminderDue('2026-10-15T10:00:00Z', now, true)).toBe(false);
    expect(exportReminderDue('2026-10-12T09:00:00Z', now, true)).toBe(true);
  });

  it('keeps the 30 newest daily snapshots', () => {
    const ids = Array.from({ length: 33 }, (_, i) => `2026-09-${String(i + 1).padStart(2, '0')}`);
    expect(snapshotsToPrune(ids)).toEqual(['2026-09-03', '2026-09-02', '2026-09-01']);
  });
});

describe('backup file name', () => {
  it('is recognizable: BulletLife_YYYYMMDD', async () => {
    const { backupFileName } = await import('./backup');
    expect(backupFileName(new Date(2026, 9, 19, 23, 5))).toBe('BulletLife_20261019.json');
  });
});
