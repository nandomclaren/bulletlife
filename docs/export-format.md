# Markdown export format

Stable mapping (spec section 7). Implemented in Phase 3; this file is the contract.

| Entry | Checkboxes (default) | Dot notation |
|---|---|---|
| Page title | `# Title` | `# Title` |
| Task, open | `- [ ] text` | `- . text` |
| Task, complete | `- [x] text` | `- x text` |
| Task, migrated | `- [>] text` | `- > text` |
| Task, scheduled | `- [<] text` | `- < text` |
| Task, cancelled | `- ~~text~~` | `- ~~. text~~` |
| Event, open | `- ○ text` | `- o text` |
| Event with state | `- [x] ○ text`, `- [>] ○ text`, `- ~~○ text~~` | `- x o text`, `- > o text`, `- ~~o text~~` |
| Note | `- text` | `- - text` |
| Free text | `text` | `text` |
| Heading | `## text` | `## text` |

- Indentation: 2 spaces per level.
- Signifiers as a text prefix before the marker: `*` priority, `!` inspiration, `👁` explore → written as `?` in plain text.
- Collapsed children are always exported.

The dot-notation and signifier details are a proposal to confirm in Phase 3.
