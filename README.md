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

## Deploy (Railway, domain root)

The repo ships a `Dockerfile` (Node 22 build → Caddy serving `dist/`), a `Caddyfile`
(SPA fallback, cache headers, listens on `$PORT`) and `railway.json` (Dockerfile builder).

1. Railway › New Project › Deploy from GitHub repo › `bulletlife`.
2. Service › Settings › Source: set the branch to deploy.
3. Settings › Networking › **Generate Domain** (or add a custom domain). The app always runs
   at the domain root, never a sub-path. HTTPS is handled by Railway.

No environment variables are needed. Every push to the chosen branch redeploys.

Local check of the production server: `docker build -t bulletlife . && docker run -p 8080:8080 bulletlife`.

## Phase 0 device check

Open the deployed URL, install it (see the page itself for steps), run each check on the
installed app, then tap **Copy report** and paste the result into `docs/spike-results.md`.
