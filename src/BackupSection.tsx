// Settings › Backup: export to a file, restore from a file, daily snapshots.
import { useRef, useState } from 'react';
import { BackupError, backupFileName } from './data/backup';
import { exportEverything, restoreFromFile, restoreSnapshot, useSettings, useSnapshots } from './data/repo';
import type { Weekday } from './dates';
import { exportFile } from './export/actions';
import { everythingMarkdown } from './export/everything';
import { t } from './i18n/en';

const when = new Intl.DateTimeFormat('en', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false });
const rel = new Intl.RelativeTimeFormat('en', { numeric: 'auto' });

function ago(iso: string) {
  const ms = Date.parse(iso) - Date.now();
  const minutes = Math.round(ms / 60_000);
  if (minutes > -1) return t.backup.justNow;
  if (minutes > -60) return rel.format(minutes, 'minute');
  if (minutes > -24 * 60) return rel.format(Math.round(minutes / 60), 'hour');
  return rel.format(Math.round(minutes / (24 * 60)), 'day');
}

export function BackupSection() {
  const settings = useSettings();
  const snapshots = useSnapshots();
  const [confirming, setConfirming] = useState<string | null>(null);
  const [pendingFile, setPendingFile] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const fileInput = useRef<HTMLInputElement>(null);

  const done = (text: string) => {
    setConfirming(null);
    setPendingFile(null);
    setMessage(text);
    setTimeout(() => setMessage(null), 4000);
  };

  return (
    <section className="setting">
      <h2>{t.backup.title}</h2>
      <div className="options">
        <button
          className="option"
          onClick={async () => {
            const { name, text } = await exportEverything();
            await exportFile(name, text, 'application/json');
          }}
        >
          <span className="option-text">
            <span className="option-title">{t.backup.export}</span>
            <span className="option-hint">
              {t.backup.lastExport}: {settings.lastExportAt ? ago(settings.lastExportAt) : t.backup.never}
            </span>
          </span>
        </button>
        <button
          className="option"
          onClick={async () => {
            const text = await everythingMarkdown(settings.markdownGlyphs ?? 'checkboxes', settings.firstDayOfWeek as Weekday);
            await exportFile(backupFileName(new Date()).replace(/\.json$/, '.md'), text, 'text/markdown');
          }}
        >
          <span className="option-text">
            <span className="option-title">{t.backup.exportMarkdown}</span>
            <span className="option-hint">{t.backup.exportMarkdownHint}</span>
          </span>
        </button>
        <button className="option" onClick={() => fileInput.current?.click()}>
          <span className="option-title">{t.backup.restoreFile}</span>
        </button>
        {pendingFile !== null && (
          <div className="option confirm-row">
            <span className="option-hint">{t.backup.confirmFile}</span>
            <span className="confirm-actions">
              <button className="btn btn-quiet" onClick={() => setPendingFile(null)}>
                {t.backup.cancel}
              </button>
              <button
                className="btn btn-primary"
                onClick={async () => {
                  try {
                    await restoreFromFile(pendingFile);
                    done(t.backup.restored);
                  } catch (e) {
                    done(e instanceof BackupError && e.message === 'newer-format' ? t.backup.newerFile : t.backup.badFile);
                  }
                }}
              >
                {t.backup.restore}
              </button>
            </span>
          </div>
        )}
      </div>
      <input
        ref={fileInput}
        type="file"
        accept="application/json,.json"
        hidden
        onChange={async (e) => {
          const file = e.currentTarget.files?.[0];
          e.currentTarget.value = '';
          if (file) setPendingFile(await file.text());
        }}
      />
      <p className="setting-hint">{t.backup.exportHint}</p>

      <h3 className="setting-sub">{t.backup.snapshots}</h3>
      <div className="options">
        {snapshots?.length === 0 && (
          <div className="option">
            <span className="option-hint">{t.backup.noSnapshots}</span>
          </div>
        )}
        {snapshots?.map((s) => (
          <div key={s.id} className="snapshot">
            <button className="option" onClick={() => setConfirming(confirming === s.id ? null : s.id)} aria-expanded={confirming === s.id}>
              <span className="option-text">
                <span className="option-title">
                  {when.format(new Date(s.createdAt))}
                  {s.kind === 'before-restore' && <span className="muted"> · {t.backup.beforeRestore}</span>}
                </span>
                <span className="option-hint">
                  {t.backup.entries(s.entryCount)} · {t.backup.collections(s.collectionCount)}
                </span>
              </span>
            </button>
            {confirming === s.id && (
              <div className="option confirm-row">
                <span className="option-hint">{t.backup.confirm}</span>
                <span className="confirm-actions">
                  <button className="btn btn-quiet" onClick={() => setConfirming(null)}>
                    {t.backup.cancel}
                  </button>
                  <button
                    className="btn btn-primary"
                    onClick={async () => {
                      await restoreSnapshot(s.id);
                      done(`${t.backup.restored} · ${when.format(new Date(s.createdAt))}`);
                    }}
                  >
                    {t.backup.restore}
                  </button>
                </span>
              </div>
            )}
          </div>
        ))}
      </div>
      <p className="setting-hint">{t.backup.snapshotsHint}</p>
      {message && (
        <div className="undo-toast" role="status">
          <span>{message}</span>
        </div>
      )}
    </section>
  );
}
