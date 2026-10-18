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
