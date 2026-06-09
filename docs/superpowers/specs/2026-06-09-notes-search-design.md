# Popup Notes — Search (Filter the Notes List) Design

- **Date:** 2026-06-09
- **Status:** Approved (design phase) — ready for implementation planning
- **Builds on:**
  [`2026-06-09-multiple-notes-swiftdata-design.md`](2026-06-09-multiple-notes-swiftdata-design.md).
  The note model, SwiftData store, sidebar/detail UI, panel, and Settings from
  that spec are unchanged.
- **Refines:** that spec listed search as **deferred**, to be done with a
  SwiftData `#Predicate`. This design **supersedes that approach**: search
  **filters in memory** via a pure helper, consistent with the repo's existing
  "fetch unfiltered, filter in memory" decision
  ([`NotesRepository.swift`](../../../PopupNotesCore/Sources/PopupNotesCore/NotesRepository.swift) §top).
  `#Predicate` is rejected (see §7).
- **Still true:** native-first, **zero third-party dependencies**, small-N
  in-memory data handling, the non-activating floating panel.

## 1. Summary

Add **search that filters the notes list**. A native search field sits at the
top of the sidebar; **⌘F** focuses it. Typing narrows the sidebar to notes whose
**full text** matches the query (**case- and diacritic-insensitive**), so you can
find and jump to a note. The match logic is a pure, unit-tested helper
(`NoteSearch`) in **`PopupNotesCore`**, mirroring the existing `NoteTitle`
pattern. The currently-open note stays in the detail pane even if it's filtered
out of the list. This is **list-filtering only** — no find-within-the-current-note
find bar (explicitly out of scope).

## 2. Decisions locked this session

| Question | Decision | Consequence |
|---|---|---|
| What search does | **Filter the notes list** (find a note) | Not a find-in-editor find bar. One UI, the sidebar search field. |
| Match target | **Full note `text`** | Title is the first line of `text`, so one field covers title + body. |
| Match semantics | **`localizedStandardContains`** (case- + diacritic-insensitive substring) | Apple's recommended user-facing comparison; "café" matches "cafe". |
| Empty query | **Whitespace-only / empty → all notes** | No filtering when the field is clear. |
| Tokenizing | **Whole-query substring only** (no multi-word AND) | YAGNI for v1; revisit if needed. |
| Where logic lives | **Pure `NoteSearch` helper in `PopupNotesCore`** | Testable, mirrors `NoteTitle`; views stay thin. |
| Filtering site | **In `NotesView`, over the `@Query` results** | In-memory, small-N; no store-side predicate. |
| Detail during search | **Selected note resolves from the *full* set** | A note you're editing stays open even if filtered from the list. |
| Selection on search | **Unchanged** (no auto-select of first match) | Less surprising; user clicks a result to switch. |
| ⌘N while searching | **Clears the search first** | A new empty note matches nothing; clearing keeps it visible + selected. |
| No-results UI | **`ContentUnavailableView.search(text:)` in the sidebar** | Native "No Results for …" state. |
| Esc | **Non-empty search → clear; empty search → close panel** | Preserves today's Esc-closes-panel while making Esc clear search first. |

## 3. Goals / Non-goals

**Goals:** quickly find a note by typing; native search field in the sidebar;
⌘F to focus; full-text, case/diacritic-insensitive matching; testable match logic
in Core; the open note stays open while filtering; zero third-party deps retained.

**Non-goals (YAGNI now):** find-within-the-current-note find bar; match
highlighting / snippets in rows; multi-word/token AND matching; regex; search
scopes/filters (by date, tag); search history; store-side `#Predicate` querying.

## 4. The Core helper — `NoteSearch`

New file `PopupNotesCore/Sources/PopupNotesCore/NoteSearch.swift`:

```swift
public enum NoteSearch {
    /// True when `text` matches `query` (case- and diacritic-insensitive
    /// substring). A blank/whitespace-only query matches everything.
    public static func matches(_ text: String, query: String) -> Bool

    /// The subset of `notes` whose `text` matches `query`, order preserved.
    /// A blank/whitespace-only query returns `notes` unchanged.
    public static func filter(_ notes: [Note], matching query: String) -> [Note]
}
```

- Trim the query; if empty after trimming, `matches` → `true` and `filter`
  returns the input unchanged.
- Comparison uses `String.localizedStandardContains(_:)` (case- +
  diacritic-insensitive, Apple's recommended user-facing search comparison).
- `filter` preserves input order (the caller passes already-sorted notes).
- Pure, `@MainActor`-free, no SwiftData fetch — operates on values passed in.

## 5. View changes & data flow

**`NotesView`** ([`NotesView.swift`](../../../PopupNotes/PopupNotes/Views/NotesView.swift)):
- Add `@State private var searchText = ""`.
- Compute `let visible = NoteSearch.filter(notes, matching: searchText)` and pass
  `visible` to `NotesListView` as its `notes`.
- **Detail lookup keeps using the full `notes`** (`notes.first(where:)`), so the
  selected note still renders when filtered out of the list.
- `newNote()` sets `searchText = ""` before creating/selecting the new note.

**`NotesListView`** ([`NotesListView.swift`](../../../PopupNotes/PopupNotes/Views/NotesListView.swift)):
- Add `@Binding var searchText: String`.
- Attach `.searchable(text: $searchText, placement: .sidebar, prompt: "Search Notes")`
  to the `List` (field renders at the top of the sidebar, above the rows). The
  `.sidebar` placement value is a **verify-item** (see §8).
- When `searchText` is non-empty and the (already-filtered) `notes` is empty,
  show `ContentUnavailableView.search(text: searchText)` as an `.overlay` on the
  `List` (the list is empty underneath, so an overlay reads as a replacement).

**Unchanged:** `NoteDetailView`, `NoteTextEditor`, `NotesRepository`, `Note`,
the panel, the container injection. No new files except `NoteSearch.swift` (+ its
test).

## 6. Keyboard & Esc

- **⌘F** focuses the sidebar search field.
- **Esc**:
  - search field non-empty → **clear the search**, stay in the panel;
  - search empty (or unfocused) → **close the panel** (today's `onExitCommand`
    behavior).

The ⌘F-focus mechanism and Esc routing on a **non-activating `NSPanel`** are the
**known-tricky area** (CLAUDE.md flags panel focus / Esc handoff). They are
**verified on hardware**, not assumed. Candidate mechanisms to evaluate against
current SwiftUI docs (do not write from memory): `.searchable(text:isPresented:placement:)`
toggled by a ⌘F `keyboardShortcut`, vs. an always-visible field focused via
`@FocusState`. If `.searchable` fights Esc routing on the panel, fall back to a
hand-rolled sidebar `TextField` (Approach B) — but try native first.

## 7. Alternatives considered (rejected)

- **B — Hand-rolled `TextField` in the sidebar toolbar.** Full control over
  focus/Esc, but reinvents the native search field (against native-first) and is
  more UI for a worse look. Kept only as a fallback if `.searchable` can't be
  made to behave on the panel.
- **C — Dynamic SwiftData `#Predicate` `@Query`.** Filters in the store. Rejected:
  contradicts the repo's "fetch unfiltered, filter in memory" decision;
  `#Predicate` can't use `localizedStandardContains`, so no case/diacritic-
  insensitive matching; over-engineering for a small-N app.

## 8. Verify-against-docs items (per CLAUDE.md — memory is stale)

1. `SearchFieldPlacement.sidebar` (or the correct placement) for a sidebar search
   field in a `NavigationSplitView` on the macOS deployment target.
2. The ⌘F-focus + Esc-clear-then-close interaction on a **non-activating panel**
   (hardware test).
3. `ContentUnavailableView.search(text:)` availability and the right way to show
   it for an empty *sidebar* list.
4. `String.localizedStandardContains(_:)` behavior (confident: case- +
   diacritic-insensitive; confirm signature/availability).

## 9. Testing

- **`NoteSearchTests`** (`PopupNotesCore/Tests/PopupNotesCoreTests/`, Swift
  Testing), runnable via `./scripts/test-core.sh`:
  - empty query → all notes; whitespace-only query → all notes;
  - case-insensitive match (`"NOTE"` matches `"a note"`);
  - diacritic-insensitive match (`"cafe"` matches `"café"`);
  - matches body text beyond the first line (title), not just the title;
  - no match → empty;
  - order preserved.
- **Manual smoke** (on hardware): ⌃⌘N to open; ⌘F focuses the field; type to
  filter; the open note stays in the detail pane while filtered out; Esc with text
  clears the search; Esc again closes the panel; ⌘N while searching clears the
  filter and shows the new note; no-results state appears for a non-matching query.

## 10. Files touched

| File | Change |
|---|---|
| `PopupNotesCore/Sources/PopupNotesCore/NoteSearch.swift` | **New** — pure match/filter helper. |
| `PopupNotesCore/Tests/PopupNotesCoreTests/NoteSearchTests.swift` | **New** — unit tests. |
| `PopupNotes/PopupNotes/Views/NotesView.swift` | `searchText` state; filter via `NoteSearch`; clear on `newNote()`. |
| `PopupNotes/PopupNotes/Views/NotesListView.swift` | `searchText` binding; `.searchable`; no-results state. |
