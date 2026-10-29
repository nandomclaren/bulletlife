import { useState } from 'react';
import { t } from '../i18n/en';
import { clearPenLog, penLogText, usePenLog } from './penLog';

/** The last events of the pen diagnostics, with Copy log (Settings › Handwriting › Pen diagnostics). */
export function PenLogPanel() {
  const { lines } = usePenLog();
  const [copied, setCopied] = useState(false);
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(penLogText());
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1500);
    } catch {
      // the clipboard refused: nothing to do but try again
    }
  };
  return (
    <div className="pen-log" role="log" aria-label={t.pen.diagnostics.title}>
      <div className="pen-log-head">
        <span>{t.pen.diagnostics.title}</span>
        <button type="button" onClick={() => void copy()}>
          {copied ? t.pen.diagnostics.copied : t.pen.diagnostics.copy}
        </button>
        <button type="button" onClick={clearPenLog}>
          {t.pen.diagnostics.clear}
        </button>
      </div>
      <pre>{lines.slice(-10).join('\n')}</pre>
    </div>
  );
}
