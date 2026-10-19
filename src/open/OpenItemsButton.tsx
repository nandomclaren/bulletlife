// Permanent, quiet way into Open items: a small button with a plain count
// (no red badge, no alarm), hidden count if the user prefers (Settings).
import { useSettings } from '../data/repo';
import { t } from '../i18n/en';
import { togglePanel, usePanel } from './panelStore';
import { useOpenItems } from './useOpenItems';

export function OpenItemsButton() {
  const settings = useSettings();
  const data = useOpenItems();
  const panel = usePanel();
  const n = data?.items.length ?? 0;
  return (
    <button
      className="open-btn"
      aria-label={settings.openCount ? `${t.open.title}, ${t.open.count(n)}` : t.open.title}
      aria-expanded={panel.open}
      onClick={togglePanel}
    >
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" aria-hidden>
        <circle cx="5" cy="7" r="1.6" fill="currentColor" stroke="none" />
        <path d="M10 7h10" />
        <circle cx="5" cy="12" r="1.6" fill="currentColor" stroke="none" />
        <path d="M10 12h10" />
        <circle cx="5" cy="17" r="1.6" />
        <path d="M10 17h6" />
      </svg>
      {settings.openCount && n > 0 && <span className="open-count">{n}</span>}
    </button>
  );
}
