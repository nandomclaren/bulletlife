import { useState } from 'react';
import { localDb } from '../data/spikeDb';
import { t } from '../i18n/en';
import { CHECK_IDS } from './CheckCard';
import { deviceLabel, getFacts, isStandalone } from './facts';
import {
  BackCheck,
  CaretCheck,
  CloudCheck,
  FontCheck,
  InstallCheck,
  LongPressCheck,
  OfflineCheck,
  PersistCheck,
  PersistenceCheck,
  RichCopyCheck,
  SelectionCheck,
  ShareCheck,
  SwipeCheck,
} from './checks';

async function buildReport() {
  const results = new Map((await localDb.results.toArray()).map((r) => [r.id, r]));
  const lines = [
    `## ${t.appName} device check · ${deviceLabel()} · ${new Date().toISOString()}`,
    '',
    `- User agent: \`${navigator.userAgent}\``,
    `- Standalone: ${isStandalone()}`,
    `- Build: ${__BUILD_ID__}`,
    '',
    '| Check | Result | Detected | Notes |',
    '|---|---|---|---|',
  ];
  for (const id of CHECK_IDS) {
    const r = results.get(id);
    const facts = getFacts(id)
      .map(([k, v]) => `${k}: ${v}`)
      .join('; ');
    const cell = (s: string) => s.replace(/\|/g, '\\|').replace(/\n/g, ' ');
    lines.push(`| ${t.checks[id].title} | ${r?.status ?? '—'} | ${cell(facts)} | ${cell(r?.note ?? '')} |`);
  }
  return lines.join('\n');
}

export function SpikePage() {
  const [copied, setCopied] = useState(false);
  return (
    <main className="page">
      <p className="eyebrow">{t.appName}</p>
      <h1>{t.spike.title}</h1>
      <p className="lede">{t.spike.subtitle}</p>
      <InstallCheck />
      <OfflineCheck />
      <PersistenceCheck />
      <PersistCheck />
      <CloudCheck />
      <ShareCheck />
      <RichCopyCheck />
      <SelectionCheck />
      <LongPressCheck />
      <SwipeCheck />
      <BackCheck />
      <FontCheck />
      <CaretCheck />
      <div className="report-bar">
        <button
          className="btn btn-primary"
          onClick={async () => {
            await navigator.clipboard.writeText(await buildReport());
            setCopied(true);
            setTimeout(() => setCopied(false), 2000);
          }}
        >
          {copied ? t.spike.reportCopied : t.spike.copyReport}
        </button>
      </div>
    </main>
  );
}
