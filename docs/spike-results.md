# Phase 0 — spike results

Status legend: ✅ pass · ❌ fail · ⚠️ works with caveats · ⏳ waiting for a device test.

The spike is the device-check page at the app root (`src/spike/`). Run it **on the installed app**
on each device, mark each check, tap **Copy report** and paste both reports at the end of this file.

## Device checks

| # | Check | iPhone | Mac | Notes |
|---|---|---|---|---|
| 1 | Install + standalone | ⏳ | ⏳ | Auto-detects `display-mode: standalone`. |
| 2 | Works offline | ⏳ | ⏳ | Service worker precaches the whole app shell. |
| 3 | IndexedDB survives several days | ⏳ | ⏳ | Every launch is logged; check "Days kept" after ≥ 3 days. |
| 4 | `navigator.storage.persist()` | ⏳ | ⏳ | |
| 5 | Dexie Cloud between both devices | ⏳ | ⏳ | Needs a database URL (setup below). Also test offline edits on both, then reconnect. |
| 6 | `navigator.share` | ⏳ | ⏳ | |
| 7 | Rich text copy (HTML) | ⏳ | ⏳ | Paste into Notes/Mail; report says which API path was used. |
| 8 | Selection survives tapping "…" | ⏳ | ⏳ | Report compares the native selection at tap time with the stored one. |
| 9 | Long press (iPhone) / right click (Mac) on bullet | ⏳ | ⏳ | |
| 10 | Mac two-finger swipe triggers browser back/forward | — | ⏳ | Installed app in the Dock. |
| 11 | Back gesture + route history + scroll restore | ⏳ | ⏳ | Month → day 18 → back. Verified in desktop Chromium: URL and scroll restored. |
| 12 | Avenir Next renders | ⏳ | ⏳ | |
| 13 | Caret takes the bullet color, typing feels good | ⏳ | ⏳ | |

Verified on the live deploy (https://bulletlife.up.railway.app, 2026-10-18, Chromium with iPhone 13 emulation):
all routes return 200 with the intended cache headers, the manifest has 3 icons, the service worker takes
control and the deep link `/month/2026-10` loads offline. No console errors.

Verified so far in headless Chromium (desktop): tap cycle open → complete → cancelled → open,
right-click menu, route navigation, back with scroll restore, deep link reload. No console errors.

## Dexie Cloud setup for check 5

```sh
npx dexie-cloud create            # asks for your email, prints the database URL
npx dexie-cloud whitelist https://bulletlife.up.railway.app
```

Paste the URL into check 5 on both devices and sign in with the same email.
**Important:** on the free plan new users start as *evaluation users* (see below). Promote your
own user to production in the Dexie Cloud manager so sync never stops.

## Section 11 open questions (from public pages, 2026-10-18 — confirm in the Dexie Cloud manager)

1. **Paid price per user:** Pro is listed at **$0.12 per user per month**, sold in packs of 25 seats ($3/month).
2. **Free plan storage:** the pricing page lists **100 MB** on the free plan (3 production users, 50,000 evaluation users, 10 databases, 10 connections, 20 req/s). Pro storage is quoted inconsistently (20+, 21+, 25+ GB) and scales with seats.
3. **Evaluation users:** they **do expire**. After **30 active days** (days without sync don't count) sync stops for that user. The app keeps working offline. Fix: promote the user to production (free plan allows 3). Eval users also have tighter rate limits (sync 50 per 5 min vs 200).
4. **Offline conflicts on both devices:** ⏳ to test (check 5).

Sources: dexie.org/pricing, dexie.org/cloud/pricing, dexie.org/blog/dexie-cloud-subscription-model, dexie.org/docs/cloud/limits.

## Recommendation

⏳ Pending the device reports.

## Raw reports

<!-- paste the "Copy report" output from each device here -->
