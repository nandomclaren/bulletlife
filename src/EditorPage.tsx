// Temporary home: one page of the chosen editor (B, line editor) while the
// real pages (Day, Week, Month, Year) are built on top of it in Phase 1.
import { useCallback, useState } from 'react';
import { LineEditor } from './editor/LineEditor';
import { SAMPLE_LINES, toEntries, type Line } from './editor/lines';
import { t } from './i18n/en';
import { navigate } from './router';

const STORAGE_KEY = 'proto.b.lines';

function load(): Line[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) return JSON.parse(raw) as Line[];
  } catch {
    // fall back to the sample
  }
  return SAMPLE_LINES;
}

function save(lines: Line[]) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(lines));
  } catch {
    // prototype only
  }
}

export function EditorPage() {
  const [initial, setInitial] = useState(load);
  const [version, setVersion] = useState(0);
  const [lines, setLines] = useState(initial);
  const [showModel, setShowModel] = useState(false);

  const onChange = useCallback((next: Line[]) => {
    setLines(next);
    save(next);
  }, []);

  return (
    <main className="page page-editor">
      <nav className="proto-nav">
        <button className="link" onClick={() => navigate('/settings')}>
          {t.proto.settings}
        </button>
        <button className="link" onClick={() => navigate('/check')}>
          {t.proto.deviceCheck}
        </button>
      </nav>
      <p className="eyebrow">{t.proto.eyebrow}</p>
      <h1>{t.proto.pageTitle}</h1>
      <LineEditor key={version} initial={initial} onChange={onChange} />
      <p className="hint">{t.proto.hint}</p>
      <div className="row">
        <button className="btn btn-quiet" onClick={() => setShowModel((v) => !v)}>
          {showModel ? t.proto.hideModel : t.proto.showModel}
        </button>
        <button
          className="btn btn-quiet"
          onClick={() => {
            save(SAMPLE_LINES);
            setInitial(SAMPLE_LINES);
            setLines(SAMPLE_LINES);
            setVersion((v) => v + 1);
          }}
        >
          {t.proto.reset}
        </button>
      </div>
      {showModel && <pre className="model">{JSON.stringify(toEntries(lines), null, 2)}</pre>}
    </main>
  );
}
