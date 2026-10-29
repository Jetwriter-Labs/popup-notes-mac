# Note titles in their own field — design

**Date:** 2026-10-30 · **Status:** built · **Supersedes:** "title = first
non-empty line" in
[`2026-06-09-multiple-notes-swiftdata-design.md`](2026-06-09-multiple-notes-swiftdata-design.md)
(§2, §4, §5) and the Welcome note's first-line title.

## 1. Summary

A note's title is its own field, above its text, rather than the text's first
line. The sidebar shows the title; a note without one still goes by its
text's first line, so nothing turns into a row of "Untitled". Existing notes
get their first line moved into the title, once, wherever that loses nothing.

## 2. Decisions

| Question | Decision | Why |
|---|---|---|
| Storage | `Note.title: String = ""`, stored | The default lets SwiftData open older stores as they are (lightweight migration, verified by a test). |
| Untitled notes | Sidebar falls back to the text's first line, then "New Note" | Notes stay recognizable without a title, as before. |
| Title format | Plain text, one line; ⌥↩ and pasted line breaks become spaces | It's a name, shown as typed; no Markdown in it. |
| Field placement | Above the editor, fixed; level with the sidebar's toolbar buttons | Always visible in a small popup; text starts right below. |
| Look | Bold, 26 pt (a `#` heading is 21 pt), "Title" placeholder | Must read as *the* title, not one more heading. |
| Keys | Return, ↓, Tab: title → start of text. ↑ on the text's first line, ⌫ at its very start: back to the title's end | Notion's flow. A held ⌫ never spills into the title. |
| Focus on open | A blank note starts in its title; any other at the end of its text | Capture stays instant for existing notes. |
| Existing notes | One-time: first non-blank line → title, if it's a heading or plain line, ≤ 120 characters, with nothing a plain title would lose | Lists, quotes, toggles, code and rules are content, not names; `**`, backticks and link addresses would vanish. |
| Export / import | `title` key in every exported note; a file without it gets the same one-time split | Old backups import exactly as upgrading would have left them. |

## 3. Model

- `Note`: `id`, **`title`**, `text`, `created`, `modified`. Computed:
  `displayTitle` (title, else first line of text, else "New Note"),
  `preview` (under a title the text's first line; untitled, the line after
  the first), `isBlank` (title *and* text whitespace-only).
- `NoteTitle` (pure, tested): `title(_:text:)`, `preview(title:text:)`,
  `singleLine(_:)`, `split(_:)` — the one-time rule above. A heading loses
  its `#`s and closing sequence; the blank lines after the moved line go too
  (never the next line's indentation).
- `NotesRepository.moveFirstLinesIntoTitles()` applies `split` to untitled
  notes without touching `modified`. `AppDelegate` runs it once
  (`didMoveFirstLinesIntoTitles`), after the legacy-scratchpad import and
  before seeding the Welcome note, and sets the flag only after a save.

## 4. UI

- `NoteDetailView`: `VStack { title TextField; NoteTextEditor }` beside the
  outline. A SwiftUI `TextField(axis: .vertical)`, `.lineLimit(1...4)`:
  on macOS Return reaches `onSubmit` (⌥↩ would insert a line break, which
  the binding flattens), and `onKeyPress` sees ↓ and Tab. Typing a title
  bumps `modified`.
- A text field selects all its text as it takes focus; going back up from
  the text sets the caret to the title's end one turn later, via a
  `TextSelection` binding (setting it before focus is overridden).
- `MarkdownTextView.onExitAtTop`: ↑ when the caret is on the first line on
  screen (a wrapped first paragraph counts only its first line), or a fresh
  ⌫ press at location 0. `NoteTextEditor.FocusRequest` moves focus into the
  text, optionally to its start.
- Sidebar rows and the delete prompt use `displayTitle`. The outline lists
  the text's headings only, not the title.

## 5. Export file

```json
[
  {
    "created" : "2026-10-30T10:00:00Z",
    "id" : "0B3D6E2A-9F4C-4A1E-8C2D-5E7F9A1B3C4D",
    "modified" : "2026-10-30T11:00:00Z",
    "text" : "milk",
    "title" : "Groceries"
  }
]
```

`title` is always written (empty for an untitled note). Missing — a file
from before titles — means "split the first line off", as upgrading does.
Import compares title and text for "unchanged", and newer-wins applies to
both.

## 6. Caveats

- **Downgrades drop titles.** An older build opening an upgraded store
  migrates it back without the column (verified): titles are gone, and the
  text no longer starts with them. Never run a pre-title build on real notes;
  test with the `.audit` bundle id. Older builds also ignore `title` when
  importing a new export file.
