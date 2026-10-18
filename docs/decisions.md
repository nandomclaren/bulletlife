# Technical decisions

Short log of technical decisions. Newest last.

## 2026-10-18 · Phase 0 scaffold

- **Stack:** Vite 8 + React 19 + TypeScript, `vite-plugin-pwa` (generateSW, autoUpdate), Dexie 4 + `dexie-react-hooks`, `dexie-cloud-addon` for the sync test.
- **Hosting:** served from a **domain root only** (Cloudflare Pages recommended). No sub-path deploys (rules out GitHub Pages project sites). `base` is fixed to `/` in `vite.config.ts`.
- **Routing:** real URLs via the History API so the system back gesture works in the installed app; scroll position is saved in `history.state` and restored on `popstate` (`history.scrollRestoration = 'manual'`). The spike uses a tiny hand-written router; revisit in Phase 1.
- **Strings:** every user-visible string lives in `src/i18n/en.ts`.
- **Long press:** Pointer Events + 500 ms timer (cancelled after 10 px of movement); `-webkit-touch-callout: none` and `user-select: none` on the bullet button only. Right click / Ctrl-click via `contextmenu`.
- **Caret color:** each line sets `--bullet` from its type and the editable text uses `caret-color: var(--bullet)` (spec section 8, "writing has to feel good").
- **Naming:** no third-party trademarks anywhere in code, UI, URLs or package names. The Markdown glyph option is called "Dot notation".
- **Spike code** lives in `src/spike/` and `src/data/spikeDb.ts` and is thrown away in Phase 1.
