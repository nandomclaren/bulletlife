# Export formats

Stable contract (CLAUDE.md section 7), implemented in `src/export/format.ts` and unit tested.
Exports are built from the data model, never from the screen: **collapsed children are always included**.

## Markdown

| Entry | Checkboxes (default) | Dot notation |
|---|---|---|
| Page title | `# Title` | `# Title` |
| Fixed section (Month day, Year month, Month tasks) | `## 18 Sun` | `## 18 Sun` |
| Heading entry | `## text` (`###` inside a section) | same |
| Task, open | `- [ ] text` | `- . text` |
| Task, complete | `- [x] text` | `- x text` |
| Task, migrated | `- [>] text` | `- > text` |
| Task, scheduled | `- [<] text` | `- < text` |
| Task, cancelled | `- ~~text~~` | `- ~~. text~~` |
| Event, open | `- ○ text` | `- o text` |
| Event, complete / migrated / scheduled | `- [x] ○ text`, `- [>] ○ text`, `- [<] ○ text` | `- x o text`, `- > o text`, `- < o text` |
| Event, cancelled | `- ~~○ text~~` | `- ~~o text~~` |
| Note | `- text` | `- - text` |
| Free text | `text` | `text` |

- Indentation: 2 spaces per level.
- Signifiers go right before the text, after the marker, so checkboxes stay valid Markdown: `- [ ] * text`. `*` priority, `!` inspiration, `👁` explore (combined: `*!👁`).
- List numbers typed in the text (`1. `) are kept as typed.

## Plain text

Same structure, with the bullet glyphs: `•` task, `×` complete, `>` migrated, `<` scheduled, `○` event, `–` note. Cancelled tasks and events are struck through with a combining long stroke (U+0336), which survives pasting as plain text. Headings in capitals. Indentation: 2 spaces.

## Rich text (HTML)

Nested lists with colored, semi-bold bullet glyphs (task `#E0533D`, event `#3B82C4`, note `#2A9D8F`), completed/migrated/scheduled text muted, cancelled text struck through. Copied as `text/html` together with the plain-text version.

## What is exported

- The page menu "…" exports the page you are on (Day, Week, Month with its day rows and Month tasks, Year with its months, a collection), or only the selected lines when there is a selection (with their collapsed children).
- Settings › Backup › Export everything as Markdown writes every page into one file, Years first, then Months, Weeks, Days, then collections.
