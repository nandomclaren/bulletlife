import { useEffect, useRef, useState } from 'react';
import { useLiveQuery, useObservable } from 'dexie-react-hooks';
import { localDb, getCloudDb, getCloudUrl, setCloudUrl, type CloudDb } from '../data/spikeDb';
import { t } from '../i18n/en';
import { navigate } from '../router';
import { CheckCard, Fact } from './CheckCard';
import { Bullet, type BulletState, type BulletType } from './Bullet';
import { deviceLabel, isStandalone, useFact } from './facts';

const yesNo = (v: boolean) => (v ? t.spike.yes : t.spike.no);

export function InstallCheck() {
  const standalone = isStandalone();
  useFact('install', t.checks.install.standalone, yesNo(standalone));
  return (
    <CheckCard id="install">
      <Fact label={t.checks.install.standalone} value={yesNo(standalone)} />
    </CheckCard>
  );
}

export function OfflineCheck() {
  const [controlled, setControlled] = useState(!!navigator.serviceWorker?.controller);
  const [online, setOnline] = useState(navigator.onLine);
  useEffect(() => {
    const on = () => setOnline(navigator.onLine);
    const ctl = () => setControlled(!!navigator.serviceWorker?.controller);
    window.addEventListener('online', on);
    window.addEventListener('offline', on);
    navigator.serviceWorker?.addEventListener('controllerchange', ctl);
    return () => {
      window.removeEventListener('online', on);
      window.removeEventListener('offline', on);
      navigator.serviceWorker?.removeEventListener('controllerchange', ctl);
    };
  }, []);
  useFact('offline', t.checks.offline.sw, yesNo(controlled));
  useFact('offline', t.checks.offline.online, online ? 'online' : 'offline');
  return (
    <CheckCard id="offline">
      <Fact label={t.checks.offline.sw} value={yesNo(controlled)} />
      <Fact label={t.checks.offline.online} value={online ? 'online' : 'offline'} />
    </CheckCard>
  );
}

const fmt = new Intl.DateTimeFormat('en', { dateStyle: 'medium', timeStyle: 'short', hour12: false });

export function PersistenceCheck() {
  const first = useLiveQuery(() => localDb.launches.orderBy('at').first());
  const count = useLiveQuery(() => localDb.launches.count());
  const days = first ? Math.floor((Date.now() - Date.parse(first.at)) / 86_400_000) : null;
  useFact('persistence', t.checks.persistence.firstLaunch, first?.at);
  useFact('persistence', t.checks.persistence.launches, count?.toString());
  useFact('persistence', t.checks.persistence.span, days?.toString());
  return (
    <CheckCard id="persistence">
      <Fact label={t.checks.persistence.firstLaunch} value={first ? fmt.format(new Date(first.at)) : '…'} />
      <Fact label={t.checks.persistence.launches} value={count ?? '…'} />
      <Fact label={t.checks.persistence.span} value={days ?? '…'} />
    </CheckCard>
  );
}

export function PersistCheck() {
  const [persisted, setPersisted] = useState<boolean | null>(null);
  const [usage, setUsage] = useState<string | null>(null);
  const refresh = async () => {
    setPersisted((await navigator.storage?.persisted?.()) ?? null);
    const est = await navigator.storage?.estimate?.();
    if (est) setUsage(`${((est.usage ?? 0) / 1024).toFixed(0)} KB of ${((est.quota ?? 0) / 1024 ** 2).toFixed(0)} MB`);
  };
  useEffect(() => {
    void refresh();
  }, []);
  useFact('persist', t.checks.persist.persisted, persisted == null ? 'unsupported' : yesNo(persisted));
  useFact('persist', t.checks.persist.usage, usage);
  return (
    <CheckCard id="persist">
      <Fact label={t.checks.persist.persisted} value={persisted == null ? '—' : yesNo(persisted)} />
      <Fact label={t.checks.persist.usage} value={usage ?? '—'} />
      <button
        className="btn"
        onClick={async () => {
          await navigator.storage?.persist?.();
          await refresh();
        }}
      >
        {t.checks.persist.request}
      </button>
    </CheckCard>
  );
}

export function CloudCheck() {
  const [url, setUrl] = useState(getCloudUrl() ?? '');
  const db = getCloudDb();
  return (
    <CheckCard id="cloud">
      {db ? (
        <CloudPanel db={db} />
      ) : (
        <form
          className="row"
          onSubmit={(e) => {
            e.preventDefault();
            if (!url.trim()) return;
            setCloudUrl(url.trim());
            location.reload();
          }}
        >
          <input
            className="field"
            type="url"
            inputMode="url"
            autoCapitalize="off"
            placeholder={t.checks.cloud.urlPlaceholder}
            value={url}
            onChange={(e) => setUrl(e.target.value)}
          />
          <button className="btn">{t.checks.cloud.connect}</button>
        </form>
      )}
    </CheckCard>
  );
}

function CloudPanel({ db }: { db: CloudDb }) {
  const user = useObservable(db.cloud.currentUser);
  const sync = useObservable(db.cloud.syncState);
  const lines = useLiveQuery(() => db.lines.orderBy('createdAt').toArray(), [db]);
  const [text, setText] = useState('');
  const state = sync ? `${sync.phase}${sync.status ? ` · ${sync.status}` : ''}` : '…';
  useFact('cloud', t.checks.cloud.user, user?.userId);
  useFact('cloud', t.checks.cloud.state, state);
  return (
    <>
      <Fact label={t.checks.cloud.user} value={user?.userId ?? '…'} />
      <Fact label={t.checks.cloud.state} value={state} />
      <ul className="sync-lines">
        {lines?.length ? (
          lines.map((l) => (
            <li key={l.id}>
              {l.text} <span className="muted">· {l.device}</span>
            </li>
          ))
        ) : (
          <li className="muted">{t.checks.cloud.empty}</li>
        )}
      </ul>
      <form
        className="row"
        onSubmit={async (e) => {
          e.preventDefault();
          if (!text.trim()) return;
          await db.lines.add({ text: text.trim(), createdAt: new Date().toISOString(), device: deviceLabel() });
          setText('');
        }}
      >
        <input className="field" placeholder={t.checks.cloud.linePlaceholder} value={text} onChange={(e) => setText(e.target.value)} />
        <button className="btn">{t.checks.cloud.add}</button>
      </form>
      <button
        className="btn btn-quiet"
        onClick={() => {
          setCloudUrl(null);
          location.reload();
        }}
      >
        {t.checks.cloud.disconnect}
      </button>
    </>
  );
}

export function ShareCheck() {
  const supported = typeof navigator.share === 'function';
  useFact('share', 'navigator.share', yesNo(supported));
  return (
    <CheckCard id="share">
      {supported ? (
        <button
          className="btn"
          onClick={() =>
            navigator.share({ title: t.appName, text: '- [ ] Call the bank\n- [x] Buy bread\n- Note: rain tomorrow' }).catch(() => {})
          }
        >
          {t.checks.share.button}
        </button>
      ) : (
        <p className="muted">{t.checks.share.unsupported}</p>
      )}
    </CheckCard>
  );
}

const SAMPLE_HTML =
  '<h1>Sun, Oct 18</h1><ul><li>☐ <b>Call the bank</b></li><li>☒ Buy bread</li><li>– Rain tomorrow</li></ul>';
const SAMPLE_TEXT = '# Sun, Oct 18\n- [ ] Call the bank\n- [x] Buy bread\n- Rain tomorrow';

async function copyRich(html: string, text: string): Promise<string> {
  if (typeof ClipboardItem !== 'undefined' && navigator.clipboard?.write) {
    try {
      await navigator.clipboard.write([
        new ClipboardItem({
          'text/html': new Blob([html], { type: 'text/html' }),
          'text/plain': new Blob([text], { type: 'text/plain' }),
        }),
      ]);
      return 'ClipboardItem';
    } catch {
      // fall through to the copy-event fallback
    }
  }
  const onCopy = (e: ClipboardEvent) => {
    e.preventDefault();
    e.clipboardData?.setData('text/html', html);
    e.clipboardData?.setData('text/plain', text);
  };
  document.addEventListener('copy', onCopy, { once: true });
  const ok = document.execCommand('copy');
  document.removeEventListener('copy', onCopy);
  return ok ? 'copy event fallback' : 'failed';
}

export function RichCopyCheck() {
  const [method, setMethod] = useState<string | null>(null);
  useFact('richCopy', 'method', method);
  return (
    <CheckCard id="richCopy">
      <button className="btn" onClick={async () => setMethod(await copyRich(SAMPLE_HTML, SAMPLE_TEXT))}>
        {t.checks.richCopy.button}
      </button>
      {method && <p className="muted">{method === 'failed' ? t.checks.richCopy.failed : `${t.checks.richCopy.done} (${method})`}</p>}
    </CheckCard>
  );
}

export function SelectionCheck() {
  const box = useRef<HTMLDivElement>(null);
  const saved = useRef('');
  const [atTap, setAtTap] = useState<string | null>(null);
  const [captured, setCaptured] = useState<string | null>(null);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    // Store the selection on every change: tapping a button on iOS can clear it.
    const onChange = () => {
      const sel = document.getSelection();
      if (sel && !sel.isCollapsed && box.current?.contains(sel.anchorNode)) saved.current = sel.toString();
    };
    document.addEventListener('selectionchange', onChange);
    return () => document.removeEventListener('selectionchange', onChange);
  }, []);

  useFact('selection', t.checks.selection.nativeAtTap, atTap);
  useFact('selection', t.checks.selection.captured, captured);

  return (
    <CheckCard id="selection">
      <div className="sel-wrap">
        <div ref={box} className="sel-box" contentEditable suppressContentEditableWarning spellCheck={false}>
          <div>• Call the bank about the card</div>
          <div>○ Dinner with Ana at 8</div>
          <div>– The plane leaves from gate 12</div>
          <div>• Renew passport</div>
        </div>
        <button
          className="icon-btn"
          aria-label={t.checks.selection.menu}
          onPointerDown={() => setAtTap(document.getSelection()?.toString() ?? '')}
          onClick={() => {
            setCaptured(saved.current);
            setOpen((o) => !o);
          }}
        >
          …
        </button>
        {open && (
          <div className="menu" role="menu">
            <button role="menuitem" onClick={() => void navigator.clipboard?.writeText(saved.current).finally(() => setOpen(false))}>
              {t.checks.selection.copySelection}
            </button>
          </div>
        )}
      </div>
      <Fact label={t.checks.selection.nativeAtTap} value={atTap || t.checks.selection.nothing} />
      <Fact label={t.checks.selection.captured} value={captured || t.checks.selection.nothing} />
    </CheckCard>
  );
}

export function LongPressCheck() {
  const [openedBy, setOpenedBy] = useState<string | null>(null);
  useFact('longPress', t.checks.longPress.opened, openedBy);
  return (
    <CheckCard id="longPress">
      <WritingLine type="task" initial="Press and hold the bullet" onMenu={setOpenedBy} />
      {openedBy && <Fact label={t.checks.longPress.opened} value={openedBy} />}
    </CheckCard>
  );
}

export function SwipeCheck() {
  const [delta, setDelta] = useState(0);
  const area = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const el = area.current!;
    const onWheel = (e: WheelEvent) => {
      if (Math.abs(e.deltaX) > Math.abs(e.deltaY)) {
        e.preventDefault();
        setDelta(Math.round(e.deltaX));
      }
    };
    el.addEventListener('wheel', onWheel, { passive: false });
    return () => el.removeEventListener('wheel', onWheel);
  }, []);
  return (
    <CheckCard id="swipe">
      <div ref={area} className="swipe-area">
        {t.checks.swipe.area}
      </div>
      <Fact label={t.checks.swipe.lastDelta} value={delta} />
    </CheckCard>
  );
}

export function BackCheck() {
  return (
    <CheckCard id="back">
      <button className="btn" onClick={() => navigate('/month/2026-10')}>
        {t.checks.back.openMonth}
      </button>
    </CheckCard>
  );
}

function detectFont(family: string) {
  const ctx = document.createElement('canvas').getContext('2d');
  if (!ctx) return false;
  const sample = 'mmmmmmmmmmlliWW0123';
  return ['monospace', 'serif'].some((fallback) => {
    ctx.font = `32px ${fallback}`;
    const base = ctx.measureText(sample).width;
    ctx.font = `32px "${family}", ${fallback}`;
    return ctx.measureText(sample).width !== base;
  });
}

export function FontCheck() {
  const found = detectFont('Avenir Next');
  useFact('font', t.checks.font.detected, yesNo(found));
  return (
    <CheckCard id="font">
      <p className="font-sample">{t.checks.font.sample}</p>
      <Fact label={t.checks.font.detected} value={yesNo(found)} />
    </CheckCard>
  );
}

export function CaretCheck() {
  return (
    <CheckCard id="caret">
      <WritingLine type="task" initial="Call the bank about the card" />
      <WritingLine type="event" initial="Dinner with Ana at 8" />
      <WritingLine type="note" initial="The plane leaves from gate 12" />
    </CheckCard>
  );
}

function WritingLine({ type, initial, onMenu }: { type: BulletType; initial: string; onMenu?: (by: string) => void }) {
  const [state, setState] = useState<BulletState>('open');
  return (
    <div className={`line line-${type} is-${state}`}>
      <Bullet type={type} state={state} onState={setState} onMenu={onMenu} />
      <div className="line-text" contentEditable suppressContentEditableWarning spellCheck={false}>
        {initial}
      </div>
    </div>
  );
}
