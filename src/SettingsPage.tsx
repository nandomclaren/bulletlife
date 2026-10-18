import { useState } from 'react';
import { t } from './i18n/en';
import { navigate } from './router';
import { getTheme, setTheme, THEMES, type ThemePref } from './theme';

export function SettingsPage() {
  const [theme, setThemeState] = useState<ThemePref>(getTheme);
  return (
    <main className="page">
      <button className="link" onClick={() => (history.length > 1 ? history.back() : navigate('/'))}>
        ‹ {t.nav.back}
      </button>
      <h1>{t.settings.title}</h1>
      <section className="setting">
        <h2 id="theme-label">{t.settings.theme}</h2>
        <div className="options" role="radiogroup" aria-labelledby="theme-label">
          {THEMES.map((th) => (
            <button
              key={th}
              role="radio"
              aria-checked={theme === th}
              className="option"
              onClick={() => {
                setTheme(th);
                setThemeState(th);
              }}
            >
              <span className={`swatch swatch-${th}`} aria-hidden />
              <span className="option-text">
                <span className="option-title">{t.settings.themes[th]}</span>
                <span className="option-hint">{t.settings.themeHints[th]}</span>
              </span>
            </button>
          ))}
        </div>
      </section>
    </main>
  );
}
