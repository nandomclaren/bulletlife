// Transcribes handwriting into text in the background: after a pause in
// writing, when leaving Pen mode, and when the connection comes back. The
// ink is saved first and always; transcription is a bonus that can wait.
import { useSyncExternalStore } from 'react';
import { applyTranscription, pendingTranscriptions, repairInk } from '../data/repo';
import type { Settings } from '../data/types';
import { recognize, RecognizeError } from './myscript';
import { readLineShape } from './structure';

type Status = { state: 'idle' | 'working' | 'offline' | 'no-keys' | 'error'; message?: string };

let status: Status = { state: 'idle' };
const listeners = new Set<() => void>();
const setStatus = (s: Status) => {
  status = s;
  listeners.forEach((l) => l());
};

export function useTranscriptionStatus() {
  return useSyncExternalStore(
    (cb) => {
      listeners.add(cb);
      return () => listeners.delete(cb);
    },
    () => status,
  );
}

const running = new Set<string>();

/** Transcribes every handwritten line of a page that changed since its last transcription. */
export async function transcribePage(logId: string, slot: string, settings: Settings): Promise<void> {
  const keys = { applicationKey: settings.myscriptAppKey?.trim() ?? '', hmacKey: settings.myscriptHmacKey?.trim() ?? '' };
  const key = `${logId}/${slot}`;
  if (running.has(key)) return;
  running.add(key);
  try {
    await repairInk(logId, slot);
    const pending = await pendingTranscriptions(logId, slot);
    if (!pending.length) return;
    if (!keys.applicationKey || !keys.hmacKey) return setStatus({ state: 'no-keys' });
    if (!navigator.onLine) return setStatus({ state: 'offline' });
    setStatus({ state: 'working' });
    for (const e of pending) {
      const strokes = e.ink!.strokes;
      const n = strokes.filter((s) => s.k === 'w').length;
      const shape = readLineShape(strokes);
      const words = strokes.filter((s, i) => s.k === 'w' && !shape.bullet.includes(i));
      const text = words.length ? await recognize(words, settings.handwritingLang, keys) : '';
      await applyTranscription(e.id, n, text, shape);
    }
    setStatus({ state: 'idle' });
  } catch (err) {
    if (err instanceof RecognizeError) setStatus({ state: 'error', message: err.auth ? 'auth' : err.message });
    else setStatus({ state: 'offline' });
  } finally {
    running.delete(key);
  }
}
