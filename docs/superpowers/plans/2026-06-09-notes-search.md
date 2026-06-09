# Notes Search (Filter the List) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a sidebar search field that filters the notes list by full-text, case/diacritic-insensitive match, with ⌘F to focus.

**Architecture:** A pure, unit-tested `NoteSearch` helper in `PopupNotesCore` (mirrors the existing `NoteTitle`) does the matching. `NotesView` filters its `@Query` results through it and passes the filtered array to `NotesListView`, which hosts a native `.searchable` field. The detail pane keeps resolving the selected note from the *unfiltered* set, so the open note stays open while filtering. Built in three commits: tested helper → working clickable filter → ⌘F focus.

**Tech Stack:** Swift 6.3, SwiftUI (`.searchable`, `ContentUnavailableView`), SwiftData (`@Query`), Swift Testing, `String.localizedStandardContains`. Zero third-party deps.

**Design spec:** [`docs/superpowers/specs/2026-06-09-notes-search-design.md`](../specs/2026-06-09-notes-search-design.md)

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `PopupNotesCore/Sources/PopupNotesCore/NoteSearch.swift` | Pure match/filter logic | **Create** |
| `PopupNotesCore/Tests/PopupNotesCoreTests/NoteSearchTests.swift` | Unit tests for the helper | **Create** |
| `PopupNotes/PopupNotes/Views/NotesView.swift` | Owns `searchText`, filters, clears on new note | **Modify** |
| `PopupNotes/PopupNotes/Views/NotesListView.swift` | Hosts `.searchable` + no-results state | **Modify** |

**Verify-against-docs reminder (CLAUDE.md — your training data is stale):** the SwiftUI search APIs below (`SearchFieldPlacement.sidebar`, the `.searchable(text:isPresented:)` overload, `ContentUnavailableView.search(text:)`) and the ⌘F/Esc routing on a *non-activating `NSPanel`* must be confirmed against current docs and on hardware. Each task says where. `String.localizedStandardContains(_:)` is high-confidence (case- + diacritic-insensitive) but confirm the signature.

---

## Task 1: `NoteSearch` helper in Core (TDD)

**Files:**
- Create: `PopupNotesCore/Tests/PopupNotesCoreTests/NoteSearchTests.swift`
- Create: `PopupNotesCore/Sources/PopupNotesCore/NoteSearch.swift`

- [ ] **Step 1: Write the failing tests**

Create `PopupNotesCore/Tests/PopupNotesCoreTests/NoteSearchTests.swift`:

```swift
import Testing
import Foundation
@testable import PopupNotesCore

@Suite struct NoteSearchTests {
    // MARK: matches(_:query:)
    @Test func emptyQueryMatchesAll() { #expect(NoteSearch.matches("anything", query: "")) }
    @Test func whitespaceQueryMatchesAll() { #expect(NoteSearch.matches("anything", query: "  \n ")) }
    @Test func caseInsensitive() { #expect(NoteSearch.matches("a Note here", query: "NOTE")) }
    @Test func diacriticInsensitive() { #expect(NoteSearch.matches("le café", query: "cafe")) }
    @Test func substringMatches() { #expect(NoteSearch.matches("groceries", query: "cer")) }
    @Test func noMatch() { #expect(!NoteSearch.matches("hello world", query: "zzz")) }

    // MARK: filter(_:matching:)
    @Test func filterEmptyReturnsAll() {
        let notes = [Note(text: "one"), Note(text: "two")]
        #expect(NoteSearch.filter(notes, matching: "  ").count == 2)
    }
    @Test func filterMatchesBodyNotJustTitle() {
        let a = Note(text: "Groceries\nmilk and eggs")
        let b = Note(text: "Ideas\nbuild an app")
        let result = NoteSearch.filter([a, b], matching: "eggs")
        #expect(result.count == 1)
        #expect(result.first?.id == a.id)
    }
    @Test func filterPreservesOrder() {
        let a = Note(text: "alpha note")
        let b = Note(text: "beta note")
        let result = NoteSearch.filter([a, b], matching: "note")
        #expect(result.map(\.id) == [a.id, b.id])
    }
    @Test func filterNoMatchIsEmpty() {
        let notes = [Note(text: "one"), Note(text: "two")]
        #expect(NoteSearch.filter(notes, matching: "zzz").isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./scripts/test-core.sh --filter NoteSearchTests`
Expected: **FAIL** — build error `cannot find 'NoteSearch' in scope` (the type doesn't exist yet). This is the TDD "red".

- [ ] **Step 3: Write the minimal implementation**

Create `PopupNotesCore/Sources/PopupNotesCore/NoteSearch.swift`:

```swift
import Foundation

/// Filters notes by a user-typed query: a case- and diacritic-insensitive
/// substring match against the note's full text. A blank query matches all.
/// Pure (no SwiftData fetch) and mirrors `NoteTitle` — unit-tested in Core.
public enum NoteSearch {
    /// True when `text` contains `query` (case- + diacritic-insensitive).
    /// A blank / whitespace-only query matches everything.
    public static func matches(_ text: String, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return text.localizedStandardContains(trimmed)
    }

    /// The subset of `notes` whose `text` matches `query`, order preserved.
    /// A blank / whitespace-only query returns `notes` unchanged.
    public static func filter(_ notes: [Note], matching query: String) -> [Note] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return notes }
        return notes.filter { $0.text.localizedStandardContains(trimmed) }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./scripts/test-core.sh --filter NoteSearchTests`
Expected: **PASS** — all 10 tests green.

- [ ] **Step 5: Run the full Core suite (no regressions)**

Run: `./scripts/test-core.sh`
Expected: **PASS** — existing suites (`NoteTitleTests`, `NoteModelTests`, `NotesJSONTests`, `NotesRepositoryTests`, etc.) still green.

- [ ] **Step 6: Commit**

```bash
git add PopupNotesCore/Sources/PopupNotesCore/NoteSearch.swift \
        PopupNotesCore/Tests/PopupNotesCoreTests/NoteSearchTests.swift
git commit -m "feat(core): NoteSearch full-text match/filter helper"
```

---

## Task 2: Filter the sidebar list (working, clickable search)

Delivers a fully usable search: an always-visible sidebar field that filters live, a no-results state, ⌘N clears the filter, and Esc clears-then-closes. (⌘F focus comes in Task 3.)

**Files:**
- Modify: `PopupNotes/PopupNotes/Views/NotesListView.swift`
- Modify: `PopupNotes/PopupNotes/Views/NotesView.swift`

- [ ] **Step 1: Add the search field + no-results state to `NotesListView`**

In `PopupNotes/PopupNotes/Views/NotesListView.swift`, add a `searchText` binding to the properties (just after the `selection` binding):

```swift
    let notes: [Note]
    @Binding var selection: UUID?
    @Binding var searchText: String
    var onNew: () -> Void
    var onDelete: (Note) -> Void
```

Then attach `.searchable` and the no-results overlay to the `List`. Replace the existing `List { … }` closing — specifically, insert the two modifiers between the end of the `List(selection:) { … }` block and the existing `.toolbar {`:

```swift
        List(selection: $selection) {
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title).lineLimit(1)
                    Text(note.modified, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(note.id)
                .contextMenu {
                    Button("Delete", role: .destructive) { pendingDelete = note }
                }
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search Notes")
        .overlay {
            if !searchText.isEmpty && notes.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .toolbar {
```

Leave the `.toolbar { … }` and `.confirmationDialog { … }` blocks exactly as they are.

> **Verify (docs):** confirm `SearchFieldPlacement.sidebar` exists for the macOS deployment target. If the build rejects `.sidebar`, drop the `placement:` argument (i.e. `.searchable(text: $searchText, prompt: "Search Notes")`) — `.automatic` places the field in the sidebar on macOS. Confirm `ContentUnavailableView.search(text:)` is available; it is macOS 14+.

- [ ] **Step 2: Wire `searchText`, filtering, and the Esc/⌘N behavior into `NotesView`**

In `PopupNotes/PopupNotes/Views/NotesView.swift`:

(a) Add the state, just after `@State private var selection: UUID?`:

```swift
    @State private var selection: UUID?
    @State private var searchText = ""
    @AppStorage("lastSelectedNoteID") private var lastSelectedRaw = ""
```

(b) Pass the **filtered** notes and the `searchText` binding into `NotesListView`:

```swift
            NotesListView(notes: NoteSearch.filter(notes, matching: searchText),
                          selection: $selection,
                          searchText: $searchText,
                          onNew: newNote,
                          onDelete: delete)
                .navigationSplitViewColumnWidth(min: 130, ideal: 200)
```

(The `detail:` branch is unchanged — it still does `notes.first(where: { $0.id == id })` over the **unfiltered** `notes`, so the open note stays visible while the list is filtered.)

(c) Replace the `.onExitCommand { onEscape() }` modifier so Esc clears a non-empty search first:

```swift
        .onExitCommand {
            if searchText.isEmpty { onEscape() } else { searchText = "" }
        }
```

(d) Update `newNote()` to clear the search before creating a note (otherwise the new empty note matches nothing and vanishes from the filtered list):

```swift
    private func newNote() {
        searchText = ""
        let note = Note()
        context.insert(note)
        selection = note.id
    }
```

> `NoteSearch` is already in scope — `NotesView.swift` imports `PopupNotesCore`.

- [ ] **Step 3: Build the app**

Run: `xcodebuild -scheme PopupNotes -configuration Debug build`
Expected: **BUILD SUCCEEDED**. If `.searchable(placement: .sidebar)` fails to compile, apply the `.automatic` fallback from Step 1 and rebuild.

- [ ] **Step 4: Manual smoke test (on hardware)**

Launch the built app (from Xcode Run, or the built `.app`), then verify:
1. Press **⌃⌘N** — the popup opens with a search field at the top of the sidebar.
2. Type a term present in one note's body (not its first line) — the list narrows to matching notes; clearing the field restores the full list.
3. Select a note, then type a query that excludes it — **the note stays open in the detail pane** even though it's gone from the list.
4. Type a query that matches nothing — the sidebar shows **"No Results for …"**.
5. With text in the field, press **Esc** — the search clears (panel stays open). Press **Esc** again — the panel closes.
6. With a filter active, press **⌘N** — the filter clears and a new empty note is created and selected.

- [ ] **Step 5: Commit**

```bash
git add PopupNotes/PopupNotes/Views/NotesView.swift \
        PopupNotes/PopupNotes/Views/NotesListView.swift
git commit -m "feat(app): filter the notes list with a sidebar search field"
```

---

## Task 3: ⌘F focuses the search field

Adds the keyboard affordance. Uses the `isPresented:` overload (the supported lever for programmatically revealing/focusing the field) toggled by a hidden ⌘F button — the same `keyboardShortcut` mechanism the working **⌘N** toolbar button already proves fires inside this panel.

**Files:**
- Modify: `PopupNotes/PopupNotes/Views/NotesListView.swift`
- Modify: `PopupNotes/PopupNotes/Views/NotesView.swift`

- [ ] **Step 1: Add a `searchPresented` binding and switch to the `isPresented` overload in `NotesListView`**

In `PopupNotes/PopupNotes/Views/NotesListView.swift`, add the binding to the properties:

```swift
    let notes: [Note]
    @Binding var selection: UUID?
    @Binding var searchText: String
    @Binding var searchPresented: Bool
    var onNew: () -> Void
    var onDelete: (Note) -> Void
```

Change the `.searchable` modifier to the `isPresented` overload and gate the overlay on `searchPresented`:

```swift
        .searchable(text: $searchText, isPresented: $searchPresented,
                    placement: .sidebar, prompt: "Search Notes")
        .overlay {
            if searchPresented && !searchText.isEmpty && notes.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
```

- [ ] **Step 2: Add `searchPresented` state + the hidden ⌘F button in `NotesView`**

In `PopupNotes/PopupNotes/Views/NotesView.swift`:

(a) Add the state next to `searchText`:

```swift
    @State private var searchText = ""
    @State private var searchPresented = false
```

(b) Pass the new binding into `NotesListView`:

```swift
            NotesListView(notes: NoteSearch.filter(notes, matching: searchText),
                          selection: $selection,
                          searchText: $searchText,
                          searchPresented: $searchPresented,
                          onNew: newNote,
                          onDelete: delete)
                .navigationSplitViewColumnWidth(min: 130, ideal: 200)
```

(c) Add a hidden ⌘F button as a `.background` on the `NavigationSplitView` (place it right before `.frame(minWidth: 360, minHeight: 220)`):

```swift
        .background {
            Button("Find") { searchPresented = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .frame(minWidth: 360, minHeight: 220)
```

- [ ] **Step 3: Build the app**

Run: `xcodebuild -scheme PopupNotes -configuration Debug build`
Expected: **BUILD SUCCEEDED**.

> **Verify (docs):** confirm the `.searchable(text:isPresented:placement:prompt:)` overload exists for the deployment target. If it doesn't compile, keep the always-visible field from Task 2 (revert to `.searchable(text:placement:prompt:)`, drop `searchPresented`) and instead expose Find as a visible toolbar button — search still works fully without ⌘F.

- [ ] **Step 4: Manual smoke test (on hardware) — the tricky panel-focus path**

1. Open the popup (**⌃⌘N**), then press **⌘F** — keyboard focus lands in the search field (you can type immediately without clicking).
2. Type a term — the list filters as in Task 2.
3. Press **Esc** with text present — the search clears; press **Esc** again — the panel closes. (The Task 2 `onExitCommand` still governs this.)
4. Re-confirm all six Task 2 smoke checks still pass.

> If ⌘F does **not** focus the field on hardware, apply the toolbar-button fallback from Step 3 and note it in the commit. Do not guess at alternate focus APIs — verify against current SwiftUI docs first.

- [ ] **Step 5: Commit**

```bash
git add PopupNotes/PopupNotes/Views/NotesView.swift \
        PopupNotes/PopupNotes/Views/NotesListView.swift
git commit -m "feat(app): ⌘F focuses the notes search field"
```

---

## Self-Review

**Spec coverage** (against `2026-06-09-notes-search-design.md`):
- §4 `NoteSearch` (match target = full text, `localizedStandardContains`, blank → all, order preserved) → **Task 1**.
- §5 view wiring (`searchText` state, filter over `@Query`, detail from full set, ⌘N clears) → **Task 2 Steps 2a/2b/2d**.
- §5 `.searchable` in sidebar + no-results overlay → **Task 2 Step 1**.
- §6 Esc clears-then-closes → **Task 2 Step 2c**; ⌘F focus → **Task 3**.
- §9 tests (empty/whitespace → all, case- and diacritic-insensitive, body-not-just-title, no-match, order) → **Task 1 Step 1**; manual smoke → **Task 2 Step 4 / Task 3 Step 4**.
- §8 verify-items called out at each relevant step.

**Placeholder scan:** none — every code step shows complete code; every run step shows the command and expected result. The "verify on hardware" notes are paired with concrete primary code plus a concrete fallback, not deferrals.

**Type consistency:** `NoteSearch.matches(_:query:)` / `NoteSearch.filter(_:matching:)` are defined in Task 1 and called with those exact signatures in Task 2. `searchText: Binding<String>` and `searchPresented: Binding<Bool>` are introduced in `NotesListView` (Task 2 / Task 3) and supplied by `NotesView` in the same tasks. `AppStorage("lastSelectedNoteID")` is preserved unchanged.
