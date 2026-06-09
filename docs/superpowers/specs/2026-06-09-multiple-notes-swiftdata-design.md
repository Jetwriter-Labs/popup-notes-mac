# Popup Notes — Multiple Notes + Settings (SwiftData) Design

- **Date:** 2026-06-09
- **Status:** Approved (design phase) — ready for implementation planning
- **Supersedes:** the **single-scratchpad** decision in
  [`2026-06-09-popup-notes-architecture-design.md`](2026-06-09-popup-notes-architecture-design.md) (§2)
  and [`2026-06-09-core-capture-flow-design.md`](2026-06-09-core-capture-flow-design.md).
  The hotkey, non-activating panel, menu-bar accessory, and `.accessory` app
  foundations from those specs **still hold** — only the **note model and
  persistence** change, and a **Settings window** is added.
- **Still true:** native-first, **zero third-party dependencies** (SwiftData is a
  first-party Apple framework), menu-bar accessory app, non-activating floating
  panel, ⌃⌘N global hotkey.

## 1. Summary

Popup Notes graduates from a single scratchpad to a lightweight **multiple-notes
manager**. ⌃⌘N drops a **resizable** popup over the current app with a **sidebar
of notes** on the left and the **selected note's editor** on the right. Notes
live in a local **SwiftData** database (SQLite under the hood). A note's
**title is its first line**. A **Settings** window adds **Launch at Login** (on
by default) and **Export/Import to JSON**. The existing scratchpad migrates into
the first note. **Search** is a planned future feature that SwiftData makes
straightforward; it is **not built now**.

## 2. Decisions locked this session

| Question | Decision | Consequence |
|---|---|---|
| Note model | **Multiple notes**; **title = first non-empty line** | No separate "name" field; sidebar shows the first line; capture stays instant. |
| Persistence | **SwiftData** (`@Model`, SQLite-backed) | Modern, native, zero third-party dep; enables future search via `#Predicate`. Replaces the single `.md` file. |
| Sort order | **Most-recently-modified first** | Editing a note bumps it to the top. |
| Panel | **Resizable; frame + sidebar width remembered**; ~720×460 default | Reverses the earlier fixed-480×320 decision (needed for sidebar + detail). |
| Open behavior | **⌃⌘N reopens the last-selected note** (caret at end); **⌘N** = new note | Resume where you left off; quick new-note in-panel. |
| Delete | **Confirmation required** | Guards against accidental loss. |
| Settings | SwiftUI **`Settings` scene**: Launch at Login + Export/Import | ⌘, and a menu item open it. |
| Launch at Login | **On by default, first launch only** (UserDefaults flag) | Subsequent user toggles are respected. |
| Export / Import | **All notes ↔ one JSON file**; **import upserts by `id`** | Backup + portability; replaces "Open Notes Folder" (DB is opaque). |
| Migration | Legacy `scratchpad.md` → first note, **one-time** | No data loss; old file left in place. |
| Search | **Deferred** (not built) | SwiftData `#Predicate` substring filter when added. |

## 3. Goals / Non-goals

**Goals:** multiple notes with a master-detail UI; durable local DB; instant
capture preserved; data portability (JSON export/import); launch-at-login
default; no data loss migrating the existing note; zero third-party deps
retained.

**Non-goals (YAGNI now):** search (planned, not built), tags, folders/notebooks,
rich text / Markdown rendering, sync / iCloud, multi-window, attachments.

## 4. Data model & storage

- **`@Model final class Note`**: `id: UUID`, `text: String`, `created: Date`,
  `modified: Date`.
  - `var title: String` — **computed**: first non-empty trimmed line of `text`;
    `"New Note"` when empty. (Computed, not stored.)
  - Editing `text` sets `modified = .now`.
- **`ModelContainer`** for `Note`, stored at
  `~/Library/Application Support/PopupNotes/Notes.store` (custom
  `ModelConfiguration` URL). Built once at launch and shared.
- **Persistence:** SwiftData autosaves; additionally `try? context.save()` on
  panel hide and on app terminate. In-memory `Note` mutations are the source of
  truth between saves.
- **Listing:** all `Note` sorted by `modified` descending (`@Query(sort:)` in the
  list view; `FetchDescriptor` in the repository for non-view code).
- **`ExportedNote`** (plain `Codable` struct: `id`, `text`, `created`,
  `modified`) — the JSON-facing DTO, **decoupled** from the `@Model` class so the
  JSON codec is pure and testable.

## 5. Notes UX

- **Layout:** `NavigationSplitView` hosted in the `FloatingPanel`. Sidebar =
  `@Query` list showing **title (first line)** + a secondary line (relative
  modified date). Detail = `TextEditor` bound to the selected note's `text`.
- **Selection:** `selection: Note.ID?`; clicking a note shows it in the detail.
- **New note (`+` in the sidebar toolbar, and ⌘N):** insert an empty `Note`,
  select it, focus the editor.
- **Delete (right-click → Delete, or ⌫ on a selected row):** show a
  **confirmation dialog**; on confirm, remove it and select the next/most-recent.
- **On show (⌃⌘N):** restore the **last-selected note** (persisted id; fall back
  to most-recent), focus the detail editor with the caret at end. If the DB has
  **zero notes**, auto-create one empty note and select it.
- **Title editing:** none — the title is the first line; editing the text updates
  the sidebar live. Empty body → sidebar shows `"New Note"`.

## 6. Settings window

- A SwiftUI **`Settings` scene** (opens via **⌘,** and a **"Settings…"** item in
  both menus).
- **Launch at Login:** a `Toggle` reflecting `SMAppService.mainApp.status ==
  .enabled`, toggling `register()` / `unregister()`. **Default-on:** on first
  launch (guarded by `UserDefaults` key `didApplyFirstRunDefaults`), call
  `register()` once; thereafter respect the user.
- **Export:** "Export Notes…" → `NSSavePanel` (default name
  `PopupNotes-export.json`) → write **all** notes as a pretty-printed JSON
  **array** of `ExportedNote`, ISO-8601 dates.
- **Import:** "Import Notes…" → `NSOpenPanel` (`.json`) → decode `[ExportedNote]`
  → **upsert by `id`** (existing id updates that note; new id inserts). Report
  count imported; a malformed file shows an error alert and changes nothing.

### JSON schema (export/import)
```json
[
  {
    "id": "5F1C…-UUID",
    "text": "Groceries\nmilk\neggs",
    "created": "2026-06-09T18:20:00Z",
    "modified": "2026-06-09T18:25:00Z"
  }
]
```

## 7. Migration (one-time)

On launch, if `UserDefaults` key `didMigrateLegacyScratchpad` is unset:
- If `~/Library/Application Support/PopupNotes/scratchpad.md` exists and is
  non-empty, insert a `Note` with its contents (created/modified = file dates or
  now).
- Set the flag regardless (runs once). **Leave the old file in place** (never
  delete user data).

## 8. Menus (Open Notes Folder removed)

- **⋯ popup menu:** New Note · Settings… · Quit Popup Notes.
- **Menu-bar fallback (`MenuBarExtra`):** Show Notes · New Note · Settings… ·
  Quit Popup Notes.
- The old "Open Notes File/Folder" affordance is gone (the DB is opaque); data
  access is now **Export** in Settings.

## 9. Components

**Core package `PopupNotesCore` (unit-tested):**
- `Note` — `@Model` (id, text, created, modified; computed `title`).
- `NoteTitle` — pure helper: `title(from:)` deriving the first-line title.
- `NotesRepository` — wraps a `ModelContext`: `allSortedByModified()`,
  `create()`, `delete(_:)`, `upsert(_ exported:)`, `note(id:)`.
- `ExportedNote` (`Codable`) + `NotesJSON` — `encode([Note]) -> Data` /
  `decode(_ data:) -> [ExportedNote]`.
- `LegacyScratchpad` — `importIfPresent(into:)` reading the old `.md`.

**App target `PopupNotes`:**
- `NotesView` — the `NavigationSplitView`; owns `selection`.
- `NotesListView` — sidebar `@Query` list (title + date), `+` toolbar,
  delete-with-confirm.
- `NoteDetailView` — editor bound to the selected note; caret-at-end on
  appear/selection.
- `SettingsView` + `Settings` scene — Launch at Login toggle, Export/Import.
- `FloatingPanel` — **+ resizable styleMask, + frame autosave**
  (`setFrameAutosaveName`) and persisted sidebar width.
- `LaunchAtLogin` — **+ first-run default-enable**.
- `AppDelegate` — builds the shared `ModelContainer`, runs migration + first-run
  defaults, wires hotkey → panel, saves on terminate.
- `PopupNotesApp` — `MenuBarExtra` (updated items) + `Settings` scene +
  `.modelContainer(shared)`.
- `PanelController` — hosts `NotesView` with `.modelContainer(shared)`;
  persists/restores the last selection.

The single-note `NoteStore` / `NoteFile` / `Debouncing` / `ScratchpadView` are
**replaced** by the above and removed once the new path works. `HotKeyCombo` /
`HotKeyManager` / the panel/menu-bar foundations are **kept**.

## 10. Testing

- **Pure logic (always unit-tested in core, runs on the toolchain):**
  `NoteTitle.title(from:)`; `NotesJSON` encode/decode round-trip + malformed
  input; `LegacyScratchpad.importIfPresent` (temp file → note).
- **SwiftData CRUD:** `NotesRepository` against an **in-memory `ModelContainer`**
  (`isStoredInMemoryOnly: true`) — create/delete/sort/upsert. **Verify early**
  that this runs under `swift test`; if not, cover via the app + manual checks
  (the pure logic above still gives strong coverage).
- **UI / integration (manual):** sidebar+detail, new/delete/select, resizable +
  remembered panel, settings export/import round-trip, launch-at-login default,
  migration, ⌃⌘N reopen-last + ⌘N new.

## 11. Acceptance criteria (manual, after build)

1. ⌃⌘N opens the resizable popup with a sidebar + editor; the last-selected note
   shows, caret at end.
2. `+` / ⌘N creates a note, selects it, focuses the editor; typing a first line
   updates its sidebar title live.
3. Notes sort most-recently-edited first.
4. Right-click → Delete asks to confirm; confirming removes it.
5. Resize + move the panel and adjust the sidebar; quit and reopen → size,
   position, and sidebar width restored.
6. Settings (⌘,): Launch at Login reflects/sets the real Login Items state; it is
   ON after a clean first run.
7. Export writes a JSON file of all notes; importing it upserts (no duplicates on
   re-import); a bad file errors without changing data.
8. First run with an existing `scratchpad.md` imports it as a note; not imported
   twice.
9. Still a non-activating overlay over a full-screen app and across Spaces.

## 12. Risks / verify-early (per CLAUDE.md "verify against current docs")

- **SwiftData testability via `swift test`** — confirm in-memory-container tests
  run on the toolchain at the start of implementation; fall back to pure-logic
  tests + manual if not.
- **`@Query` / `.modelContainer` inside the hosted `NSHostingView` panel** (not a
  `WindowGroup`) — verify list updates + context propagation there; if `@Query`
  misbehaves, drive the list from `NotesRepository` fetches instead.
- **Current SwiftData APIs** — verify names/signatures and macOS 15 availability
  against current Apple docs before relying on memory.
- **CLAUDE.md** described the single-note model — updated to the SwiftData
  multiple-notes architecture during implementation. ✓
- **Sandbox (decided during implementation):** the Xcode app template enables
  App Sandbox; we **kept it** (supersedes the original specs' non-sandboxed
  plan). Data lives in the app container
  (`~/Library/Containers/com.gorvgoyl.PopupNotes/…/PopupNotes/Notes.store`),
  not a user-visible folder; JSON export/import is the portability path.
