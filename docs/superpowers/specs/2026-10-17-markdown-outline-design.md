# Popup Notes — Markdown Editing & Sticky Outline Design

- **Date:** 2026-10-17
- **Status:** Implemented
- **Builds on:**
  [`2026-06-09-multiple-notes-swiftdata-design.md`](2026-06-09-multiple-notes-swiftdata-design.md).
- **Supersedes:** that spec's non-goal "rich text / Markdown rendering". Notes
  are still stored as plain text — now read and styled as Markdown.
- **Still true:** native-first, **zero third-party dependencies** (the
  Markdown parser is our own), the note model and store are unchanged, JSON
  export/import is unchanged.

## 1. Summary

Notes are written in Markdown and styled live in the editor: headings,
**bold**, *italic*, ~~strikethrough~~, `code`, links, bullet / numbered /
task lists, quotes, fenced code blocks and rules. The syntax characters stay
visible but quiet (tertiary color), so what is saved is exactly what is
typed. Typing aids make it comfortable: Return continues a list, Tab nests
it, ⌘B / ⌘I toggle emphasis, a click on a task's box checks it off.

Notes with two or more headings get a **sticky outline**: a pane beside the
editor listing the headings, which stays put while the note scrolls,
highlights the section being read or edited, and jumps to a heading on click.

## 2. Decisions

| Question | Decision | Why |
|---|---|---|
| Storage | **Plain Markdown text**, unchanged model | Export, import and titles keep working; no migration. |
| Rendering style | **Live styling in place, syntax dimmed** (not hidden, no preview mode) | Robust caret behavior, no mode switch, WYSIWYG-enough for notes. |
| Parser | **Own line-based parser in `PopupNotesCore`** (no `swift-markdown`, no `AttributedString(markdown:)`) | User asked for no third-party Markdown tools; Foundation's parser drops source ranges, which live styling needs. |
| Markdown coverage | ATX headings, emphasis/strong (CommonMark delimiter rules), `~~strike~~`, code spans, `[links](url)`, `<autolinks>`, bare `http(s)://` URLs, `-`/`*`/`+`/`1.` lists, `- [ ]` tasks, `>` quotes, ``` / ~~~ fences, `---` rules | "Basic Markdown". **Not** supported: setext headings and indented code blocks (in notes, `---` under a line and 4-space indents are usually meant literally), tables, reference links, HTML. |
| Text system | **TextKit 2** `NSTextView` subclass (`MarkdownTextView`) | Default on macOS 13+; keeps Writing Tools' inline experience. Never touches `layoutManager` (that would fall back to TextKit 1). |
| When to restyle | **`textStorage(_:didProcessEditing:…)`**, only changed lines | Restyling in `willProcessEditing` widens the edited range and NSTextView then moves the caret to its end (verified). |
| Block backgrounds | Drawn in `drawBackground(in:)` from a custom attribute | Full-width code-block backgrounds, quote bars, rule lines; text attributes can only paint behind glyphs. |
| Sidebar titles | **Read without syntax** (`# Plan` → "Plan") | Titles should read like the editor shows them. |
| Outline placement | **Trailing pane in the detail column**, below the toolbar strip | Mirrors the sidebar; stays put while the editor scrolls. Custom `HStack`, not `.inspector` (predictable in a hosted `NSPanel`). |
| When it shows | Setting on (default) **and ≥ 2 headings** and detail ≥ 420 pt wide | One heading is just a title; a narrow panel needs the room for text. |
| Current section | Around the **caret** when it's on screen, else the **top line** on screen | Tracks editing in short notes and reading in long ones. |
| Jump | Heading scrolled to the top (animated unless Reduce Motion), caret at the end of its line, editor focused | Typing continues right under the heading. |
| Toggle | ⋯ menu "Show Outline" (checkmark), the pane's hide button, **⌃⌘O** | ⌃⌘ is the HIG pattern for view toggles. The panel handles ⌃⌘O itself: shortcuts on toolbar-menu items only fire while the menu is open. |
| Undo | Each Markdown edit (⌘B, list continuation, Tab, task toggle) is its own undo step | NSTextView otherwise folds it into the typing before it. |

## 3. Core (`PopupNotesCore`, pure and unit-tested)

All ranges are **UTF-16 offsets** (`NSRange`) so they apply to
`NSTextStorage` directly.

- `MarkdownText` — the text as `[UInt16]` (one bulk copy from `NSString`).
- `MarkdownBlocks.lines(in:)` → `[MarkdownLine]`: one entry per line (a
  trailing line break leaves a final empty line, so every caret position has
  a line) with its `MarkdownBlock` kind and ranges for prefix, marker, content,
  task box and a heading's closing `#`s. Fence state carries across lines.
- `MarkdownInline.spans(in:range:)` → `[MarkdownSpan]`: strong / emphasis /
  strikethrough / code / link / url / syntax. Emphasis uses CommonMark's
  flanking rules, rule of three and `openers_bottom` (so `snake_case` and
  `5 * 3` stay plain, and unmatched delimiters can't go quadratic). Lines over
  10 000 UTF-16 units aren't inline-parsed. `plainText(in:range:)` drops syntax.
- `MarkdownOutline.headings(in:)` → `[MarkdownHeading]` (level, nesting
  depth, plain title, line range; untitled headings skipped, headings inside
  code ignored) and `section(containing:in:)`.
- `MarkdownEditing` → `MarkdownEdit` (range, replacement, selection) for
  Return, Tab / Shift-Tab, ⌘B / ⌘I and task toggling; `nil` means "let the key
  do its usual thing".
- `NoteTitle` strips syntax from the title and preview line.

## 4. App

- `MarkdownTextView` (`Editor/`): owns a `MarkdownStyler`; overrides
  `insertNewline` / `insertTab` / `insertBacktab`, `performKeyEquivalent`
  (⌘B / ⌘I, only while focused), `mouseDown` (task boxes);
  `reveal(_:)`, `visibleCharacterRange()` and `boundingRect(for:exact:)` for
  the outline; draws block backgrounds.
- `MarkdownStyler` (`Editor/`): the text-storage delegate. Per edit: re-reads
  the lines (cheap), diffs them against the previous edit's to find the lines
  to restyle, sets attributes inside `beginEditing`/`endEditing`. Reports
  whether a decorated line changed so the view redraws its backgrounds.
- `MarkdownTheme` (`Editor/`): system dynamic colors, cached fonts, heading
  scale, hanging-indent paragraph styles (prefix widths cached).
- `NoteTextEditor`: hosts the text view; its coordinator keeps a
  `NoteOutline` current (headings a run-loop turn after edits, current
  section on selection change and scroll) and resets typing attributes so an
  empty line's caret is body-sized.
- `NoteOutline` (`@Observable`) + `NoteOutlineView`: the pane. Writes are
  equality-guarded; the detail view observes only `isWorthShowing`, so typing
  doesn't redraw it.

## 5. Performance (measured, optimized build)

- Typing in a normal note: ~0.5 ms per keystroke including NSTextView's own work.
- 122 000-character note (4 800 lines, 800 headings): first styling 25 ms;
  ~2 ms per keystroke (line scan 0.4 ms, outline 1.3 ms).

## 6. Testing

- `PopupNotesCore`: `MarkdownBlocksTests`, `MarkdownInlineTests`,
  `MarkdownOutlineTests`, `MarkdownEditingTests`, plus title/preview and
  Welcome-note cases — `./scripts/test-core.sh`.
- Manual (see CLAUDE.md smoke test): styling while typing, list keys, ⌘B/⌘I
  and ⌘Z, task clicks, outline appearance at the second heading, current-
  section tracking while typing and scrolling, jumps, ⌃⌘O, narrow panel.
