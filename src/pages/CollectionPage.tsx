// A collection: a free page the user created and named (CLAUDE.md 3.1).
import { usePane } from './pane';
import { useEffect, useState } from 'react';
import { collectionRef, renameCollection, useLog } from '../data/repo';
import { t } from '../i18n/en';
import { PageMenu } from '../export/PageMenu';
import { PageBody, PenToggle } from '../ink/PageBody';
import { OpenItemsButton } from '../open/OpenItemsButton';
import { SplitButton, SpreadButton } from './SplitPane';

export function CollectionPage({ id }: { id: string }) {
  const { navigate } = usePane();
  const log = useLog(id);
  const [title, setTitle] = useState('');
  useEffect(() => {
    if (log) setTitle(log.title);
  }, [log?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  if (log === undefined) return null;
  if (log === null || log.kind !== 'collection') {
    return (
      <main className="page">
        <button className="link" onClick={() => navigate('/index')}>
          ‹ {t.index.title}
        </button>
        <p className="muted">{t.index.noCollections}</p>
      </main>
    );
  }

  const commit = () => {
    const next = title.trim();
    if (next && next !== log.title) void renameCollection(log.id, next);
    else setTitle(log.title);
  };

  return (
    <main className="page page-time page-collection">
      <header className="time-header">
        <button className="crumb" onClick={() => navigate('/index')}>
          ‹ {t.index.title}
        </button>
      </header>
      <p className="eyebrow">{t.index.collections}</p>
      <div className="title-row">
        <input
          className="title-input"
          aria-label={t.index.namePlaceholder}
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          onBlur={commit}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              (e.target as HTMLInputElement).blur();
            }
          }}
          enterKeyHint="done"
        />
        <PenToggle />
        <OpenItemsButton />
        <SpreadButton flowOnly />
        <SplitButton />
        <PageMenu page={{ kind: 'collection', id: log.id, title: log.title }} />
      </div>
      <PageBody key={log.id} log={collectionRef(log)} label={log.title} flow />
    </main>
  );
}
