// Month day rows (CLAUDE.md 3.6): when a phrase does not fit on one line,
// shrink its font gradually down to 85% (never below 14 px); if it still does
// not fit, let it wrap and the row grow. Text is never truncated or hidden.

const MIN_SCALE = 0.85;
const MIN_PX = 14;

function fit(el: HTMLElement) {
  el.style.fontSize = '';
  const base = parseFloat(getComputedStyle(el).fontSize);
  el.style.whiteSpace = 'nowrap';
  const needed = el.scrollWidth;
  const available = el.clientWidth;
  el.style.whiteSpace = '';
  if (needed <= available || !available) return;
  const min = Math.max(base * MIN_SCALE, MIN_PX);
  const size = Math.max(min, Math.floor((base * available) / needed * 10) / 10);
  if (size < base) el.style.fontSize = `${size}px`;
}

/** Keeps every day row's text fitted while typing and on resize. Returns a cleanup. */
export function fitDayRows(container: HTMLElement): () => void {
  let frame = 0;
  const run = () => {
    cancelAnimationFrame(frame);
    frame = requestAnimationFrame(() => container.querySelectorAll<HTMLElement>('.day-text .line-text').forEach(fit));
  };
  const mo = new MutationObserver(run);
  mo.observe(container, { subtree: true, childList: true, characterData: true });
  const ro = new ResizeObserver(run);
  ro.observe(container);
  run();
  return () => {
    cancelAnimationFrame(frame);
    mo.disconnect();
    ro.disconnect();
  };
}
