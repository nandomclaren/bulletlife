// The page menu "…" (CLAUDE.md 7): Copy As, Export and Share in Markdown, Rich
// Text or Plain Text, for the whole page or only the selected lines.
import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import type { Weekday } from '../dates';
import { useSettings } from '../data/repo';
import { t } from '../i18n/en';
import { flushAll } from '../pages/flush';
import { canShare, copyAs, exportFile, fileName, render, shareAs } from './actions';
import { buildPdf } from './pdf';
import { selectionDoc, type ExportDoc, type Format } from './format';
import { buildPageDoc, type PageRef } from './pageDoc';
import { useStoredSelection } from './selection';

const FORMATS: Format[] = ['markdown', 'rich', 'plain'];
const FORMAT_KEY = 'export.format';

function savedFormat(): Format {
  try {
    const f = localStorage.getItem(FORMAT_KEY) as Format | null;
    return f && FORMATS.includes(f) ? f : 'markdown';
  } catch {
    return 'markdown';
  }
}

export function PageMenu({ page }: { page: PageRef }) {
  const [open, setOpen] = useState(false);
  const button = useRef<HTMLButtonElement>(null);
  return (
    <>
      <button ref={button} className="page-menu-btn" aria-label={t.pageMenu.open} aria-expanded={open} onClick={() => setOpen((o) => !o)}>
        <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
          <circle cx="5" cy="12" r="1.7" />
          <circle cx="12" cy="12" r="1.7" />
          <circle cx="19" cy="12" r="1.7" />
        </svg>
      </button>
      {open && <MenuPanel page={page} anchor={button.current!} onClose={() => setOpen(false)} />}
    </>
  );
}

function MenuPanel({ page, anchor, onClose }: { page: PageRef; anchor: HTMLElement; onClose: () => void }) {
  const settings = useSettings();
  const style = settings.markdownGlyphs ?? 'checkboxes';
  const selection = useStoredSelection();
  const [useSelection, setUseSelection] = useState(!!selection);
  const [format, setFormat] = useState<Format>(savedFormat);
  const [pageDoc, setPageDoc] = useState<ExportDoc | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  // The PDF is made ahead too: on the iPad the share sheet only opens right inside the tap.
  const [pdf, setPdf] = useState<Blob | null>(null);
  const ref = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState<{ top: number; right: number } | null>(null);

  // Prepare the document now, so the actions run right inside the tap.
  const pageKey = JSON.stringify(page);
  useEffect(() => {
    let alive = true;
    void flushAll()
      .then(() => buildPageDoc(page, settings.firstDayOfWeek as Weekday))
      .then((d) => {
        if (!alive) return;
        setPageDoc(d);
        return buildPdf([page], settings.firstDayOfWeek as Weekday, settings.doneMark).then((b) => alive && setPdf(b.blob));
      });
    return () => {
      alive = false;
    };
  }, [pageKey, settings.firstDayOfWeek]); // eslint-disable-line react-hooks/exhaustive-deps

  useLayoutEffect(() => {
    const r = anchor.getBoundingClientRect();
    setPos({ top: r.bottom + 6, right: Math.max(8, window.innerWidth - r.right) });
  }, [anchor]);

  useEffect(() => {
    const onDown = (e: PointerEvent) => !ref.current?.contains(e.target as Node) && !anchor.contains(e.target as Node) && onClose();
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    document.addEventListener('pointerdown', onDown, true);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('pointerdown', onDown, true);
      document.removeEventListener('keydown', onKey);
    };
  }, [anchor, onClose]);

  // A selection is copied as bare lines, like ⌘C; the page title belongs to the whole page.
  const doc = useSelection && selection ? selectionDoc(selection) : pageDoc;
  const ready = !!doc;
  const pick = (f: Format) => {
    setFormat(f);
    try {
      localStorage.setItem(FORMAT_KEY, f);
    } catch {
      // remembered for this session only
    }
  };
  const flash = (text: string) => {
    setToast(text);
    setTimeout(() => {
      setToast(null);
      onClose();
    }, 1400);
  };

  return createPortal(
    <div
      ref={ref}
      className="bullet-menu page-menu"
      role="dialog"
      aria-label={t.pageMenu.open}
      style={pos ? { top: pos.top, right: pos.right } : { visibility: 'hidden' }}
      onMouseDown={(e) => e.preventDefault()}
    >
      {selection && (
        <div className="menu-section" role="radiogroup" aria-label={t.pageMenu.scope}>
          <div className="menu-section-title">{t.pageMenu.scope}</div>
          <div className="menu-chips">
            <button role="radio" aria-checked={!useSelection} className="menu-chip" onClick={() => setUseSelection(false)}>
              {t.pageMenu.wholePage}
            </button>
            <button role="radio" aria-checked={useSelection} className="menu-chip" onClick={() => setUseSelection(true)}>
              {t.pageMenu.selection(selection.length)}
            </button>
          </div>
        </div>
      )}
      <div className="menu-section" role="radiogroup" aria-label={t.pageMenu.format}>
        <div className="menu-section-title">{t.pageMenu.format}</div>
        <div className="menu-chips">
          {FORMATS.map((f) => (
            <button key={f} role="radio" aria-checked={format === f} className="menu-chip" onClick={() => pick(f)}>
              {t.pageMenu.formats[f]}
            </button>
          ))}
        </div>
      </div>
      <div className="menu-actions">
        <button
          disabled={!ready}
          onClick={async () => {
            if (!doc) return;
            const ok = await copyAs(doc, format, style);
            flash(ok ? t.pageMenu.copied(t.pageMenu.formats[format]) : t.pageMenu.copyFailed);
          }}
        >
          {ready ? t.pageMenu.copy : t.pageMenu.preparing}
        </button>
        <button
          disabled={!ready}
          onClick={async () => {
            if (!doc) return;
            const out = render(doc, format, style);
            await exportFile(fileName(doc.title, out.ext), out.text, out.mime);
            onClose();
          }}
        >
          {t.pageMenu.export}
        </button>
        <button
          disabled={!pdf}
          onClick={async () => {
            if (!pdf || !pageDoc) return;
            await exportFile(fileName(pageDoc.title, 'pdf'), pdf, 'application/pdf');
            onClose();
          }}
        >
          {pdf ? t.pageMenu.pdf : t.pageMenu.pdfPreparing}
        </button>
        {canShare() && (
          <button
            disabled={!ready}
            onClick={async () => {
              if (!doc) return;
              await shareAs(doc, format, style);
              onClose();
            }}
          >
            {t.pageMenu.share}
          </button>
        )}
      </div>
      {toast && (
        <div className="undo-toast page-menu-toast" role="status">
          {toast}
        </div>
      )}
    </div>,
    document.body,
  );
}
