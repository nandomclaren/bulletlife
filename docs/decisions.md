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
