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

## 2026-10-18 · The page's free space belongs to the editor

- Each editor sits in an `.editor-area` tap target. A tap on free space puts the caret at the end of the last visible line (the first line on an empty page); a tap in a line's left margin puts it at the end of that line. Taps on text, bullets and chevrons are left alone.
- On Day and Week pages the area stretches to the bottom of the screen; Year month areas and Month day rows are whole tap targets too. The focus happens inside the tap, so iOS opens the keyboard.

## 2026-10-18 · Caret can no longer enter the gutter

- Bug (iPhone): Backspace on an empty first line moved the caret into the gutter and broke the line. WebKit lets the caret sit before a non-editable element at the start of the editing host.
- Fix in three layers: (1) the gutter is now absolutely positioned beside the text, outside the text flow, with the same top padding, font size and line height as the text so bullets still sit on the first baseline; (2) Backspace at a line start is handled in `keydown` (not only `beforeinput`, which WebKit may not let us cancel there); (3) a `selectionchange` guard moves any caret that lands outside `.line-text` back to the start of that line.

## 2026-10-18 · "* " on plain text stays text

- Bug: typing "* " on an empty plain line turned it into a priority mark in the gutter, which Backspace could not remove.
- Now a lone "* " marks priority only on a line that already has a bullet (as CLAUDE.md 3.4 says: "* " before a bullet). On plain text it stays a typed asterisk. "* . ", "* o. ", "* - " still create a priority task/event/note.
- Backspace at the start of a plain line that still carries a priority mark (older data) removes the mark first.

## 2026-10-18 · Phase 1 core, part 2: settings, bullet menu, Month text fit

- **Settings** (Dexie `settings` row): active logs Month / Week / Day with the "at least one" rule (`src/data/settings.ts`, unit tested; the last switch on is locked), Event states, First day of week (Monday / Sunday). Theme stays per device.
- **Event states off:** event bullets stop cycling (tap and ⌘↵ do nothing); a state already saved stays visible (CLAUDE.md 12: never hide data).
- **Bullet menu:** long press (500 ms, also click-and-hold) or right click / Ctrl-click on the bullet (right click anywhere in the margin for plain lines). One entry at a time: Type (Task, Event, Note, Text), State (Open, Complete, Cancel, Migrate, Schedule), Signifiers (Priority `*`, Inspiration `!`, Explore drawn eye), Indent, Outdent, Delete. Delete moves children up one level and shows an "Undo" toast for 5 s. "Copy as…" arrives with Phase 3.
- **Migrate / Schedule** set `placement = { status: 'pending' }` (cleared when the entry leaves those states), ready for the Pending panel in Phase 4.
- **Month text fit** (`src/pages/fitText.ts`): a phrase that does not fit one line shrinks continuously down to 85% (min 14 px), then wraps and the row grows. Never truncated.

## 2026-10-18 · Pages of a turned-off level redirect

- Bug: with only Week on, a Day page could still open (old link, history, or the app opening before Settings were read) and ‹ › stepped by day.
- Now a Day, Week or Month page whose level is off is replaced (history `replace`) by the finest active level for the same date. Opening the app waits for Settings to be read (`useLoadedSettings`) instead of using defaults.

## 2026-10-18 · Phase 1 part 3: Collections, Index, acceptance

- **Collections** are logs of kind `collection` with id `collection:<ULID>`, created only by "New collection" in the Index (explicit action) and renamed in place. Route `/collection/<id>`.
- **Index** (`/index`, button left of the breadcrumb) is derived: collections A–Z, then logs that have entries, grouped by year (Year, Month, Week, Day). Settings link moved there too (the footer link stays).
- **Scroll restore:** the browser's scroll anchoring shifted the restored position while a page's entries loaded (Month back from Day landed 136 px off). `overflow-anchor: none` on the root, and the router retries the restore for up to 800 ms until the page is tall enough (stops if the user scrolls).
- Acceptance recorded in `docs/phase1-acceptance.md`.

## 2026-10-18 · Year always listed in the Index

- Fernando asked whether the future log should be a default collection so the Pending panel can find it. Decision: no. The Year keeps its own kind (`future`) with a deterministic id (`future:YYYY`) and month slots (`YYYY-MM`), which is exactly what the panel's category C query needs; a collection has no months. An unwritten Year has no entries, so there is nothing to find.
- Because the future log is "always on", the current year's Year is now pinned at the top of the Index even before anything is written. It is a link only; nothing is stored.

## 2026-10-18 · List numbers read like bullets

- A leading list number (`1. `, `12) `, up to 3 digits, followed by a space) is styled like a bullet: semi-bold, in the bullet color. On a plain text line it colors like a task (Fernando's example), so its children inherit that color; on a task/event/note it takes that item's color.
- The number stays part of the text: stored and exported exactly as typed. The editor renders it in a `.num` span and rebuilds the line's text (keeping the caret) only when the number appears, changes or goes away.

## 2026-10-18 · Numbered lists behave like lists

- **Enter on a numbered item** starts the next line with the next number (`2. …` → `3. `). Enter on an empty item (`3. ` alone) ends the list.
- **Enter at the end of a collapsed item** puts the new line after everything hidden inside it, as the next sibling, and the item stays collapsed (it used to expand it and slip the line in among its children). On an open item with children, Enter starts a new first child.
- **Automatic renumbering** — Fernando's explicit exception to principle 1 (recorded in CLAUDE.md 2.1). After a structural edit (Enter, delete, join, indent/outdent, paste) consecutive numbered siblings are renumbered from the list's first number and separator; a plain sibling ends the list; nested lists count separately. An item indented into a new nested list starts at 1. Typing a number by hand is never overridden while typing. Only the number changes.
- **The user's numbers win** (follow-up from Fernando): before each structural edit the editor notes which items were *not* following their previous sibling + 1 (the first item of a list, or a number typed out of sequence such as `10.` after `2.`). Renumbering keeps those numbers and counts on from them (`10.`, `11.`, …); only the in-sequence items are renumbered. `listRestarts` + `renumberLists` in `src/editor/lines.ts`, unit tested.

## 2026-10-18 · Simpler Index

- Fernando found the "Logs" list messy (repeated year, a lone "Day" row, two stacked rules). Removed: the Index shows the current Year (pinned) and Collections only. Other years: ‹ › on the Year page or the calendar.
- The Index header matches the time pages: Today and the calendar sit in exactly the same place; the ‹ › slots are kept empty so nothing shifts. Today opens today's finest log; the calendar opens the finest log of the chosen date.
- The two rules were the last item's border plus the footer's border; the last item of a list no longer draws one.

## 2026-10-18 · Phase 2: sync with Dexie Cloud

- **Database:** `https://zsu6nu12q.dexie.cloud` (`src/data/cloud.ts`). `requireAuth: false`: the app works fully without signing in (local-first); sync starts after "Sign in" in Settings (email + one-time code, Dexie's own dialog for now).
- **Same local database:** `nameSuffix: false`. By default the addon opens a new IndexedDB named after the cloud database, which made existing data look gone in testing (it was untouched in the old database). Now `bullet-life` is upgraded in place (v1 → v2), verified with a v1 database built by hand.
- **Globally unique ids:** synced primary keys must be globally unique. Entries (ULID) and collections (`collection:<ULID>`) already are. The deterministic time-log rows (`daily:2026-10-18`, …) are dropped in the v2 upgrade: nothing needed them (everything about a time page comes from its date) and entries keep referring to the page by that name. Settings stay per device (`unsyncedTables`), a single fixed row; revisit for the commercial version.
- **Editors only write what they changed:** each editor keeps a base (what it loaded or last saved) and saves only lines it touched; it deletes only lines it knew and removed. Before this, an editor that had not yet received a change from elsewhere wrote the whole page back and undid it (reproduced with two windows). `touchedIds` + `diffEntries(..., base)`, unit tested.
- **Live updates:** each editor watches its stored entries; when they change from elsewhere it reloads, but never while the user is typing (waits for a 2.5 s pause, keeps the caret in the editor).
- **Indicator:** Settings › Sync shows "Up to date", "Syncing…", "Offline…" or "Sync paused" with the signed-in email, plus Sync now and Sign out. On every page a small ring on the Index button appears only when offline or paused; nothing when in sync or not signed in.

## 2026-10-19 · Phase 2 accepted

- Fernando signed in on iPhone and Mac with the same email: entries written on one appear on the other, including entries written offline and synced after reconnecting (Phase 2 acceptance criterion).
- Icons and manifest already use the final files from `assets/icon/` (manifest icons incl. maskable, apple-touch-icon, favicons).
- Still per device: Settings (theme, active logs, first day of week).

## 2026-10-19 · Backup (before Phase 3, at Fernando's request)

- Sync is replication, not backup: a deletion or a bug spreads to every copy. Two protections added now; an automatic off-device copy (Dexie Cloud export on the Mac, or a small service on Railway) is planned for Phase 5.
- **Daily snapshots:** once a day (3 s after launch and when the app returns to the foreground) a full copy of entries and collections goes into a separate local database, `bullet-life-backups`, which is never synced. The 30 newest are kept. Each device has its own.
- **Restore** (from a snapshot or a file) replaces the current content exactly, and first saves a "Before restore" snapshot of the current state (5 newest kept), so a restore can be undone. Confirmation is inline.
- **Export everything:** a JSON file (`bullet-life-YYYY-MM-DD-HHMM.json`, format 1) with entries and collections, without the sync service's fields (`realmId`, `owner`). iPhone: share sheet (Save to Files / iCloud Drive); Mac: download. "Last export" shown in Settings. **Restore from a file** validates the file first and refuses anything that is not a backup from this app (or from a newer format).
- The full Markdown export arrived with Phase 3 (see below).
- Pure rules in `src/data/backup.ts`, unit tested.

## 2026-10-19 · Phase 3: Export, Copy As, Share

- **Where:** a "…" button on the title row of every page (Day, Week, Month, Year, collection). The time header is already full at iPhone width, so the menu sits beside the title instead.
- **Menu:** one panel, no submenus. Scope (Whole page / Selection · N lines, only when there is a selection), format chips (Markdown / Rich Text / Plain Text, the last choice remembered on the device), then Copy, Export, Share. Copying a page in Markdown is 2 taps ("…", Copy).
- **Built from the model, never the screen:** the document is read from the stored entries (`src/export/pageDoc.ts`), so collapsed children are always included. The Month exports its written day rows as `## 18 Sun` sections plus Month tasks; the Year exports its written months. Empty sections are left out; the layout itself is not "content".
- **Prepared on open:** Safari only allows clipboard and share right after a tap, so opening the menu flushes pending edits (`src/pages/flush.ts`) and builds the document; the buttons then run synchronously inside the tap.
- **Copy:** `ClipboardItem` with `text/html` + `text/plain` for Rich Text (plain fallback for apps that only take text); fallback to a `copy` event with `DataTransfer`. **Export:** iPhone opens the share sheet with the file (Save to Files), Mac downloads it. **Share:** `navigator.share` with text; hidden where it does not exist.
- **Selection:** stored on every `selectionchange` as whole lines (with the collapsed children of a collapsed last line) because tapping "…" on iOS can clear the native selection; cleared on navigation. A selection exports as bare lines without the page title, the same as ⌘C.
- **⌘C / iOS Copy / cut** are intercepted when the selection spans lines or covers the whole text of a collapsed parent: the clipboard gets plain text and HTML from the model, children included. A few words inside one line keep the native copy. Cut removes what it copied, hidden children included.
- **Settings:** Markdown glyph style (Checkboxes / Dot notation). Backup › Export everything as Markdown: every written page in one `.md` file (Years, Months, Weeks, Days oldest first, then collections by name). The JSON file stays the restorable backup.
- To validate on the iPhone: rich-text paste into Notes/Mail, the share sheet, and the selection surviving a tap on "…".
- **Paste back into the app** (Fernando's report: pasted items came in as literal "•" and struck characters). ⌘C/iOS Copy now also carries the exact lines (`application/x-bullet-life-lines`); on paste the editor recreates them as entries (fresh ids, indentation relative to the line pasted on). Without that type, text that looks like our export (Markdown with checkboxes or dot notation, or plain text with glyphs) is read back too (`src/editor/paste.ts`, tested). Plain text cannot tell a done/migrated event from a task, so those come back as tasks; Markdown keeps it. Ordinary text keeps the regular paste. Pasting is the user's own gesture on the page they are on, so it is not an automatic copy (principle 1).

## 2026-10-19 · Phase 3 accepted

- Fernando confirmed on the iPhone: Copy As (incl. rich text pasted into native apps), Share, the selection surviving a tap on "…", Export, and copy/paste of entries inside the app.

## 2026-10-19 · Phase 4: Open items and rituals

- **Name:** the panel and its button are "Open items" (Fernando). Swipe right marks `>`, left marks `<` (Fernando confirmed the default); Settings › Reverse swipe directions flips it.
- **Derived, never stored** (`src/data/openItems.ts`, tested): A = open tasks (and events with Event states on) on a Day/Week/Month whose period has ended; B = marked `>`/`<` with `placement.status = pending`, on any page; C = open Year items whose month has come (or `dueDate` passed). Notes and free text never. Grouped by page (Year items by month), oldest first, coarser page first on the same date; label + age ("Wk 41 · Oct 5 – 11 · last week").
- **Only single-entry writes:** tap the bullet (open → done → cancelled → open), long press / right click for a states-only menu, swipe for `>`/`<`, and "I wrote it there" (placement → placed). No select-many, clear-all, copy or drag. Items acted on stay listed with their new state until the panel closes, so a second tap can still cancel; then resolved ones are gone.
- **Suggested destination** (read-only, toast with "Open"): `>` → the next period of the same log, or the current one for an item left behind; if that level is off, the finest active log; from the Year, this Month; from a collection, the finest log. `<` → the Year, at the first month after the item. Nothing is ever written there.
- **Horizon** setting deferred: without a date on the entry there is nothing to compare N periods against. Revisit if dates on entries arrive.
- **Mac shortcuts:** ⌃⌥→ migrate, ⌃⌥← schedule. The spec's ⌥→/⌥← are the macOS "move by word" keys in any text field, so they stay with the system.
- **Swipe** (touch only, `src/editor/swipe.ts`): horizontal after 10 px, commits at 72 px, reveals the glyph and the destination behind the line; marking again takes the mark back. Lines use `touch-action: pan-y`. The Mac uses menu and shortcuts (trackpad swipes belong to the browser).
- **Layout:** ≥ 1000 px the panel is a 380 px column beside the page (page stays editable); below, a sheet from the right that closes with ×, a tap on the backdrop, or a swipe right outside the rows. Tapping an item opens its page and flashes the entry (the sheet closes on iPhone; the column stays on Mac).
- **Set up banner:** on pages of the current period, "October isn't set up yet" / "Week 43 isn't set up yet" (month first). "Set up" records a small row (`setup:<ULID>`, `periodLogId`) so every device knows; the page stays empty; then it opens that page and the panel. Entries on the page also count as set up. Dismiss is per device and per period.
- **Close the day:** from 20:00 by default (time and on/off in Settings), on current-period pages when Day is active. Opens tomorrow's page with the panel filtered to what is still open today ("Show all open items" removes the filter). Dismissed for the day once used.
- **Count:** plain number beside the button (Settings › Show the count), no badge.

## 2026-10-19 · Due dates (Fernando's request)

- **Writing:** `due:` + `2026-10-23`, a short date (`23/10`, this year; Settings › Date format decides day or month first, and a date that only makes sense the other way round is read that way), `today`, `tomorrow`, `yesterday`, a weekday (`fri`: the coming one; `next fri`: strictly after today), `next week`, `next month`, `in 3 days/weeks/months`.
- **Stored as typed text** `due:YYYY-MM-DD` once the word is finished (space, Enter, or leaving the editor): a written "tomorrow" must not drift. The text survives sync, copy/paste and Markdown export; `Entry.dueDate` is derived from it on save.
- **Shown as a pill:** calendar mark + "Today" / "Tomorrow" / "Yesterday", else "23 Oct" (or "Oct 23"), with the year when not this one. Month names instead of numbers, so no one misreads it. Tint by urgency (overdue red, today amber, later blue), muted on finished items. The pill is atomic: the stored text sits inside, invisible, so the line reads back unchanged; tap it for the system date picker; Backspace removes it whole.
- **Open items:** a **Due** group on top: any open task (or event with Event states) dated today or earlier, on any page, nearest date first, with the page it lives on.
- **Sorting, on request only:** a list of two or more sibling bullets with at least one date that is out of order shows a small sort mark on its first line. A tap sorts it by date (cancelled ones too), undated items last in their order, children with their item; Undo puts it back. Reordering within the page is allowed by principle 1; the app never sorts on its own.
- **Bug fixed on the way:** when lines moved, order keys of lines that did not move could be reassigned but not saved, so two lines could share a key and the stored order differed from the page. `diffEntries` now writes every line whose key changed (regression test).
- Commercial note: the date format default should come from the device region; for now DD/MM per CLAUDE.md.

## 2026-10-19 · Phase 4 adjustments (Fernando's iPhone test)

- **Swipe did not work on iOS.** Inside editable text iOS Safari takes over a horizontal pointer gesture and cancels the pointer, so the swipe now uses Touch Events: a mostly horizontal touchmove is claimed (`preventDefault`) before Safari decides, a vertical one is left to scrolling, and the end of a swipe is cancelled so it does not place the caret. Pills, the sort mark and buttons do not start a swipe. Tested with real touch input (CDP) in Chromium; to confirm on the iPhone.
- **No suggested destination.** Showing "Migrated · Tomorrow" suggested the app had done something it did not. After a mark the toast says only "Migrated" / "Scheduled" with **Undo**; the swipe reveals the glyph and "Migrate" / "Schedule". The destination logic, its tests and the Horizon setting are gone (CLAUDE.md updated).

## 2026-10-19 · Phase 4 accepted

- Fernando confirmed on the iPhone and Mac: Open items panel, swipe marks (Touch Events), mark toast with Undo, banners, due dates and sorting by date. CLAUDE.md updated (gesture table shortcuts, swipe direction confirmed, section 3.7 on due dates).
