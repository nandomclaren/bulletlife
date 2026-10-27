import { useState, type ReactNode } from 'react';
import { usePane } from './pages/pane';
import { BackupSection } from './BackupSection';
import { PdfSection } from './export/PdfSection';
import { resendLeft, signIn, signOut, syncNow, updateSettings, useSettings, useSync } from './data/repo';
import { isLastActive, toggleActiveLog, type TimeLog } from './data/settings';
import { t } from './i18n/en';
import { DONE_ANIMATIONS, playDoneFx } from './editor/doneFx';
import { useTranscriptionStatus } from './ink/transcribe';
import { getPalette, getTheme, PALETTES, setPalette, setTheme, THEMES, type Palette, type ThemePref } from './theme';

const TIME_LOGS: TimeLog[] = ['monthly', 'weekly', 'daily'];

export function SettingsPage() {
  const { back } = usePane();
  const settings = useSettings();
  const [theme, setThemeState] = useState<ThemePref>(getTheme);
  const [palette, setPaletteState] = useState<Palette>(getPalette);
  const sync = useSync();
  return (
    <main className="page">
      <button className="link" onClick={back}>
        ‹ {t.nav.back}
      </button>
      <h1>{t.settings.title}</h1>

      <section className="setting">
        <h2>{t.sync.title}</h2>
        {sync.kind === 'off' ? (
          <>
            <p className="setting-hint setting-hint-top">{t.sync.off}</p>
            <button className="btn" onClick={() => void signIn()}>
              {t.sync.signIn}
            </button>
          </>
        ) : (
          <div className="options">
            <div className="option sync-row">
              <span className="option-text">
                <span className="option-title">{t.sync.states[sync.kind]}</span>
                <span className="option-hint">
                  {t.sync.signedInAs} {sync.email}
                  {sync.kind === 'error' && sync.message ? ` · ${sync.message}` : ''}
                  {resendLeft() > 0 ? ` · ${t.sync.resending(resendLeft())}` : ''}
                </span>
              </span>
              <span className={`sync-dot sync-${sync.kind}`} aria-hidden />
            </div>
            <button className="option" onClick={() => void syncNow()}>
              <span className="option-title">{t.sync.syncNow}</span>
            </button>
            <button className="option" onClick={() => void signOut()}>
              <span className="option-title muted">{t.sync.signOut}</span>
            </button>
          </div>
        )}
      </section>

      <PdfSection />
      <BackupSection />

      <section className="setting">
        <h2>{t.settings.logs}</h2>
        <div className="options">
          {TIME_LOGS.map((log) => {
            const locked = isLastActive(settings.activeLogs, log);
            return (
              <Switch
                key={log}
                label={t.settings.logNames[log]}
                hint={locked ? t.settings.lastLog : undefined}
                checked={settings.activeLogs[log]}
                disabled={locked}
                onChange={() => {
                  const next = toggleActiveLog(settings.activeLogs, log);
                  if (next) void updateSettings({ activeLogs: next });
                }}
              />
            );
          })}
        </div>
        <p className="setting-hint">{t.settings.logsHint}</p>
      </section>

      <section className="setting">
        <h2>{t.settings.entries}</h2>
        <div className="options">
          <Switch
            label={t.settings.eventStates}
            hint={t.settings.eventStatesHint}
            checked={settings.eventStates}
            onChange={() => void updateSettings({ eventStates: !settings.eventStates })}
          />
        </div>
      </section>

      <section className="setting">
        <h2>{t.settings.openItems}</h2>
        <div className="options">
          <Switch
            label={t.settings.openCount}
            hint={t.settings.openCountHint}
            checked={settings.openCount}
            onChange={() => void updateSettings({ openCount: !settings.openCount })}
          />
          <Switch
            label={t.settings.setupBanner}
            hint={t.settings.setupBannerHint}
            checked={settings.setupBanner}
            onChange={() => void updateSettings({ setupBanner: !settings.setupBanner })}
          />
          <Switch
            label={t.settings.closeDay}
            hint={t.settings.closeDayHint}
            checked={settings.closeDay}
            onChange={() => void updateSettings({ closeDay: !settings.closeDay })}
          />
          {settings.closeDay && (
            <label className="option time-row">
              <span className="option-title">{t.settings.closeDayAt}</span>
              <input
                type="time"
                className="time-input"
                value={settings.closeDayAt}
                onChange={(e) => e.target.value && void updateSettings({ closeDayAt: e.target.value })}
              />
            </label>
          )}
          <Switch
            label={t.settings.reverseSwipes}
            hint={t.settings.reverseSwipesHint}
            checked={settings.reverseSwipes}
            onChange={() => void updateSettings({ reverseSwipes: !settings.reverseSwipes })}
          />
        </div>
      </section>

      <section className="setting">
        <h2 id="first-day-label">{t.settings.firstDay}</h2>
        <div className="options" role="radiogroup" aria-labelledby="first-day-label">
          {([1, 0] as const).map((d) => (
            <button
              key={d}
              role="radio"
              aria-checked={settings.firstDayOfWeek === d}
              className="option"
              onClick={() => void updateSettings({ firstDayOfWeek: d })}
            >
              <span className="option-text">
                <span className="option-title">{t.settings.weekdays[d]}</span>
              </span>
            </button>
          ))}
        </div>
      </section>

      <section className="setting">
        <h2 id="spread-mode-label">{t.settings.spreadMode}</h2>
        <div className="options" role="radiogroup" aria-labelledby="spread-mode-label">
          {(['flow', 'next'] as const).map((m) => (
            <button key={m} role="radio" aria-checked={settings.spreadMode === m} className="option" onClick={() => void updateSettings({ spreadMode: m })}>
              <span className="option-text">
                <span className="option-title">{t.settings.spreadModes[m]}</span>
                <span className="option-hint">{t.settings.spreadModeHints[m]}</span>
              </span>
            </button>
          ))}
        </div>
        <p className="setting-hint">{t.settings.spreadModeHint}</p>
      </section>

      <section className="setting">
        <h2 id="done-anim-label">{t.settings.doneAnimation}</h2>
        <div className="options" role="radiogroup" aria-labelledby="done-anim-label">
          {DONE_ANIMATIONS.map((a) => (
            <button
              key={a}
              role="radio"
              aria-checked={settings.doneAnimation === a}
              className="option"
              onClick={(e) => {
                // Preview right away, before the setting round-trips.
                document.documentElement.dataset.doneAnim = a;
                playDoneFx(e.currentTarget.querySelector<HTMLElement>('.anim-preview'), 'done');
                void updateSettings({ doneAnimation: a });
              }}
            >
              <span className="anim-preview line t-task c-task s-done" aria-hidden>
                <span className="bullet drawn cross" />
              </span>
              <span className="option-text">
                <span className="option-title">{t.settings.doneAnimations[a]}</span>
                <span className="option-hint">{t.settings.doneAnimationHints[a]}</span>
              </span>
            </button>
          ))}
        </div>
        <p className="setting-hint">{t.settings.doneAnimationHint}</p>
      </section>

      <section className="setting">
        <h2 id="done-mark-label">{t.settings.doneMark}</h2>
        <div className="options" role="radiogroup" aria-labelledby="done-mark-label">
          {(['cross', 'check'] as const).map((m) => (
            <button key={m} role="radio" aria-checked={settings.doneMark === m} className="option" onClick={() => void updateSettings({ doneMark: m })}>
              <span className={`chip-glyph c-task g-cross done-preview-${m}`} aria-hidden />
              <span className="option-text">
                <span className="option-title">{t.settings.doneMarks[m]}</span>
                <span className="option-hint">{t.settings.doneMarkHints[m]}</span>
              </span>
            </button>
          ))}
        </div>
      </section>

      <section className="setting">
        <h2 id="date-format-label">{t.settings.dateFormat}</h2>
        <div className="options" role="radiogroup" aria-labelledby="date-format-label">
          {(['dmy', 'mdy'] as const).map((o) => (
            <button key={o} role="radio" aria-checked={settings.dateOrder === o} className="option" onClick={() => void updateSettings({ dateOrder: o })}>
              <span className="option-text">
                <span className="option-title">{t.settings.dateFormats[o]}</span>
                <span className="option-hint">{t.settings.dateFormatHints[o]}</span>
              </span>
            </button>
          ))}
        </div>
      </section>

      <section className="setting">
        <h2 id="glyph-label">{t.settings.glyphStyle}</h2>
        <div className="options" role="radiogroup" aria-labelledby="glyph-label">
          {(['checkboxes', 'dots'] as const).map((g) => (
            <button
              key={g}
              role="radio"
              aria-checked={(settings.markdownGlyphs ?? 'checkboxes') === g}
              className="option"
              onClick={() => void updateSettings({ markdownGlyphs: g })}
            >
              <span className="option-text">
                <span className="option-title">{t.settings.glyphStyles[g]}</span>
                <span className="option-hint">{t.settings.glyphHints[g]}</span>
              </span>
            </button>
          ))}
        </div>
      </section>

      <section className="setting">
        <h2>{t.settings.keyboard}</h2>
        <dl className="shortcuts">
          {t.settings.shortcuts.map(([keys, what]) => (
            <div key={keys} className="shortcut">
              <dt>
                <kbd>{keys}</kbd>
              </dt>
              <dd>{what}</dd>
            </div>
          ))}
        </dl>
        <p className="setting-hint">{t.settings.keyboardHint}</p>
      </section>

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

      <HandwritingSettings />

      <section className="setting">
        <h2 id="palette-label">{t.settings.palette}</h2>
        <div className="options" role="radiogroup" aria-labelledby="palette-label">
          {PALETTES.map((p) => (
            <button
              key={p}
              role="radio"
              aria-checked={palette === p}
              className="option"
              onClick={() => {
                setPalette(p);
                setPaletteState(p);
              }}
            >
              {/* Each row shows its own colors in the current theme (light or dark). */}
              <span className="palette-dots" data-palette={p} aria-hidden>
                <span className="pd pd-task" />
                <span className="pd pd-event" />
                <span className="pd pd-note" />
              </span>
              <span className="option-text">
                <span className="option-title">{t.settings.palettes[p]}</span>
              </span>
            </button>
          ))}
        </div>
        <p className="setting-hint">{t.settings.paletteHint}</p>
      </section>
    </main>
  );
}

function Switch(props: { label: string; hint?: ReactNode; checked: boolean; disabled?: boolean; onChange: () => void }) {
  return (
    <button
      role="switch"
      aria-checked={props.checked}
      aria-disabled={props.disabled || undefined}
      className="option switch-row"
      onClick={() => !props.disabled && props.onChange()}
    >
      <span className="option-text">
        <span className="option-title">{props.label}</span>
        {props.hint && <span className="option-hint">{props.hint}</span>}
      </span>
      <span className="switch" aria-hidden />
    </button>
  );
}

function HandwritingSettings() {
  const settings = useSettings();
  const status = useTranscriptionStatus();
  const note =
    status.state === 'error'
      ? status.message === 'auth'
        ? t.settings.transcription.auth
        : t.settings.transcription.error + status.message
      : t.settings.transcription[status.state];
  return (
    <section className="setting">
      <h2 id="handwriting-label">{t.settings.handwriting}</h2>
      <div className="options" role="radiogroup" aria-labelledby="handwriting-label">
        {(['pt_BR', 'en_US'] as const).map((l) => (
          <button
            key={l}
            role="radio"
            aria-checked={settings.handwritingLang === l}
            className="option"
            onClick={() => void updateSettings({ handwritingLang: l })}
          >
            <span className="option-text">
              <span className="option-title">{t.settings.handwritingLangs[l]}</span>
            </span>
          </button>
        ))}
      </div>
      <label className="key-field">
        <span>{t.settings.myscriptAppKey}</span>
        <input
          className="field"
          type="text"
          autoComplete="off"
          autoCapitalize="off"
          spellCheck={false}
          key={settings.myscriptAppKey ?? ''}
          defaultValue={settings.myscriptAppKey ?? ''}
          onBlur={(e) => void updateSettings({ myscriptAppKey: e.target.value.trim() })}
        />
      </label>
      <label className="key-field">
        <span>{t.settings.myscriptHmacKey}</span>
        <input
          className="field"
          type="password"
          autoComplete="off"
          autoCapitalize="off"
          spellCheck={false}
          key={settings.myscriptHmacKey ?? ''}
          defaultValue={settings.myscriptHmacKey ?? ''}
          onBlur={(e) => void updateSettings({ myscriptHmacKey: e.target.value.trim() })}
        />
      </label>
      <p className="setting-hint">{t.settings.handwritingHint}</p>
      {note && <p className="setting-hint">{note}</p>}
    </section>
  );
}
