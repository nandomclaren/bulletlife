// PDF of the notebook in A5, to print and keep (Fernando: "the journal, in my
// own handwriting"). Pages are drawn as vectors from the stored entries: the
// handwriting where it was written (as in Pen mode), drawings, and typed
// entries with their colored bullets. Plain sheet, no rules. jsPDF is loaded
// only when exporting.
import type { jsPDF } from 'jspdf';
import { addDays, addMonths, fmt, monthDays, todayIso, weekKey, weekKeyStart, type Weekday } from '../dates';
import { DUE_TOKEN } from '../editor/due';
import { stripInline } from '../editor/inline';
import { colorTypes, type Line, type LineType } from '../editor/lines';
import { t } from '../i18n/en';
import { hasInk, hasWriting, inkRows, ROW, strokeBox, strokeOutline, type Ink } from '../ink/ink';
import { COLORS } from './format';
import { buildPageDoc, type PageRef } from './pageDoc';

// ---------- page geometry (mm) ----------

const PAGE = { w: 148, h: 210 };
const M = { left: 14, right: 12, top: 16, bottom: 16 };
/** Pen mode sheet width (px) mapped onto the text area: handwriting keeps its proportions. */
const SHEET_W = 740;
const S = (PAGE.w - M.left - M.right) / SHEET_W;
const ROW_MM = ROW * S;
const GUTTER = 60;
const STEP = 26;
const INK = '#1F1D1A';
const MUTED = '#8A857C';
const TEXT_PT = 9;

interface PdfPage {
  eyebrow: string;
  title: string;
  /** A Month page lists every day; other pages list sections (Year months, Month tasks) or just lines. */
  days?: Array<{ iso: string; lines: Line[] }>;
  sections: Array<{ heading?: string; lines: Line[] }>;
}

const colorOf = (token: string) =>
  token === 'task' ? COLORS.task : token === 'event' ? COLORS.event : token === 'note' ? COLORS.note : token === 'ink' ? INK : MUTED;

/** Typed text as it reads on paper: no Markdown markers, due dates as short labels. */
function plain(text: string): string {
  const t2 = text.replace(new RegExp(DUE_TOKEN.source, 'g'), (_m, iso: string) => `(${fmt(iso, { month: 'short', day: 'numeric' })})`);
  return stripInline(t2).replace(/\s+/g, ' ').trim();
}

class Writer {
  y = M.top;
  /** Height of one typed line (a Month packs its days tighter so the month fits one sheet). */
  row = ROW_MM;
  constructor(readonly doc: jsPDF) {}

  get bottom() {
    return PAGE.h - M.bottom;
  }

  newPage() {
    this.doc.addPage();
    this.y = M.top;
  }

  /** Room for `h` mm, or a new page. */
  ensure(h: number) {
    if (this.y + h > this.bottom && this.y > M.top + 1) this.newPage();
  }

  header(eyebrow: string, title: string) {
    const d = this.doc;
    d.setFont('helvetica', 'bold');
    d.setFontSize(6.5);
    d.setTextColor(MUTED);
    d.text(eyebrow.toUpperCase(), M.left, this.y + 2, { charSpace: 0.35 });
    d.setFontSize(16);
    d.setTextColor(INK);
    d.text(title, M.left, this.y + 10);
    this.y += 17;
  }

  sectionHeading(text: string) {
    this.ensure(ROW_MM * 2);
    const d = this.doc;
    d.setFont('helvetica', 'bold');
    d.setFontSize(7.5);
    d.setTextColor(MUTED);
    d.text(text.toUpperCase(), M.left + GUTTER * S, this.y + ROW_MM * 0.7, { charSpace: 0.3 });
    this.y += ROW_MM;
  }

  // ---------- marks (bullets and states, drawn as shapes so any font works) ----------

  mark(kind: 'dot' | 'circle' | 'dash' | 'check' | 'cross' | 'migrated' | 'scheduled', cx: number, cy: number, color: string) {
    const d = this.doc;
    d.setDrawColor(color);
    d.setFillColor(color);
    d.setLineWidth(0.3);
    d.setLineCap('round');
    const r = 0.55;
    switch (kind) {
      case 'dot':
        d.circle(cx, cy, r, 'F');
        break;
      case 'circle':
        d.circle(cx, cy, r + 0.35, 'S');
        break;
      case 'dash':
        d.line(cx - 0.9, cy, cx + 0.9, cy);
        break;
      case 'check':
        d.lines(
          [
            [0.55, 0.6],
            [1.3, -1.5],
          ],
          cx - 0.95,
          cy + 0.1,
          [1, 1],
          'S',
        );
        break;
      case 'cross':
        d.line(cx - 0.8, cy - 0.8, cx + 0.8, cy + 0.8);
        d.line(cx - 0.8, cy + 0.8, cx + 0.8, cy - 0.8);
        break;
      case 'migrated':
        d.lines(
          [
            [1.2, 0.85],
            [-1.2, 0.85],
          ],
          cx - 0.6,
          cy - 0.85,
          [1, 1],
          'S',
        );
        break;
      case 'scheduled':
        d.lines(
          [
            [-1.2, 0.85],
            [1.2, 0.85],
          ],
          cx + 0.6,
          cy - 0.85,
          [1, 1],
          'S',
        );
        break;
    }
  }

  stateMark(l: Line, cx: number, cy: number, color: string, doneMark: 'cross' | 'check') {
    if (l.type === 'note') return this.mark('dash', cx, cy, color);
    if (l.type !== 'task' && l.type !== 'event') return;
    if (l.state === 'done') return this.mark(doneMark, cx, cy, color);
    if (l.state === 'migrated') return this.mark('migrated', cx, cy, color);
    if (l.state === 'scheduled') return this.mark('scheduled', cx, cy, color);
    return this.mark(l.type === 'task' ? 'dot' : 'circle', cx, cy, color);
  }

  // ---------- lines ----------

  /** A page's lines, `dx` mm to the right (Month days sit after the day number). */
  lines(lines: Line[], doneMark: 'cross' | 'check', dx = 0) {
    // Collapsed children print too: collapsing never changes what is exported.
    const colors = colorTypes(lines);
    lines.forEach((l, i) => {
      // Transcribed handwriting prints as handwriting, corrected or not (the ink is the original).
      const handwritten = hasWriting(l.ink) && (l.ink!.tx !== undefined || !l.text.trim());
      if (handwritten) this.ink(l, l.ink!, colors[i], doneMark, dx);
      else {
        if (l.text.trim() || l.type !== 'text') this.typed(l, colors[i], doneMark, dx);
        else if (!hasInk(l.ink)) this.y += ROW_MM * 0.6; // a blank line keeps a little air
        if (hasInk(l.ink)) {
          const drawing = l.ink!.strokes.filter((s) => s.k === 'd');
          if (drawing.length) this.ink(l, { strokes: drawing }, colors[i], doneMark, dx);
        }
      }
    });
  }

  typed(l: Line, color: LineType, doneMark: 'cross' | 'check', dx: number) {
    const d = this.doc;
    const indent = l.indent * STEP;
    const textX = M.left + dx + (indent + GUTTER) * S;
    const width = PAGE.w - M.right - textX;
    const heading = l.type === 'heading';
    d.setFont('helvetica', heading ? 'bold' : 'normal');
    d.setFontSize(heading ? 11 : TEXT_PT);
    const sig = (l.priority ? '* ' : '') + (l.inspiration ? '! ' : '');
    const rows: string[] = d.splitTextToSize(sig + plain(l.text), width);
    const h = Math.max(1, rows.length) * this.row;
    this.ensure(h);
    const base = this.y + this.row * 0.66;
    const faded = l.state === 'done' || l.state === 'cancelled';
    if (!heading && l.type !== 'text') this.stateMark(l, M.left + dx + (indent + 46) * S, base - 1.05, colorOf(color), doneMark);
    d.setTextColor(faded ? MUTED : INK);
    rows.forEach((row, k) => {
      const y = base + k * this.row;
      d.text(row, textX, y);
      if (l.state === 'cancelled' && l.type !== 'note') {
        d.setDrawColor(MUTED);
        d.setLineWidth(0.2);
        d.line(textX, y - 1.1, textX + d.getTextWidth(row), y - 1.1);
      }
    });
    this.y += h;
  }

  /** Handwriting and drawings, as written in Pen mode (sheet coordinates scaled to the page). */
  ink(l: Line, ink: Ink, color: LineType, doneMark: 'cross' | 'check', dx: number) {
    const d = this.doc;
    const rows = Math.max(1, inkRows(ink));
    let k = 1;
    const room = PAGE.h - M.top - M.bottom;
    if (rows * ROW_MM > room) k = room / (rows * ROW_MM); // a drawing taller than a page is scaled to fit
    this.ensure(rows * ROW_MM * k);
    const x0 = M.left + dx;
    const y0 = this.y;
    const typeColor = color === 'task' || color === 'event' || color === 'note' ? colorOf(color) : null;
    const bullet = ink.strokes.find((s) => s.b);
    const marked = !!bullet && l.state !== 'open' && l.state !== 'cancelled' && (l.type === 'task' || l.type === 'event');
    const faded = l.state === 'done' || l.state === 'cancelled';
    for (const s of ink.strokes) {
      if (s.b && marked) continue;
      const outline = strokeOutline(s);
      if (outline.length < 3) continue;
      const pts = outline.map(([x, y]) => [x0 + x * S * k, y0 + y * S * k]);
      const deltas = pts.slice(1).map((p, i) => [p[0] - pts[i][0], p[1] - pts[i][1]]);
      const c = s.b && typeColor ? typeColor : colorOf(s.c);
      d.setFillColor(faded && !s.b ? MUTED : c);
      d.lines(deltas, pts[0][0], pts[0][1], [1, 1], 'F', true);
    }
    if (bullet) {
      const b = strokeBox(bullet.p);
      const cx = x0 + ((b.x0 + b.x1) / 2) * S * k;
      const cy = y0 + ((b.y0 + b.y1) / 2) * S * k;
      if (marked) this.stateMark(l, cx, cy, typeColor ?? INK, doneMark);
      if (l.state === 'cancelled') {
        const words = ink.strokes.filter((s) => s.k === 'w' && !s.b).map((s) => strokeBox(s.p));
        if (words.length) {
          d.setDrawColor(MUTED);
          d.setLineWidth(0.25);
          d.line(x0 + Math.min(...words.map((w) => w.x0)) * S * k, cy, x0 + Math.max(...words.map((w) => w.x1)) * S * k, cy);
        }
      }
    }
    this.y += rows * ROW_MM * k;
  }

  /** A Month page: every day with its number and initial, week rules, and what was written on each day. */
  month(ym: string, days: Array<{ iso: string; lines: Line[] }>, firstDay: Weekday, doneMark: 'cross' | 'check') {
    const d = this.doc;
    const dx = 10; // day number and initial
    // Every day gets a line; the whole month fits one sheet when it can (as a printed month spread).
    const slots = days.reduce((n, d) => n + Math.max(1, d.lines.length), 0);
    const rules = days.filter((d, i) => i > 0 && new Date(`${d.iso}T12:00:00`).getDay() === firstDay).length;
    this.row = Math.max(3.6, Math.min(ROW_MM, (this.bottom - this.y - rules * 1.2) / slots));
    days.forEach(({ iso, lines }, i) => {
      const date = new Date(`${iso}T12:00:00`);
      if (i > 0 && date.getDay() === firstDay) {
        this.ensure(this.row);
        d.setDrawColor('#D9D4CB');
        d.setLineWidth(0.15);
        d.line(M.left, this.y + 0.6, PAGE.w - M.right, this.y + 0.6);
        d.setFont('helvetica', 'normal');
        d.setFontSize(5.5);
        d.setTextColor(MUTED);
        d.text(`Wk ${Number(weekKey(iso, firstDay).split('-W')[1])}`, PAGE.w - M.right, this.y + 2.6, { align: 'right' });
        this.y += 1.2;
      }
      this.ensure(this.row);
      const base = this.y + this.row * 0.66;
      const weekend = date.getDay() === 0 || date.getDay() === 6;
      d.setFont('helvetica', 'bold');
      d.setFontSize(8);
      d.setTextColor(weekend ? MUTED : INK);
      d.text(String(date.getDate()), M.left, base);
      d.setFont('helvetica', 'normal');
      d.setFontSize(6);
      d.setTextColor(MUTED);
      d.text(fmt(iso, { weekday: 'narrow' }), M.left + 5.2, base);
      if (lines.length) this.lines(lines, doneMark, dx - GUTTER * S + 1);
      else this.y += this.row;
    });
    this.row = ROW_MM;
    void ym;
  }
}

/** The pages of the PDF for these notebook pages (each starts on a new sheet). */
async function pagesFor(refs: PageRef[], firstDay: Weekday): Promise<PdfPage[]> {
  return Promise.all(
    refs.map(async (ref): Promise<PdfPage> => {
      const doc = await buildPageDoc(ref, firstDay);
      switch (ref.kind) {
        case 'daily':
          return {
            eyebrow: fmt(ref.key, { weekday: 'long' }),
            title: fmt(ref.key, { month: 'long', day: 'numeric', year: 'numeric' }),
            sections: doc.sections,
          };
        case 'weekly': {
          const start = weekKeyStart(ref.key, firstDay);
          const end = addDays(start, 6);
          return {
            eyebrow: `${t.pages.week} ${Number(ref.key.split('-W')[1])}`,
            title: `${fmt(start, { month: 'short', day: 'numeric' })} – ${fmt(end, { month: 'short', day: 'numeric', year: 'numeric' })}`,
            sections: doc.sections,
          };
        }
        case 'monthly': {
          const isos = monthDays(ref.key);
          return {
            eyebrow: fmt(`${ref.key}-01`, { month: 'long' }),
            title: fmt(`${ref.key}-01`, { month: 'long', year: 'numeric' }),
            days: isos.map((iso, i) => ({ iso, lines: doc.sections[i].lines })),
            sections: [doc.sections[doc.sections.length - 1]],
          };
        }
        case 'future':
          return { eyebrow: t.index.kinds.future, title: ref.key, sections: doc.sections };
        case 'collection':
          return { eyebrow: t.index.collections, title: ref.title, sections: doc.sections };
      }
    }),
  );
}

/** Builds the PDF (A5, one notebook page per sheet or more). */
export async function buildPdf(refs: PageRef[], firstDay: Weekday, doneMark: 'cross' | 'check'): Promise<{ blob: Blob; pages: number }> {
  const { jsPDF } = await import('jspdf');
  const doc = new jsPDF({ format: 'a5', unit: 'mm', orientation: 'portrait', compress: true });
  doc.setProperties({ title: 'Bullet Life', creator: 'Bullet Life' });
  const w = new Writer(doc);
  const pages = await pagesFor(refs, firstDay);
  pages.forEach((p, n) => {
    if (n > 0) w.newPage();
    w.header(p.eyebrow, p.title);
    if (p.days) {
      w.month('', p.days, firstDay, doneMark);
      const tasks = p.sections[0];
      if (tasks?.lines.length) {
        w.y += ROW_MM * 0.5;
        w.sectionHeading(tasks.heading ?? t.pages.monthTasks);
        w.lines(tasks.lines, doneMark);
      }
      return;
    }
    for (const s of p.sections) {
      if (s.heading) {
        if (!s.lines.length && refs[n].kind !== 'future') continue;
        w.sectionHeading(s.heading);
      }
      w.lines(s.lines, doneMark);
      if (s.heading) w.y += ROW_MM * 0.4;
    }
  });
  // Page numbers, quietly.
  const total = doc.getNumberOfPages();
  for (let i = 1; i <= total; i++) {
    doc.setPage(i);
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(6);
    doc.setTextColor(MUTED);
    doc.text(String(i), PAGE.w / 2, PAGE.h - 7, { align: 'center' });
  }
  return { blob: doc.output('blob'), pages: total };
}

// ---------- which pages a period covers ----------

export type PdfRange = 'month' | 'year' | 'all';

/**
 * Written pages in notebook order: each Year first, then each month's Month
 * page followed by its weeks and days in date order; Collections at the end
 * (only when exporting everything).
 */
export function pagesInRange(logIds: string[], collections: Array<{ id: string; title: string }>, range: PdfRange, today = todayIso()): PageRef[] {
  const year = today.slice(0, 4);
  const month = today.slice(0, 7);
  const keyed: Array<{ sort: string; ref: PageRef }> = [];
  for (const id of logIds) {
    const [kind, key] = [id.slice(0, id.indexOf(':')), id.slice(id.indexOf(':') + 1)];
    let start = '';
    let end = '';
    let sort = '';
    let ref: PageRef | null = null;
    if (kind === 'future') {
      [start, end, sort, ref] = [`${key}-01-01`, `${key}-12-31`, `${key}-00-00 0`, { kind: 'future', key }];
    } else if (kind === 'monthly') {
      [start, end, sort, ref] = [`${key}-01`, addDays(`${addMonths(key, 1)}-01`, -1), `${key}-00 1`, { kind: 'monthly', key }];
    } else if (kind === 'weekly') {
      const s0 = weekKeyStartAny(key);
      [start, end, sort, ref] = [s0, addDays(s0, 6), `${s0} 2`, { kind: 'weekly', key }];
    } else if (kind === 'daily') {
      [start, end, sort, ref] = [key, key, `${key} 3`, { kind: 'daily', key }];
    }
    if (!ref) continue;
    if (range === 'year' && !(start <= `${year}-12-31` && end >= `${year}-01-01`)) continue;
    if (range === 'month' && !(start <= `${month}-31` && end >= `${month}-01`)) continue;
    keyed.push({ sort, ref });
  }
  keyed.sort((a, b) => (a.sort < b.sort ? -1 : a.sort > b.sort ? 1 : 0));
  const refs = keyed.map((k) => k.ref);
  if (range === 'all')
    for (const c of [...collections].sort((a, b) => a.title.localeCompare(b.title))) refs.push({ kind: 'collection', id: c.id, title: c.title });
  return refs;
}

/** The Monday-based start of an ISO week key ('2026-W43'), whatever the first day setting (only for ordering). */
function weekKeyStartAny(key: string): string {
  return weekKeyStart(key, 1 as Weekday);
}
