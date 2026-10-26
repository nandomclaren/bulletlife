// Theme preference. Stored locally for now; moves into synced Settings later in Phase 1.
export type ThemePref = 'auto' | 'paper' | 'graphite' | 'night';
export const THEMES: ThemePref[] = ['auto', 'paper', 'graphite', 'night'];

const KEY = 'settings.theme';
const BG: Record<Exclude<ThemePref, 'auto'>, string> = { paper: '#FAF8F4', graphite: '#141414', night: '#000000' };

export function getTheme(): ThemePref {
  try {
    const v = localStorage.getItem(KEY) as ThemePref | null;
    return v && THEMES.includes(v) ? v : 'auto';
  } catch {
    return 'auto';
  }
}

export function setTheme(pref: ThemePref) {
  try {
    localStorage.setItem(KEY, pref);
  } catch {
    // still applied for this session
  }
  applyTheme(pref);
}

export function applyTheme(pref: ThemePref = getTheme()) {
  const root = document.documentElement;
  if (pref === 'auto') delete root.dataset.theme;
  else root.dataset.theme = pref;
  // Status bar color on iOS follows theme-color.
  document.querySelectorAll<HTMLMetaElement>('meta[name="theme-color"]').forEach((m) => {
    const isDark = m.media.includes('dark');
    m.content = pref === 'auto' ? (isDark ? BG.graphite : BG.paper) : BG[pref];
  });
}

// Palette: the colors of the task, event and note bullets. Per device, like the theme.
export type Palette = 'classic' | 'earth' | 'dusk' | 'citrus' | 'muted';
export const PALETTES: Palette[] = ['classic', 'earth', 'dusk', 'citrus', 'muted'];
const PALETTE_KEY = 'settings.palette';

export function getPalette(): Palette {
  try {
    const v = localStorage.getItem(PALETTE_KEY) as Palette | null;
    return v && PALETTES.includes(v) ? v : 'classic';
  } catch {
    return 'classic';
  }
}

export function setPalette(p: Palette) {
  try {
    localStorage.setItem(PALETTE_KEY, p);
  } catch {
    // still applied for this session
  }
  applyPalette(p);
}

export function applyPalette(p: Palette = getPalette()) {
  if (p === 'classic') delete document.documentElement.dataset.palette;
  else document.documentElement.dataset.palette = p;
}
