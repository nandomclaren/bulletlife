# Technical decisions

Short log of technical decisions. Newest last.

## 2026-10-18 · Phase 0 scaffold

- **Stack:** Vite 8 + React 19 + TypeScript, `vite-plugin-pwa` (generateSW, autoUpdate), Dexie 4 + `dexie-react-hooks`, `dexie-cloud-addon` for the sync test.
- **Hosting:** served from a **domain root only**. No sub-path deploys. `base` is fixed to `/` in `vite.config.ts`.
- **Routing:** real URLs via the History API so the system back gesture works in the installed app; scroll position is saved in `history.state` and restored on `popstate` (`history.scrollRestoration = 'manual'`). The spike uses a tiny hand-written router; revisit in Phase 1.
- **Strings:** every user-visible string lives in `src/i18n/en.ts`.
- **Long press:** Pointer Events + 500 ms timer (cancelled after 10 px of movement); `-webkit-touch-callout: none` and `user-select: none` on the bullet button only. Right click / Ctrl-click via `contextmenu`.
- **Caret color:** each line sets `--bullet` from its type and the editable text uses `caret-color: var(--bullet)` (spec section 8, "writing has to feel good").
- **Naming:** no third-party trademarks anywhere in code, UI, URLs or package names. The Markdown glyph option is called "Dot notation".
- **Spike code** lives in `src/spike/` and `src/data/spikeDb.ts` and is thrown away in Phase 1.

## 2026-10-18 · Hosting on Railway

- Fernando already uses Railway, so the app is deployed there instead of Cloudflare Pages.
- **Dockerfile** (multi-stage: `node:22-alpine` build → `caddy:2-alpine`) rather than Railpack auto-detection, so the build and the server config are explicit and reproducible locally.
- **Caddyfile:** `auto_https off` (Railway terminates TLS), listens on `$PORT`, SPA fallback with `try_files {path} /index.html`, `/assets/*` cached for a year as immutable, everything else `no-cache` so a new service worker reaches installed apps, manifest served as `application/manifest+json`.
- Verified locally with Caddy 2.10: headers as above, service worker takes control, deep link `/month/2026-10` loads offline.
- Cost: one always-on static container, a few MB of RAM. It fits the Hobby plan's included usage. Sync stays on Dexie Cloud. Railway could host a sync backend later if we leave Dexie Cloud (see section 11).

## 2026-10-18 · Dexie Cloud during the spike

- Spike runs on a Dexie Cloud **evaluation user** (sync stops after 30 active days; local data and the offline app keep working).
- The manager offered no free production user, only seat packs (25 for $3/month). Decide in Phase 2: pay the $3/month, or move to another backend (Instant, Jazz, or our own on Railway). The `src/data/` repository layer keeps that switch cheap.

## 2026-10-18 · Phase 1: editor prototypes

- Two prototypes with identical features, same line DOM and CSS, so the comparison is about the engine only:
  - **A · ProseMirror** (`src/proto/PmEditor.tsx`): raw ProseMirror (no TipTap layer), flat `line` nodes with `indent` as an attribute; derived classes (inherited color, chevrons, hidden subtrees) via node decorations; prefixes via input rules (Backspace right after undoes the conversion).
  - **B · Line editor** (`src/proto/LineEditor.tsx`): one contentEditable root; the browser edits text inside a line, structural edits are intercepted in `beforeinput` and applied to our model.
- **Flat list + indent** instead of nested lists: maps 1:1 to `Entry` (`parentId` derived from indentation, see `src/editor/lines.ts`), makes collapse a pure render concern, and keeps multi-line selection inside a single editing host.
- Shared, editor-agnostic logic lives in `src/editor/lines.ts` with unit tests (prefix matching, state cycle, color inheritance, collapse, indent rules).
- Routes: `/` prototype chooser, `/proto/a`, `/proto/b`, `/check` device check.
- Decision: see next entry.

## 2026-10-18 · Themes now, not in Phase 5

- Fernando asked for dark mode with a manual choice. Themes ship now: **Automatic** (follows the system, default), **Paper** (light), **Graphite** (dark), **Night** (OLED black), on a Settings page at `/settings`.
- Tokens are CSS variables switched by `data-theme` on `<html>`; no attribute = Automatic via `prefers-color-scheme`. An inline script in `index.html` applies the saved theme before first paint (no flash). `theme-color` follows the theme so the iOS status bar matches.
- Stored in `localStorage` for now; moves into the synced Settings model later in Phase 1.

## 2026-10-18 · Editor decision: B (own line editor)

- **Chosen: B**, after Fernando wrote in both on the iPhone. B "wins easily": deleting a bullet behaves like editing text he controls, and he can freely type "-" or any other symbol. In A, Backspace over a bullet jumped back to the previous bullet.
- A (ProseMirror) and its dependencies were removed. B lives in `src/editor/LineEditor.tsx`; `/` now opens it until the real pages exist.
- Risk to watch with B: iOS autocorrect, dictation, predictive text and IME composition all go through our `beforeinput` handling. Test them on the iPhone as the editor grows.
- **iPhone indenting without Tab:** a space at the very start of a line indents it; Backspace at the start outdents first, then removes the bullet, then joins with the line above.
- **iOS form bar (^ v ✓) cannot be hidden by a web app.** A toolbar of our own above the keyboard kept fighting it (covered, then floating over the page while scrolling), so it was **dropped** (Fernando). Indent/outdent use space/Backspace at the line start; priority uses the `* ` prefix and the bullet menu. A native app can replace the system bar (`inputAccessoryView`); see CLAUDE.md section 14.
