// Settings › Print: a PDF of a period (this month, this year, everything),
// in notebook order. Made first, then saved with a second tap (the iPad's
// share sheet only opens right inside a tap).
import { useState } from 'react';
import { useSettings, writtenPages } from '../data/repo';
import { todayIso, type Weekday } from '../dates';
import { t } from '../i18n/en';
import { flushAll } from '../pages/flush';
import { exportFile } from './actions';
import { buildPdf, pagesInRange, type PdfRange } from './pdf';

const RANGES: PdfRange[] = ['month', 'year', 'all'];

export function PdfSection() {
  const settings = useSettings();
  const [busy, setBusy] = useState<PdfRange | null>(null);
  const [ready, setReady] = useState<{ range: PdfRange; blob: Blob; pages: number } | null>(null);
  const [empty, setEmpty] = useState(false);

  const make = async (range: PdfRange) => {
    setBusy(range);
    setReady(null);
    setEmpty(false);
    try {
      await flushAll();
      const { logIds, collections } = await writtenPages();
      const refs = pagesInRange(
        logIds,
        collections.filter((c) => c.kind === 'collection').map((c) => ({ id: c.id, title: c.title })),
        range,
      );
      if (!refs.length) return setEmpty(true);
      const { blob, pages } = await buildPdf(refs, settings.firstDayOfWeek as Weekday, settings.doneMark);
      setReady({ range, blob, pages });
    } finally {
      setBusy(null);
    }
  };

  return (
    <section className="setting">
      <h2>{t.pdf.title}</h2>
      <div className="pdf-ranges">
        {RANGES.map((r) => (
          <button key={r} className="btn" disabled={!!busy} onClick={() => void make(r)}>
            {busy === r ? t.pdf.preparing : t.pdf.ranges[r]}
          </button>
        ))}
      </div>
      {ready && (
        <button
          className="btn btn-primary"
          onClick={() => void exportFile(`BulletLife_${todayIso().replace(/-/g, '')}_${ready.range}.pdf`, ready.blob, 'application/pdf')}
        >
          {t.pdf.save(ready.pages)}
        </button>
      )}
      {empty && <p className="setting-hint">{t.pdf.empty}</p>}
      <p className="setting-hint">{t.pdf.hint}</p>
    </section>
  );
}
