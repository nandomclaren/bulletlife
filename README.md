# Bullet Life

A calm, local-first notebook for rapid logging, installable as a PWA on Mac and iPhone.
Product spec: [`CLAUDE.md`](CLAUDE.md). Current stage: **Phase 0 (device spike)**.

## Develop

```sh
npm install
npm run dev        # http://localhost:5173
npm run build      # typecheck + production build in dist/
npm run preview    # serve dist/ locally
```

## Deploy (Cloudflare Pages, domain root)

1. Cloudflare dashboard › Workers & Pages › Create › Pages › Connect to Git › pick this repo.
2. Framework preset: **None**. Build command: `npm run build`. Output directory: `dist`.
3. Environment variable: `NODE_VERSION = 22`.
4. Deploy. The app is served at `https://<project>.pages.dev/` (always the domain root, never a sub-path).

Every push to the main branch redeploys; other branches get preview URLs.

## Phase 0 device check

Open the deployed URL, install it (see the page itself for steps), run each check on the
installed app, then tap **Copy report** and paste the result into `docs/spike-results.md`.
