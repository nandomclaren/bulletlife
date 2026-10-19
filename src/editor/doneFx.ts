// Micro-animation when an entry is completed (or, quieter, cancelled):
// Settings › Done animation. Pure decoration on the line's DOM; the entry
// itself changes the moment the user taps. Shapes are drawn in CSS
// (editor.css, "Done animations"), so they work with both the cross and the
// check done mark. prefers-reduced-motion turns them off.

export type DoneAnimation = 'ink' | 'pop' | 'ripple' | 'sparks' | 'highlighter' | 'settle' | 'colorSparks';
export const DONE_ANIMATIONS: DoneAnimation[] = ['ink', 'pop', 'ripple', 'sparks', 'highlighter', 'settle', 'colorSparks'];

/** Long enough for the slowest animation (all run 40% slower than their base timing). */
const CLEANUP_MS = 1400;
const timers = new WeakMap<HTMLElement, number>();
const COLORS = ['var(--task)', 'var(--event)', 'var(--note)'];

export function playDoneFx(line: HTMLElement | null | undefined, kind: 'done' | 'cancel') {
  if (!line) return;
  line.classList.remove('fx-done', 'fx-cancel');
  void line.offsetWidth; // restart the animation if it is already running
  line.classList.add(kind === 'done' ? 'fx-done' : 'fx-cancel');
  const bullet = line.querySelector('.bullet');
  bullet?.querySelector('.fx')?.remove();
  const anim = document.documentElement.dataset.doneAnim as DoneAnimation | undefined;
  if (bullet && (anim === 'ripple' || anim === 'sparks' || anim === 'colorSparks')) {
    const fx = document.createElement('span');
    fx.className = 'fx';
    fx.setAttribute('aria-hidden', 'true');
    if (anim === 'ripple') fx.append(Object.assign(document.createElement('span'), { className: 'fx-ring' }));
    else
      for (let i = 0; i < 6; i++) {
        const dot = document.createElement('i');
        dot.style.setProperty('--a', `${i * 60}deg`);
        if (anim === 'colorSparks') dot.style.setProperty('--c', COLORS[i % 3]);
        fx.append(dot);
      }
    bullet.append(fx);
  }
  window.clearTimeout(timers.get(line));
  timers.set(
    line,
    window.setTimeout(() => {
      line.classList.remove('fx-done', 'fx-cancel');
      line.querySelector('.bullet .fx')?.remove();
    }, CLEANUP_MS),
  );
}
