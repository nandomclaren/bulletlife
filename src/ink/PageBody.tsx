// A free page's body: the text editor, or the ruled sheet in Pen mode (iPad).
import { useEffect, type ComponentProps } from 'react';
import { useLoadedSettings } from '../data/repo';
import { transcribePage } from './transcribe';
import { PageEditor } from '../pages/PageEditor';
import { flushAll } from '../pages/flush';
import { usePane } from '../pages/pane';
import { t } from '../i18n/en';
import { PenSheet } from './PenSheet';
import { setPenMode, usePen, usePenAvailable } from './penStore';

export function PageBody(props: ComponentProps<typeof PageEditor>) {
  const pen = usePen();
  const available = usePenAvailable();
  const { secondary } = usePane();
  const settings = useLoadedSettings();
  // Handwriting not transcribed yet (written offline, or before the keys were set) is read when the page opens
  // and when the connection comes back.
  useEffect(() => {
    if (!settings) return;
    const run = () => void transcribePage(props.log.id, props.slot ?? '', settings);
    run();
    window.addEventListener('online', run);
    return () => window.removeEventListener('online', run);
  }, [props.log.id, props.slot, settings?.myscriptAppKey, settings?.myscriptHmacKey, settings?.handwritingLang]);
  if (pen.on && available && !secondary) return <PenSheet log={props.log} slot={props.slot} label={props.label} />;
  return <PageEditor {...props} />;
}

/** Title-row capsule: keyboard | pen. Only where Pen mode exists (a tablet). */
export function PenToggle() {
  const pen = usePen();
  const available = usePenAvailable();
  const { secondary } = usePane();
  if (!available || secondary) return null;
  const go = async (on: boolean) => {
    if (on === pen.on) return;
    await flushAll();
    setPenMode(on);
  };
  return (
    <div className="pen-switch" role="radiogroup" aria-label={t.pen.mode}>
      <button role="radio" aria-checked={!pen.on} aria-label={t.pen.type} className={!pen.on ? 'on' : ''} onClick={() => void go(false)}>
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" aria-hidden>
          <rect x="3" y="6" width="18" height="12" rx="2" />
          <path d="M7 10h.01M11 10h.01M15 10h.01M8 14h8" />
        </svg>
      </button>
      <button role="radio" aria-checked={pen.on} aria-label={t.pen.pen} className={pen.on ? 'on' : ''} onClick={() => void go(true)}>
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round" aria-hidden>
          <path d="M15 4l5 5L9 20H4v-5z" />
          <path d="M13 6l5 5" />
        </svg>
      </button>
    </div>
  );
}
