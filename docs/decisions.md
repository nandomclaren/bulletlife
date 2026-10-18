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

## 2026-10-18 · Phase 1 core, part 1: data and time pages

- **Repository** (`src/data/repo.ts`) is the only data entry point; Dexie lives in `src/data/db.ts`. Tables: `logs`, `entries` (`[logId+slot]` index), `settings`.
- **Deterministic ids for time logs** (`daily:2026-10-18`, `weekly:2026-W43`, `monthly:2026-10`, `future:2026`): two offline devices writing the same day never create two logs. Entries use ULIDs.
- **Lazy creation:** a log row is written only when its first non-blank entry is saved. Navigating never writes. A blank page (one empty line) is never stored.
- **Saving:** each editor saves its `(log, slot)` 400 ms after the last change, and flushes on page hide and unmount. Only changed entries are written (`diffEntries`); order uses fractional keys that are kept when still in order (`assignOrders`).
- **Flat lines ↔ entries:** the editor's indent becomes `parentId`; loading rebuilds indents from parents in order.
- **Weeks:** keys follow ISO-8601 numbering (`2026-W43`). With Sunday as first day, a week takes the number of the Monday after its Sunday. Routes: `/day/2026-10-18`, `/week/2026-W43`, `/month/2026-10`, `/year/2026`; `/` redirects to today's finest active log.
- **Month:** day rows are rendered from the date; each row is a compact editor storing entries with `slot = 'YYYY-MM-DD'`. "Month tasks" is the same log with an empty slot. Year: twelve editors with `slot = 'YYYY-MM'`.
- **Header:** breadcrumb of active levels, ‹ ›, Today, native date picker. Settings moved to a quiet footer link until the Index menu exists (the header must fit a 390 px iPhone).
- Still to do in Phase 1: Month row font shrink (85% then wrap), bullet menu, settings for active logs / event states / first day, Collections and Index, offline check of the whole flow.

## 2026-10-18 · Week strip removed, cross drawn

- The 7-day strip on Day and Week pages is **commented out** at Fernando's request (it made the app look like a digital note taker). Week → Day goes through the breadcrumb's day crumb (the anchor day), then ‹ › on the Day page. Code kept in `src/pages/WeekStrip.tsx`.
- The completed "×" is now drawn in CSS like the dot and ring: the text glyph sat higher than the dot it replaced.

## 2026-10-18 · No horizontal scrolling

- `html, body { overflow-x: clip; overscroll-behavior-x: none }` and `body { touch-action: pan-y pinch-zoom }`: nothing can push the page sideways, no sideways rubber-band on iOS, vertical panning and pinch zoom kept. Horizontal pointer moves still reach the app (Phase 4 swipes).
- The breadcrumb no longer scrolls: outer crumbs shrink with an ellipsis, the current one stays whole.
- Mac: Safari's two-finger swipe between pages is a system gesture; `overscroll-behavior-x` may not stop it in Safari (Chromium honors it). If it still fires, it can be turned off in macOS System Settings › Trackpad › More Gestures › Swipe between pages (affects all apps).
