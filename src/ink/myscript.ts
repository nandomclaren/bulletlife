// Handwriting recognition by MyScript's cloud (stage 2, a test before an
// on-device recognizer). The request format follows MyScript's own client,
// iink-ts (HTTPClientV2): strokes in mm, signed with HMAC-SHA512.
import { strokeBox, type Stroke } from './ink';

export type HandwritingLang = 'pt_BR' | 'en_US';

export interface MyScriptKeys {
  applicationKey: string;
  hmacKey: string;
}

const URL = 'https://cloud.myscript.com/api/v4.0/iink/recognize';
/** CSS px to mm at 96 dpi, as iink-ts sends it. */
const SCALE = 0.265;

/** The request body: our strokes have no timestamps, so points get evenly spaced times in writing order. */
export function requestBody(strokes: Stroke[], lang: HandwritingLang) {
  let t = 0;
  return {
    configuration: {
      lang,
      text: { guides: { enable: false }, margin: { top: 0, left: 0, right: 0, bottom: 0 } },
      export: { jiix: { 'bounding-box': false, strokes: false, text: { chars: false, words: false } } },
    },
    scaleX: SCALE,
    scaleY: SCALE,
    contentType: 'Text',
    strokes: strokes.map((s, i) => {
      const x: number[] = [];
      const y: number[] = [];
      const p: number[] = [];
      const ts: number[] = [];
      for (let j = 0; j < s.p.length; j += 3) {
        x.push(s.p[j]);
        y.push(s.p[j + 1]);
        p.push(s.p[j + 2]);
        ts.push((t += 8));
      }
      t += 120;
      return { id: `s${i}`, pointerType: 'pen', x, y, t: ts, p };
    }),
  };
}

export async function hmac(message: string, keys: MyScriptKeys): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey('raw', enc.encode(keys.applicationKey + keys.hmacKey), { name: 'HMAC', hash: { name: 'SHA-512' } }, false, [
    'sign',
  ]);
  const sig = new Uint8Array(await crypto.subtle.sign('HMAC', key, enc.encode(message)));
  return Array.from(sig, (b) => b.toString(16).padStart(2, '0')).join('');
}

export class RecognizeError extends Error {
  constructor(
    message: string,
    readonly auth = false,
  ) {
    super(message);
  }
}

/** Plain text of these strokes (one handwritten line). */
export async function recognize(strokes: Stroke[], lang: HandwritingLang, keys: MyScriptKeys): Promise<string> {
  if (!strokes.length) return '';
  // Shift to the origin: only the shapes matter, and smaller numbers keep the request small.
  const box = strokes.map((s) => strokeBox(s.p)).reduce((a, b) => ({ x0: Math.min(a.x0, b.x0), y0: Math.min(a.y0, b.y0), x1: 0, y1: 0 }));
  const moved = strokes.map((s) => ({ ...s, p: s.p.map((v, i) => (i % 3 === 0 ? v - box.x0 : i % 3 === 1 ? v - box.y0 : v)) }));
  const body = JSON.stringify(requestBody(moved, lang));
  const res = await fetch(URL, {
    method: 'POST',
    credentials: 'omit',
    headers: {
      Accept: 'text/plain',
      'Content-Type': 'application/json',
      applicationKey: keys.applicationKey,
      hmac: await hmac(body, keys),
    },
    body,
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new RecognizeError(`${res.status} ${text}`.trim(), res.status === 401 || res.status === 403 || text.includes('access.not.granted'));
  }
  return (await res.text()).replace(/\s+/g, ' ').trim();
}
