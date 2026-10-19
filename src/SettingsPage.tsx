import { useState, type ReactNode } from "react";
import { BackupSection } from "./BackupSection";
import {
  signIn,
  signOut,
  syncNow,
  updateSettings,
  useSettings,
  useSync,
} from "./data/repo";
import { isLastActive, toggleActiveLog, type TimeLog } from "./data/settings";
import { t } from "./i18n/en";
import { navigate } from "./router";
import { getTheme, setTheme, THEMES, type ThemePref } from "./theme";

const TIME_LOGS: TimeLog[] = ["monthly", "weekly", "daily"];

export function SettingsPage() {
  const settings = useSettings();
  const [theme, setThemeState] = useState<ThemePref>(getTheme);
  const sync = useSync();
  return (
    <main className="page">
      <button
        className="link"
        onClick={() => (history.length > 1 ? history.back() : navigate("/"))}
      >
        ‹ {t.nav.back}
      </button>
      <h1>{t.settings.title}</h1>

      <section className="setting">
        <h2>{t.sync.title}</h2>
        {sync.kind === "off" ? (
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
                  {sync.kind === "error" && sync.message
                    ? ` · ${sync.message}`
                    : ""}
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
            onChange={() =>
              void updateSettings({ eventStates: !settings.eventStates })
            }
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
            onChange={() =>
              void updateSettings({ openCount: !settings.openCount })
            }
          />
          <Switch
            label={t.settings.setupBanner}
            hint={t.settings.setupBannerHint}
            checked={settings.setupBanner}
            onChange={() =>
              void updateSettings({ setupBanner: !settings.setupBanner })
            }
          />
          <Switch
            label={t.settings.closeDay}
            hint={t.settings.closeDayHint}
            checked={settings.closeDay}
            onChange={() =>
              void updateSettings({ closeDay: !settings.closeDay })
            }
          />
          {settings.closeDay && (
            <label className="option time-row">
              <span className="option-title">{t.settings.closeDayAt}</span>
              <input
                type="time"
                className="time-input"
                value={settings.closeDayAt}
                onChange={(e) =>
                  e.target.value &&
                  void updateSettings({ closeDayAt: e.target.value })
                }
              />
            </label>
          )}
          <Switch
            label={t.settings.reverseSwipes}
            hint={t.settings.reverseSwipesHint}
            checked={settings.reverseSwipes}
            onChange={() =>
              void updateSettings({ reverseSwipes: !settings.reverseSwipes })
            }
          />
        </div>
      </section>

      <section className="setting">
        <h2 id="first-day-label">{t.settings.firstDay}</h2>
        <div
          className="options"
          role="radiogroup"
          aria-labelledby="first-day-label"
        >
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
        <h2 id="glyph-label">{t.settings.glyphStyle}</h2>
        <div
          className="options"
          role="radiogroup"
          aria-labelledby="glyph-label"
        >
          {(["checkboxes", "dots"] as const).map((g) => (
            <button
              key={g}
              role="radio"
              aria-checked={(settings.markdownGlyphs ?? "checkboxes") === g}
              className="option"
              onClick={() => void updateSettings({ markdownGlyphs: g })}
            >
              <span className="option-text">
                <span className="option-title">
                  {t.settings.glyphStyles[g]}
                </span>
                <span className="option-hint">{t.settings.glyphHints[g]}</span>
              </span>
            </button>
          ))}
        </div>
      </section>

      <section className="setting">
        <h2 id="theme-label">{t.settings.theme}</h2>
        <div
          className="options"
          role="radiogroup"
          aria-labelledby="theme-label"
        >
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

function Switch(props: {
  label: string;
  hint?: ReactNode;
  checked: boolean;
  disabled?: boolean;
  onChange: () => void;
}) {
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
