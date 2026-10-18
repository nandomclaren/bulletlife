import { useLiveQuery } from 'dexie-react-hooks';
import type { ReactNode } from 'react';
import { localDb, type CheckResult } from '../data/spikeDb';
import { t } from '../i18n/en';

export const CHECK_IDS = [
  'install',
  'offline',
  'persistence',
  'persist',
  'cloud',
  'share',
  'richCopy',
  'selection',
  'longPress',
  'swipe',
  'back',
  'font',
  'caret',
] as const;
export type CheckId = (typeof CHECK_IDS)[number];

const STATUSES: Array<Exclude<CheckResult['status'], null>> = ['pass', 'fail', 'unsure'];

export function CheckCard({ id, children }: { id: CheckId; children?: ReactNode }) {
  const copy = t.checks[id];
  const result = useLiveQuery(() => localDb.results.get(id), [id]);
  const save = (patch: Partial<CheckResult>) =>
    localDb.results.put({ id, status: null, note: '', ...result, ...patch });

  return (
    <section className="check" id={`check-${id}`}>
      <h2>{copy.title}</h2>
      <p className="how">{copy.how}</p>
      {children && <div className="check-body">{children}</div>}
      <div className="status" role="radiogroup" aria-label={copy.title}>
        {STATUSES.map((s) => (
          <button
            key={s}
            role="radio"
            aria-checked={result?.status === s}
            className={`chip chip-${s}`}
            onClick={() => save({ status: result?.status === s ? null : s })}
          >
            {t.spike[s]}
          </button>
        ))}
      </div>
      <input
        className="note"
        placeholder={t.spike.notePlaceholder}
        defaultValue={result?.note ?? ''}
        key={result ? 'loaded' : 'loading'}
        onBlur={(e) => save({ note: e.currentTarget.value })}
      />
    </section>
  );
}

export function Fact({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="fact">
      <span className="fact-label">{label}</span>
      <span className="fact-value">{value}</span>
    </div>
  );
}
