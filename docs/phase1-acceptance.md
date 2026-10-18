# Phase 1 — acceptance

Run on 2026-10-18 against a production build (Chromium, 390 × 800, touch off), with an
automated script that follows CLAUDE.md section 13 step by step. Unit tests: 27 passing
(prefixes, state cycle, tree rules, indent, dates and weeks, entry diff and ordering,
signifiers and placement, active-logs rule).

| Criterion | Result |
|---|---|
| `. task` creates a colored task | ✅ |
| Indent makes a parent with a chevron | ✅ |
| Collapse / expand | ✅ |
| 1 tap completes, 2nd tap cancels (tasks; events with Event states on; notes never) | ✅ |
| Event states off: tapping an event does nothing | ✅ |
| Cannot turn off all of Month, Week and Day | ✅ (last switch locked; unit tested) |
| Nothing is created or moved automatically; visiting a page that does not exist does not create it | ✅ |
| Works offline (open, write, reload) | ✅ |
| Month: label, title, every day with number and initial, week dividers, nothing stored until writing | ✅ |
| A long Month phrase shrinks to 85% then wraps, never cut | ✅ (17 → 14.45 px, wraps) |
| Year: 12 months with names written; each area grows with content | ✅ |
| Breadcrumb: Day → Week / Month / Year in one tap | ✅ |
| Content taps: Year → Month, Month → Day, Month → Week | ✅ |
| Back restores scroll | ✅ (after fixing scroll anchoring, see decisions) |
| With Week off the breadcrumb omits the week | ✅ |
| No console errors | ✅ |

Also in Phase 1: Collections (create, rename, write) and a basic Index (collections plus
written logs by year), bullet menu, signifiers, settings, themes.

## Needs Fernando's devices

- Long press on the bullet on the iPhone (menu), right click on the Mac.
- Writing feel on both: Backspace and space at line start, autocorrect, dictation.
- Month text shrinking with Avenir Next.

## Deferred (not Phase 1 acceptance items)

- Level transition animation ("the row expands into the page", 150–200 ms).
- Long press on Today to jump to the finest log.
- "Copy as…" in the bullet menu (Phase 3), migrate destination hints (Phase 4), search ⌘K (Phase 5).
