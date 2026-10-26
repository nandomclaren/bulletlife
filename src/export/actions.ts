// Copy As, Export and Share (CLAUDE.md 7). Everything here runs synchronously
// inside the tap: Safari only allows clipboard and share right after a gesture,
// so the document is prepared beforehand (when the menu opens).
import { toHtml, toMarkdown, toPlain, type ExportDoc, type Format, type GlyphStyle } from './format';

export function render(doc: ExportDoc, format: Format, style: GlyphStyle) {
  if (format === 'markdown') return { text: toMarkdown(doc, style), mime: 'text/markdown', ext: 'md' };
  if (format === 'plain') return { text: toPlain(doc), mime: 'text/plain', ext: 'txt' };
  return { text: toHtml(doc), mime: 'text/html', ext: 'html', plain: toPlain(doc) };
}

/** Copy As. Rich text goes as HTML plus a plain-text fallback for apps that only take text. */
export async function copyAs(doc: ExportDoc, format: Format, style: GlyphStyle): Promise<boolean> {
  const out = render(doc, format, style);
  const items: Record<string, Blob> = { 'text/plain': new Blob([format === 'rich' ? out.plain! : out.text], { type: 'text/plain' }) };
  if (format === 'rich') items['text/html'] = new Blob([out.text], { type: 'text/html' });
  try {
    if (typeof ClipboardItem !== 'undefined' && navigator.clipboard?.write) {
      await navigator.clipboard.write([new ClipboardItem(items)]);
      return true;
    }
  } catch {
    // fall back below
  }
  // Fallback: a copy event carrying our data.
  const onCopy = (e: ClipboardEvent) => {
    e.preventDefault();
    e.clipboardData?.setData('text/plain', format === 'rich' ? out.plain! : out.text);
    if (format === 'rich') e.clipboardData?.setData('text/html', out.text);
  };
  document.addEventListener('copy', onCopy, { once: true });
  const ok = document.execCommand('copy');
  document.removeEventListener('copy', onCopy);
  return ok;
}

const coarse = () => window.matchMedia('(pointer: coarse)').matches;

export function fileName(title: string, ext: string) {
  const slug = title
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^\w]+/g, '-')
    .replace(/^-|-$/g, '')
    .toLowerCase();
  return `${slug || 'bullet-life'}.${ext}`;
}

/** Export: a file. iPhone: the share sheet (Save to Files); Mac: a download. */
export async function exportFile(name: string, text: string | Blob, mime: string) {
  const file = new File([text], name, { type: mime });
  if (coarse() && navigator.canShare?.({ files: [file] })) {
    try {
      await navigator.share({ files: [file], title: name });
      return;
    } catch (e) {
      if ((e as Error).name === 'AbortError') return;
    }
  }
  const url = URL.createObjectURL(file);
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
}

export const canShare = () => typeof navigator.share === 'function';

/** Share: the system share sheet with the text (rich text is shared as plain text). */
export async function shareAs(doc: ExportDoc, format: Format, style: GlyphStyle) {
  const out = render(doc, format, style);
  try {
    await navigator.share({ title: doc.title || undefined, text: format === 'rich' ? out.plain : out.text });
  } catch {
    // cancelled
  }
}
