import { useCallback, useState } from 'react';
import { KeyboardBar, type EditorApi } from '../editor/KeyboardBar';
import { SAMPLE_LINES, toEntries, type Line } from '../editor/lines';
import { t } from '../i18n/en';
import { navigate } from '../router';
import { LineEditor } from './LineEditor';
import { PmEditor } from './PmEditor';

type Kind = 'a' | 'b';
const storageKey = (kind: Kind) => `proto.${kind}.lines`;

function load(kind: Kind): Line[] {
  try {
    const raw = localStorage.getItem(storageKey(kind));
    if (raw) return JSON.parse(raw) as Line[];
  } catch {
    // fall back to the sample
  }
  return SAMPLE_LINES;
}

function save(kind: Kind, lines: Line[]) {
  try {
    localStorage.setItem(storageKey(kind), JSON.stringify(lines));
  } catch {
    // prototype only
  }
}

export function ProtoPage({ kind }: { kind: Kind }) {
  const [initial, setInitial] = useState(() => load(kind));
  const [version, setVersion] = useState(0);
  const [lines, setLines] = useState(initial);
  const [api, setApi] = useState<EditorApi | null>(null);
  const [focused, setFocused] = useState(false);
  const [showModel, setShowModel] = useState(false);

  const onChange = useCallback(
    (next: Line[]) => {
      setLines(next);
      save(kind, next);
    },
    [kind],
  );

  const Editor = kind === 'a' ? PmEditor : LineEditor;
  const other: Kind = kind === 'a' ? 'b' : 'a';

  return (
    <main className="page page-editor">
      <nav className="proto-nav">
        <button className="link" onClick={() => navigate('/')}>
          ‹ {t.proto.chooseTitle}
        </button>
        <button className="link" onClick={() => navigate(`/proto/${other}`)}>
          {t.proto.other} ›
        </button>
      </nav>
      <p className="eyebrow">
        {t.proto.eyebrow} · {kind === 'a' ? t.proto.a : t.proto.b}
      </p>
      <h1>{t.proto.pageTitle}</h1>
      <Editor key={`${kind}-${version}`} initial={initial} onChange={onChange} onApi={setApi} onFocusChange={setFocused} />
      <p className="hint">{t.proto.hint}</p>
      <div className="row">
        <button className="btn btn-quiet" onClick={() => setShowModel((v) => !v)}>
          {showModel ? t.proto.hideModel : t.proto.showModel}
        </button>
        <button
          className="btn btn-quiet"
          onClick={() => {
            save(kind, SAMPLE_LINES);
            setInitial(SAMPLE_LINES);
            setLines(SAMPLE_LINES);
            setVersion((v) => v + 1);
          }}
        >
          {t.proto.reset}
        </button>
      </div>
      {showModel && <pre className="model">{JSON.stringify(toEntries(lines), null, 2)}</pre>}
      <KeyboardBar api={api} visible={focused} />
    </main>
  );
}

export function ProtoChooser() {
  return (
    <main className="page">
      <p className="eyebrow">{t.appName}</p>
      <h1>{t.proto.chooseTitle}</h1>
      <p className="lede">{t.proto.chooseLede}</p>
      <div className="choices">
        <button className="choice" onClick={() => navigate('/proto/a')}>
          {t.proto.a}
        </button>
        <button className="choice" onClick={() => navigate('/proto/b')}>
          {t.proto.b}
        </button>
      </div>
      <div className="proto-nav">
        <button className="link" onClick={() => navigate('/settings')}>
          {t.proto.settings} ›
        </button>
        <button className="link" onClick={() => navigate('/check')}>
          {t.proto.deviceCheck} ›
        </button>
      </div>
    </main>
  );
}
