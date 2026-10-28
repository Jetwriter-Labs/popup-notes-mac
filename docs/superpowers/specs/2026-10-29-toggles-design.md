# Popup Notes — Toggles (collapsible blocks) Design

- **Date:** 2026-10-29
- **Status:** Implemented
- **Builds on:**
  [`2026-10-17-markdown-outline-design.md`](2026-10-17-markdown-outline-design.md).
- **Still true:** notes are plain text, the model and store are unchanged,
  zero third-party dependencies.

## 1. Summary

Notion-style toggles: type `>` and a space at the start of a line and it
becomes a toggle — an arrow, then a title. Lines indented under it (Tab)
are its content. Click the arrow, or press ⌘↩ anywhere in the toggle, to
fold that content away under the title and bring it back; ⌥⌘T opens or
closes every toggle in the note (Notion's shortcuts).

## 2. Decisions

| Question | Decision | Why |
|---|---|---|
| Syntax | **`▾ Title` (open) / `▸ Title` (closed)**, content = the following lines indented deeper, plus blank lines between them | Markdown has no toggles. A visible marker reads well in plain text and export; indentation is how lists already nest (Tab). |
| Typing it | **`>` + space at a line's start → `▾ `**, as its own undo step | Notion's shortcut. ⌘Z right after brings back `> ` — that's how to type a quote now. Existing `>` quotes still render as quotes. |
| Where open/closed lives | **In the text** (the marker) | Survives relaunch, sync and JSON export with no model change; parsing alone says what's hidden, so it's unit-tested in Core. |
| Folding = edit? | **No**: not undoable, doesn't bump `modified` | Opening a toggle shouldn't reorder the sidebar or sit on the undo stack (Notion, code editors). The marker swap keeps its length, so the undo history stays valid. |
| Hiding | `NSTextContentStorageDelegate.textContentManager(_:shouldEnumerate:options:)` turns down paragraphs carrying the styler's `.markdownHidden` attribute | TextKit 2's documented way to hide elements; restyling a line (attribute edit) makes TextKit re-ask, so folding needs no manual layout invalidation (verified offscreen). |
| Caret | Never in folded lines. Navigation (arrows, clicks, code) **steps over** them; an **edit** (typing, ⌘Z, a pasted or tabbed-in line) that lands in them **opens** the toggles over it | TextKit 2's ↓ skips hidden paragraphs but →, ⌘↓ and undo don't. NSTextView's undo doesn't even move the selection when the change is after the caret, so the open-on-edit hook is the edit itself (the styler's `didEdit`), not the selection. |
| Telling them apart | A selection change right after an edit (styler `editCount` moved) belongs to that edit | NSTextView restyles, then sets the selection exactly once per edit (typing, undo, `string =` — measured). |
| Return | Open title → first line inside (indented). Closed title → a new toggle after its content. Inside → keeps the indentation; on an indentation-only line steps out a level. Empty toggle/item → ends it (staying inside its toggle) | Notion-like, and the same "Return twice gets you out" as lists. |
| Tab / Shift-Tab | A toggle moves **with its content**; lines inside toggles nest like list items; a multi-line selection now moves every selected line | Otherwise its content would fall out of it. Selecting lines + Tab used to replace them with a tab — the way to move existing text into a toggle. |
| Backspace / Delete | At a title's start: the toggle becomes plain text. Next to a closed toggle: joins the line to the title, keeping the folded lines folded | The join the user sees, never into hidden text. |
| Blocks inside | Headings, quotes, rules indented under a toggle still count (indentation measured from the toggle's) | Notion allows them; the outline lists such headings and jumping to one opens its toggles. |
| Last line | The empty line after a final line break folds with the line above it | TextKit 2 lays it out as part of that paragraph (verified). |
| Look | Arrow is the marker glyph a size up (secondary label color), line height pinned to body; title and content start at the next tab stop; code/quote/rule decorations indent with the toggle | Readable, clickable, and the content lines up under the title. |

## 3. Code

- Core: `MarkdownBlocks` (`.toggle(isOpen:)`, `toggleDepth`, `isHidden`,
  toggle-relative indentation), `MarkdownToggles` (body, parent, fold,
  reveal, fold-all, caret placement), `MarkdownEditing` (`toggleShortcut`,
  toggle-aware `newline` / `indentation`, `deleteBackward`, `deleteForward`).
- App: `MarkdownStyler` (hidden attribute, `shouldEnumerate`, `editCount`,
  `didEdit`), `MarkdownTheme` (arrow font, title indent), `MarkdownTextView`
  (keys, arrow clicks, `setFolds`, selection clamp, reveal-on-edit,
  `setText`), `NoteTextEditor` (`onEdit` skips folds).

## 4. Testing

- Core: `MarkdownTogglesTests` plus toggle cases in `MarkdownEditingTests`,
  `WelcomeNoteTests`.
- Offscreen harness (editor sources + Core compiled together, never shown
  on screen): `> ` + ⌘Z, Return in/out, ⌘↩ (caret to title, not an edit),
  → / ← / ↑ / ↓ around folds, undo into a closed toggle opens it, arrow
  clicks, backspace-join, Tab under a closed toggle, trailing fold, ⌥⌘T,
  outline jump into a fold — and rendered PNGs of the look.
