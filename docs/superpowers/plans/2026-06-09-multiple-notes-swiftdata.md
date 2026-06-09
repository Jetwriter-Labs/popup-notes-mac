# Multiple Notes + Settings (SwiftData) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single scratchpad with a SwiftData-backed multi-note manager — sidebar/detail UI in a resizable popup, first-line titles, a Settings window (launch-at-login default + JSON export/import), and one-time migration of the existing note.

**Architecture:** A `PopupNotesCore` package holds the data layer: a SwiftData `@Model Note`, a `NotesRepository` over `ModelContext`, a pure `ExportedNote`/`NotesJSON` codec, a `NoteTitle` helper, and legacy-import. The app hosts a `NavigationSplitView` (sidebar `@Query` list + detail editor) inside the existing non-activating `FloatingPanel`, plus a SwiftUI `Settings` scene. Pure logic is unit-tested; SwiftData CRUD is tested against an in-memory container.

**Tech Stack:** Swift 6, SwiftData (first-party, SQLite-backed), SwiftUI `NavigationSplitView` + `@Query`, AppKit panel, `SMAppService`, Swift Testing. Zero third-party dependencies. Spec: [`docs/superpowers/specs/2026-06-09-multiple-notes-swiftdata-design.md`](../specs/2026-06-09-multiple-notes-swiftdata-design.md).

---

## ⚠️ Build/verify commands

- **Core tests:** `./scripts/test-core.sh` (auto-detects Xcode vs CLT toolchain).
- **App build:** `xcodebuild -project PopupNotes/PopupNotes.xcodeproj -scheme PopupNotes -configuration Debug -derivedDataPath .build/xcode-dd build`
- **Relaunch:** `killall PopupNotes 2>/dev/null; open .build/xcode-dd/Build/Products/Debug/PopupNotes.app`
- Commit straight to `main` after each task; the PostToolUse hook auto-pushes.

## File structure

```
PopupNotesCore/Sources/PopupNotesCore/
  HotKeyCombo.swift          # KEEP (unchanged)
  Note.swift                 # NEW  @Model: id, text, created, modified; computed title
  NoteTitle.swift            # NEW  pure: first-line title
  ExportedNote.swift         # NEW  Codable DTO + Note<->DTO mapping
  NotesJSON.swift            # NEW  pure: encode/decode [ExportedNote]
  LegacyScratchpad.swift     # NEW  pure: read old scratchpad.md
  NotesRepository.swift      # NEW  ModelContext CRUD (create/delete/sort/upsert/save)
  NoteStore.swift            # DELETE (Task 11)
  NoteFile.swift             # DELETE (Task 11)
  Debouncing.swift           # DELETE (Task 11)
PopupNotes/PopupNotes/
  PopupNotesApp.swift        # MODIFY  MenuBarExtra items + Settings scene + .modelContainer
  AppDelegate.swift          # MODIFY  build ModelContainer; migration + first-run defaults; save on quit
  Panel/PanelController.swift# MODIFY  host NotesView w/ .modelContainer; persist last selection
  Panel/FloatingPanel.swift  # MODIFY  + .resizable, + frame autosave
  Views/NotesView.swift      # NEW  NavigationSplitView container
  Views/NotesListView.swift  # NEW  sidebar @Query list + new/delete
  Views/NoteDetailView.swift # NEW  editor bound to selected note
  Views/ScratchpadView.swift # DELETE (Task 11)
  Settings/SettingsView.swift# NEW  launch-at-login + export/import
  Support/LaunchAtLogin.swift# MODIFY  + firstRunEnableDefault()
  Support/NotesFile.swift    # DELETE (Task 11; "Open Notes Folder" removed)
```

---

# PHASE A — De-risk SwiftData testing

### Task 0: Confirm SwiftData in-memory tests run on the toolchain

**Files:** Test: `PopupNotesCore/Tests/PopupNotesCoreTests/SwiftDataProbeTests.swift` (temporary)

- [ ] **Step 1: Add `SwiftData` to the package** — edit `PopupNotesCore/Package.swift` target so the platform is current. Confirm `platforms: [.macOS(.v14)]` (SwiftData needs macOS 14+). No dependency line needed (SwiftData is in the SDK).

- [ ] **Step 2: Write a probe test**

`SwiftDataProbeTests.swift`:
```swift
import Testing
import SwiftData
import Foundation

@Model final class ProbeItem { var n: Int; init(n: Int) { self.n = n } }

@MainActor
@Test func swiftDataInMemoryWorks() throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: ProbeItem.self, configurations: config)
    let ctx = ModelContext(container)
    ctx.insert(ProbeItem(n: 7))
    let items = try ctx.fetch(FetchDescriptor<ProbeItem>())
    #expect(items.count == 1)
    #expect(items.first?.n == 7)
}
```

- [ ] **Step 3: Run it**

Run: `./scripts/test-core.sh`
Expected: PASS. **If it fails** (SwiftData unavailable under `swift test`): mark `NotesRepository` tests (Task 5) as "manual via app" in this plan, keep all pure-logic tests, and proceed. Record the outcome in the commit message.

- [ ] **Step 4: Delete the probe and commit the finding**

```bash
rm PopupNotesCore/Tests/PopupNotesCoreTests/SwiftDataProbeTests.swift
git add -A && git commit -m "chore(core): confirm SwiftData in-memory testing on the toolchain"
```

---

# PHASE B — Core data layer (TDD)

### Task 1: `NoteTitle` — first-line title

**Files:** Create `PopupNotesCore/Sources/PopupNotesCore/NoteTitle.swift`; Test `PopupNotesCore/Tests/PopupNotesCoreTests/NoteTitleTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import PopupNotesCore

@Suite struct NoteTitleTests {
    @Test func emptyIsNewNote() { #expect(NoteTitle.title(from: "") == "New Note") }
    @Test func whitespaceOnlyIsNewNote() { #expect(NoteTitle.title(from: "   \n\n ") == "New Note") }
    @Test func firstNonEmptyLine() { #expect(NoteTitle.title(from: "Hello\nworld") == "Hello") }
    @Test func skipsLeadingBlankLines() { #expect(NoteTitle.title(from: "\n\n  Groceries \nmilk") == "Groceries") }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `./scripts/test-core.sh` — Expected: FAIL (`cannot find 'NoteTitle'`).

- [ ] **Step 3: Implement**

`NoteTitle.swift`:
```swift
/// Derives a note's display title from its body: the first non-empty,
/// whitespace-trimmed line, or "New Note" when the body is blank.
public enum NoteTitle {
    public static func title(from text: String) -> String {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return "New Note"
    }
}
```

- [ ] **Step 4: Run to verify pass** — `./scripts/test-core.sh` → PASS.

- [ ] **Step 5: Commit**

```bash
git add PopupNotesCore && git commit -m "feat(core): NoteTitle first-line title helper"
```

---

### Task 2: `Note` `@Model` + `ExportedNote` DTO

**Files:** Create `PopupNotesCore/Sources/PopupNotesCore/Note.swift`, `PopupNotesCore/Sources/PopupNotesCore/ExportedNote.swift`; Test `PopupNotesCore/Tests/PopupNotesCoreTests/NoteModelTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import PopupNotesCore

@Suite struct NoteModelTests {
    @Test func titleReflectsText() {
        let note = Note(text: "Shopping\nmilk")
        #expect(note.title == "Shopping")
    }
    @Test func exportedRoundTripsToNoteValues() {
        let d = Date(timeIntervalSince1970: 1_000_000)
        let e = ExportedNote(id: UUID(), text: "hi", created: d, modified: d)
        #expect(e.text == "hi")
        #expect(e.created == d)
    }
}
```

- [ ] **Step 2: Run to verify fail** — Expected: FAIL (`cannot find 'Note'`).

- [ ] **Step 3: Implement**

`Note.swift`:
```swift
import Foundation
import SwiftData

@Model
public final class Note {
    public var id: UUID
    public var text: String
    public var created: Date
    public var modified: Date

    public init(id: UUID = UUID(), text: String = "", created: Date = .now, modified: Date = .now) {
        self.id = id
        self.text = text
        self.created = created
        self.modified = modified
    }

    /// Display title — first non-empty line of `text` (not persisted).
    public var title: String { NoteTitle.title(from: text) }
}
```

`ExportedNote.swift`:
```swift
import Foundation

/// Plain JSON-facing representation of a note, decoupled from the @Model class.
public struct ExportedNote: Codable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var created: Date
    public var modified: Date

    public init(id: UUID, text: String, created: Date, modified: Date) {
        self.id = id; self.text = text; self.created = created; self.modified = modified
    }

    public init(_ note: Note) {
        self.init(id: note.id, text: note.text, created: note.created, modified: note.modified)
    }
}
```

> ⚠️ VERIFY: `@Model` macro + `UUID`/`Date` stored properties compile under the current SwiftData. If the macro errors, confirm `import SwiftData` and macOS 14+ target.

- [ ] **Step 4: Run to verify pass** — PASS.

- [ ] **Step 5: Commit**

```bash
git add PopupNotesCore && git commit -m "feat(core): Note @Model and ExportedNote DTO"
```

---

### Task 3: `NotesJSON` codec

**Files:** Create `PopupNotesCore/Sources/PopupNotesCore/NotesJSON.swift`; Test `PopupNotesCore/Tests/PopupNotesCoreTests/NotesJSONTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import PopupNotesCore

@Suite struct NotesJSONTests {
    @Test func roundTrips() throws {
        let d = Date(timeIntervalSince1970: 1_700_000_000)
        let notes = [ExportedNote(id: UUID(), text: "a\nb", created: d, modified: d)]
        let data = try NotesJSON.encode(notes)
        #expect(try NotesJSON.decode(data) == notes)
    }
    @Test func malformedThrows() {
        #expect(throws: (any Error).self) {
            _ = try NotesJSON.decode(Data("not json".utf8))
        }
    }
    @Test func usesISO8601Dates() throws {
        let d = Date(timeIntervalSince1970: 0)
        let data = try NotesJSON.encode([ExportedNote(id: UUID(), text: "x", created: d, modified: d)])
        #expect(String(decoding: data, as: UTF8.self).contains("1970-01-01T00:00:00Z"))
    }
}
```

- [ ] **Step 2: Run to verify fail** — FAIL (`cannot find 'NotesJSON'`).

- [ ] **Step 3: Implement**

`NotesJSON.swift`:
```swift
import Foundation

public enum NotesJSON {
    public static func encode(_ notes: [ExportedNote]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(notes)
    }

    public static func decode(_ data: Data) throws -> [ExportedNote] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ExportedNote].self, from: data)
    }
}
```

- [ ] **Step 4: Run to verify pass** — PASS.

- [ ] **Step 5: Commit**

```bash
git add PopupNotesCore && git commit -m "feat(core): NotesJSON export/import codec"
```

---

### Task 4: `LegacyScratchpad` reader

**Files:** Create `PopupNotesCore/Sources/PopupNotesCore/LegacyScratchpad.swift`; Test `PopupNotesCore/Tests/PopupNotesCoreTests/LegacyScratchpadTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import PopupNotesCore

@Suite struct LegacyScratchpadTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("legacy-\(UUID().uuidString).md")
    }
    @Test func missingFileReturnsNil() {
        #expect(LegacyScratchpad.read(at: tempURL()) == nil)
    }
    @Test func emptyFileReturnsNil() throws {
        let url = tempURL(); try "  \n\n".write(to: url, atomically: true, encoding: .utf8)
        #expect(LegacyScratchpad.read(at: url) == nil)
        try? FileManager.default.removeItem(at: url)
    }
    @Test func nonEmptyReturnsContents() throws {
        let url = tempURL(); try "old note\nline2".write(to: url, atomically: true, encoding: .utf8)
        #expect(LegacyScratchpad.read(at: url) == "old note\nline2")
        try? FileManager.default.removeItem(at: url)
    }
}
```

- [ ] **Step 2: Run to verify fail** — FAIL.

- [ ] **Step 3: Implement**

`LegacyScratchpad.swift`:
```swift
import Foundation

/// Reads the pre-SwiftData single scratchpad file for one-time migration.
public enum LegacyScratchpad {
    /// Returns the file's text, or nil if missing/unreadable/blank.
    public static func read(at url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    /// Default location of the legacy file.
    public static func defaultURL(fileManager: FileManager = .default) -> URL? {
        try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                             appropriateFor: nil, create: false)
            .appendingPathComponent("PopupNotes/scratchpad.md")
    }
}
```

- [ ] **Step 4: Run to verify pass** — PASS.

- [ ] **Step 5: Commit**

```bash
git add PopupNotesCore && git commit -m "feat(core): LegacyScratchpad reader for migration"
```

---

### Task 5: `NotesRepository` — SwiftData CRUD

**Files:** Create `PopupNotesCore/Sources/PopupNotesCore/NotesRepository.swift`; Test `PopupNotesCore/Tests/PopupNotesCoreTests/NotesRepositoryTests.swift`

> If Task 0 failed, write `NotesRepository` per Step 3 but skip the test (verify via the app in Phase C) and note it in the commit.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import SwiftData
import Foundation
@testable import PopupNotesCore

@MainActor
@Suite struct NotesRepositoryTests {
    private func repo() throws -> NotesRepository {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Note.self, configurations: config)
        return NotesRepository(context: ModelContext(container))
    }

    @Test func createAddsNote() throws {
        let r = try repo()
        r.create(text: "hi")
        #expect(r.allSortedByModified().count == 1)
    }
    @Test func sortsByModifiedDescending() throws {
        let r = try repo()
        let older = r.create(text: "old"); older.modified = Date(timeIntervalSince1970: 1)
        let newer = r.create(text: "new"); newer.modified = Date(timeIntervalSince1970: 2)
        #expect(r.allSortedByModified().first?.text == "new")
    }
    @Test func deleteRemoves() throws {
        let r = try repo()
        let n = r.create(text: "x")
        r.delete(n)
        #expect(r.allSortedByModified().isEmpty)
    }
    @Test func upsertInsertsThenUpdatesSameID() throws {
        let r = try repo()
        let id = UUID(); let d = Date(timeIntervalSince1970: 5)
        r.upsert(ExportedNote(id: id, text: "first", created: d, modified: d))
        r.upsert(ExportedNote(id: id, text: "second", created: d, modified: d))
        let all = r.allSortedByModified()
        #expect(all.count == 1)
        #expect(all.first?.text == "second")
    }
}
```

- [ ] **Step 2: Run to verify fail** — FAIL (`cannot find 'NotesRepository'`).

- [ ] **Step 3: Implement**

`NotesRepository.swift`:
```swift
import Foundation
import SwiftData

/// CRUD over the SwiftData store. Small-N notes app: fetches are unfiltered and
/// filtered in memory (avoids predicate edge cases; revisit if datasets grow).
@MainActor
public final class NotesRepository {
    private let context: ModelContext
    public init(context: ModelContext) { self.context = context }

    public func allSortedByModified() -> [Note] {
        let descriptor = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.modified, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    public func create(text: String = "") -> Note {
        let note = Note(text: text)
        context.insert(note)
        return note
    }

    public func delete(_ note: Note) { context.delete(note) }

    public func note(id: UUID) -> Note? {
        allSortedByModified().first { $0.id == id }
    }

    @discardableResult
    public func upsert(_ exported: ExportedNote) -> Note {
        if let existing = note(id: exported.id) {
            existing.text = exported.text
            existing.created = exported.created
            existing.modified = exported.modified
            return existing
        }
        let note = Note(id: exported.id, text: exported.text,
                        created: exported.created, modified: exported.modified)
        context.insert(note)
        return note
    }

    public func save() { try? context.save() }
}
```

> ⚠️ VERIFY: `FetchDescriptor` + `SortDescriptor(\.modified, order: .reverse)` API names against current SwiftData docs.

- [ ] **Step 4: Run to verify pass** — `./scripts/test-core.sh` → PASS (all core suites).

- [ ] **Step 5: Commit**

```bash
git add PopupNotesCore && git commit -m "feat(core): NotesRepository SwiftData CRUD (create/delete/sort/upsert)"
```

---

# PHASE C — App rewire (requires Xcode; build + manual verify)

> GUI/SwiftData-integration tasks can't be unit-tested. Each ends in a **build** and a **manual check**. Code is concrete but `⚠️ VERIFY` flags mark SwiftData/SwiftUI specifics to confirm against current docs (consult **swiftui-expert-skill**). Commit straight to `main`.

### Task 6: Shared `ModelContainer` + migration + first-run defaults

**Files:** Modify `PopupNotes/PopupNotes/AppDelegate.swift`; Modify `PopupNotes/PopupNotes/Support/LaunchAtLogin.swift`

- [ ] **Step 1: Add first-run default to `LaunchAtLogin`**

Append to `LaunchAtLogin` (the existing enum):
```swift
    /// Enables launch-at-login once, on first run only.
    static func applyFirstRunDefaultIfNeeded() {
        let key = "didApplyFirstRunDefaults"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        isEnabled = true
    }
```

- [ ] **Step 2: Rewrite `AppDelegate` to own the container + migration**

```swift
import AppKit
import SwiftData
import PopupNotesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container: ModelContainer
    private let hotKey = HotKeyManager()
    private let panel: PanelController

    override init() {
        let storeURL = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("PopupNotes/Notes.store"))
        let config = storeURL.map { ModelConfiguration(url: $0) } ?? ModelConfiguration()
        // swiftlint:disable:next force_try
        self.container = try! ModelContainer(for: Note.self, configurations: config)
        self.panel = PanelController(container: container)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        migrateLegacyIfNeeded()
        LaunchAtLogin.applyFirstRunDefaultIfNeeded()
        let ok = hotKey.register(.default) { [weak self] in self?.panel.toggle() }
        if !ok { NSLog("PopupNotes: hotkey registration failed; use the menu-bar item.") }
    }

    func applicationWillTerminate(_ notification: Notification) {
        try? container.mainContext.save()
        hotKey.unregister()
    }

    func showScratchpad() { panel.show() }
    func newNote() { panel.showWithNewNote() }

    private func migrateLegacyIfNeeded() {
        let key = "didMigrateLegacyScratchpad"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard let url = LegacyScratchpad.defaultURL(), let text = LegacyScratchpad.read(at: url) else { return }
        let repo = NotesRepository(context: container.mainContext)
        repo.create(text: text)
        repo.save()
    }
}
```

> ⚠️ VERIFY: `ModelConfiguration(url:)` initializer name and `container.mainContext` against current SwiftData docs.

- [ ] **Step 3: Build** — `xcodebuild ... build`. Expected: fails until `PanelController` gains `init(container:)` (Task 7). That's fine — proceed to Task 7, then build.

- [ ] **Step 4: Commit (after Task 7 builds)** — committed together with Task 7.

---

### Task 7: `NotesView` + list + detail; host in `PanelController`

**Files:** Create `PopupNotes/PopupNotes/Views/NotesView.swift`, `NotesListView.swift`, `NoteDetailView.swift`; Modify `PopupNotes/PopupNotes/Panel/PanelController.swift`

- [ ] **Step 1: `NoteDetailView.swift`**

```swift
import SwiftUI
import PopupNotesCore

struct NoteDetailView: View {
    @Bindable var note: Note
    @FocusState private var focused: Bool

    var body: some View {
        TextEditor(text: Binding(
            get: { note.text },
            set: { note.text = $0; note.modified = .now }
        ))
        .font(.body)
        .scrollContentBackground(.hidden)
        .padding(12)
        .focused($focused)
        .onAppear { focused = true }
    }
}
```

- [ ] **Step 2: `NotesListView.swift`**

```swift
import SwiftUI
import SwiftData
import PopupNotesCore

struct NotesListView: View {
    let notes: [Note]
    @Binding var selection: Note.ID?
    var onNew: () -> Void
    var onDelete: (Note) -> Void

    @State private var pendingDelete: Note?

    var body: some View {
        List(selection: $selection) {
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title).lineLimit(1)
                    Text(note.modified, format: .relative(presentation: .named))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .tag(note.id)
                .contextMenu { Button("Delete", role: .destructive) { pendingDelete = note } }
            }
        }
        .toolbar { ToolbarItem { Button(action: onNew) { Image(systemName: "square.and.pencil") } } }
        .confirmationDialog("Delete this note?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { note in
            Button("Delete", role: .destructive) { onDelete(note); pendingDelete = nil }
        }
    }
}
```

> ⚠️ VERIFY: `List(selection:)` + `.tag` selection binding behaves in the panel; `.relative` date format API.

- [ ] **Step 3: `NotesView.swift`**

```swift
import SwiftUI
import SwiftData
import PopupNotesCore

struct NotesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Note.modified, order: .reverse) private var notes: [Note]
    @Binding var selection: Note.ID?

    var body: some View {
        NavigationSplitView {
            NotesListView(notes: notes, selection: $selection, onNew: newNote, onDelete: delete)
                .navigationSplitViewColumnWidth(min: 160, ideal: 220)
        } detail: {
            if let id = selection, let note = notes.first(where: { $0.id == id }) {
                NoteDetailView(note: note).id(note.id)
            } else {
                Text("Select or create a note").foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 560, minHeight: 360)
        .onAppear { if notes.isEmpty { newNote() } else if selection == nil { selection = notes.first?.id } }
    }

    private func newNote() {
        let note = Note()
        context.insert(note)
        selection = note.id
    }

    private func delete(_ note: Note) {
        let wasSelected = selection == note.id
        context.delete(note)
        if wasSelected { selection = nil }
    }
}
```

> ⚠️ VERIFY: `@Query` updates inside the `NSHostingView` panel (spec §12). If the list doesn't refresh on insert/delete, drive it from `NotesRepository.allSortedByModified()` + an `@Observable` view-model instead.

- [ ] **Step 4: Rewrite `PanelController`** to host `NotesView` with the container + persist selection

Replace the body of `PanelController` (keep the panel show/hide/position/monitor logic; swap the hosted view and the store dependency):
```swift
import AppKit
import SwiftUI
import SwiftData
import PopupNotesCore

@MainActor
final class PanelController {
    private let container: ModelContainer
    private var panel: FloatingPanel?
    private var clickMonitor: Any?
    private weak var previousApp: NSRunningApplication?
    private var selection: Note.ID?   // persisted across shows

    init(container: ModelContainer) { self.container = container }

    var isVisible: Bool { panel?.isVisible ?? false }
    func toggle() { isVisible ? hide() : show() }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        previousApp = NSWorkspace.shared.frontmostApplication
        panel.makeKeyAndOrderFront(nil)
        installClickMonitor()
    }

    func showWithNewNote() {
        let note = NotesRepository(context: container.mainContext).create()
        selection = note.id
        rebuildHost()
        show()
    }

    func hide() {
        guard let panel else { return }
        try? container.mainContext.save()
        removeClickMonitor()
        panel.orderOut(nil)
        previousApp?.activate()
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 460))
        panel.setHosted(rootView(), container: container)
        return panel
    }

    private func rebuildHost() { panel?.setHosted(rootView(), container: container) }

    private func rootView() -> some View {
        NotesView(selection: Binding(get: { [weak self] in self?.selection },
                                     set: { [weak self] in self?.selection = $0 }))
    }

    private func installClickMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }
    private func removeClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor); self.clickMonitor = nil }
    }
}
```

And add to `FloatingPanel` a helper that applies `.modelContainer` to the hosted view:
```swift
import SwiftUI
import SwiftData
extension FloatingPanel {
    func setHosted(_ view: some View, container: ModelContainer) {
        let host = NSHostingView(rootView: AnyView(view.modelContainer(container)))
        host.frame = NSRect(origin: .zero, size: frame.size)
        contentView = host
    }
}
```

> ⚠️ VERIFY: caret-at-end on selection change — `@FocusState` focuses the editor, but SwiftUI `TextEditor` may not place the caret at the end. If the manual test shows it wrong, wrap an `NSTextView` (`NSViewRepresentable`) for the detail editor and `setSelectedRange(NSRange(location: text.count, length: 0))` on focus. (Same fallback noted in the original core-flow plan.)

- [ ] **Step 5: Build** — `xcodebuild ... build`. Expected: BUILD SUCCEEDED (Tasks 6+7 together).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(app): SwiftData multi-note master-detail view + container wiring"
```

---

### Task 8: Resizable, frame-remembering panel

**Files:** Modify `PopupNotes/PopupNotes/Panel/FloatingPanel.swift`

- [ ] **Step 1: Add `.resizable` + frame autosave** — in `FloatingPanel.init`, change the style mask and set autosave:
```swift
        super.init(contentRect: contentRect,
                   styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        setFrameAutosaveName("PopupNotesPanel")   // persists size + position
```
Keep the existing `isFloatingPanel`, `level`, `collectionBehavior`, material, `canBecomeKey`, `animationBehavior = .none` lines.

> ⚠️ VERIFY: a `.resizable` panel needs `.titled` to show resize affordances on all edges; hiding the title bar buttons + transparent titlebar keeps it clean. Confirm the panel still becomes key and the `.none` animation still applies. The SwiftUI `NavigationSplitView` persists its own sidebar width automatically; if not, set an explicit `AppStorage` width on the sidebar column.

- [ ] **Step 2: Build + manual check** — resize and move the panel, quit, relaunch → frame restored.

- [ ] **Step 3: Commit**

```bash
git add PopupNotes/PopupNotes/Panel/FloatingPanel.swift && git commit -m "feat(app): resizable panel with remembered frame"
```

---

### Task 9: Settings window (launch-at-login + export/import)

**Files:** Create `PopupNotes/PopupNotes/Settings/SettingsView.swift`; Modify `PopupNotes/PopupNotes/PopupNotesApp.swift`

- [ ] **Step 1: `SettingsView.swift`**

```swift
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PopupNotesCore

struct SettingsView: View {
    let container: ModelContainer
    @State private var message: String?

    var body: some View {
        Form {
            Toggle("Launch at Login", isOn: Binding(
                get: { LaunchAtLogin.isEnabled }, set: { LaunchAtLogin.isEnabled = $0 }))
            Section("Data") {
                HStack {
                    Button("Export Notes…") { export() }
                    Button("Import Notes…") { importNotes() }
                }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .padding()
    }

    private func export() {
        let repo = NotesRepository(context: container.mainContext)
        let exported = repo.allSortedByModified().map(ExportedNote.init)
        guard let data = try? NotesJSON.encode(exported) else { message = "Export failed."; return }
        let p = NSSavePanel()
        p.nameFieldStringValue = "PopupNotes-export.json"
        p.allowedContentTypes = [.json]
        if p.runModal() == .OK, let url = p.url {
            try? data.write(to: url)
            message = "Exported \(exported.count) notes."
        }
    }

    private func importNotes() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.json]
        p.allowsMultipleSelection = false
        guard p.runModal() == .OK, let url = p.url, let data = try? Data(contentsOf: url) else { return }
        guard let incoming = try? NotesJSON.decode(data) else { message = "Import failed: not a valid notes file."; return }
        let repo = NotesRepository(context: container.mainContext)
        incoming.forEach { repo.upsert($0) }
        repo.save()
        message = "Imported \(incoming.count) notes."
    }
}
```

> ⚠️ VERIFY: `NSSavePanel`/`NSOpenPanel` `.runModal()` from a SwiftUI Settings scene works (it's a regular app window context). `UTType.json` import.

- [ ] **Step 2: Add the `Settings` scene + container** in `PopupNotesApp` (Task 10 also edits this file; do both then build).

- [ ] **Step 3: Build + manual check** — ⌘, opens Settings; export writes JSON; import upserts; toggle reflects Login Items.

- [ ] **Step 4: Commit (with Task 10)**

---

### Task 10: Menus + app scene wiring

**Files:** Modify `PopupNotes/PopupNotes/PopupNotesApp.swift`; Modify `PopupNotes/PopupNotes/Views/NotesView.swift` (⌘N) 

- [ ] **Step 1: Rewrite `PopupNotesApp`**

```swift
import SwiftUI

@main
struct PopupNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Popup Notes", systemImage: "note.text") {
            Button("Show Notes") { appDelegate.showScratchpad() }
                .keyboardShortcut("n", modifiers: [.control, .command])
            Button("New Note") { appDelegate.newNote() }
            Divider()
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit Popup Notes") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }

        Settings { SettingsView(container: appDelegate.container) }
    }
}
```

> ⚠️ VERIFY: `SettingsLink` (macOS 14+) opens the `Settings` scene from a `MenuBarExtra`. If unavailable, use `Button("Settings…") { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }` and verify the selector on the current OS.

- [ ] **Step 2: Add the in-popup ⌘N + Settings/Quit to the ⋯ menu.** In `NotesView`, add a hidden command button for ⌘N:
```swift
        .background {
            Button("") { newNote() }.keyboardShortcut("n", modifiers: .command).hidden()
        }
```
And restore the ⋯ overlay menu (replacing the deleted ScratchpadView's) on the detail/top-right with: New Note, Settings… (`SettingsLink`), Quit. *(Reuse the `optionsMenu` pattern from the old ScratchpadView; Launch at Login is now in Settings, not here.)*

- [ ] **Step 3: Build + manual check** — menu bar shows Show Notes/New Note/Settings…/Quit; ⌘N in the panel makes a note; ⋯ menu works.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat(app): Settings scene, export/import, updated menus (⌘N new note)"
```

---

### Task 11: Remove dead single-note code

**Files:** Delete `PopupNotesCore/.../NoteStore.swift`, `NoteFile.swift`, `Debouncing.swift` and their tests; `PopupNotes/.../Views/ScratchpadView.swift`, `Support/NotesFile.swift`

- [ ] **Step 1: Delete the files**

```bash
git rm PopupNotesCore/Sources/PopupNotesCore/NoteStore.swift \
       PopupNotesCore/Sources/PopupNotesCore/NoteFile.swift \
       PopupNotesCore/Sources/PopupNotesCore/Debouncing.swift \
       PopupNotesCore/Tests/PopupNotesCoreTests/NoteStoreTests.swift \
       PopupNotesCore/Tests/PopupNotesCoreTests/NoteFileTests.swift \
       PopupNotesCore/Tests/PopupNotesCoreTests/DebouncerTests.swift \
       PopupNotes/PopupNotes/Views/ScratchpadView.swift \
       PopupNotes/PopupNotes/Support/NotesFile.swift
```

- [ ] **Step 2: Core tests + app build** — `./scripts/test-core.sh` (only the new suites remain, all pass) and `xcodebuild ... build` (BUILD SUCCEEDED — confirms nothing referenced the deleted code).

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "refactor: remove single-note code superseded by SwiftData multi-note"
```

---

### Task 12: Update CLAUDE.md

**Files:** Modify `CLAUDE.md`

- [ ] **Step 1:** Update the "What this app is" / model / tech-stack sections so they describe **multiple notes backed by SwiftData** (not a single text file), note the **Settings window** and **JSON export/import**, and keep the "zero third-party deps" claim (SwiftData is first-party). Reference this spec.

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md && git commit -m "docs: update CLAUDE.md for SwiftData multi-note architecture"
```

---

### Task 13: Manual acceptance test

**Files:** none. Relaunch, then run the spec §11 checklist:

- [ ] ⌃⌘N opens the resizable popup; last-selected note shown, caret at end.
- [ ] `+` / ⌘N creates a note, focuses it; first line updates the sidebar title live.
- [ ] Notes sort most-recently-edited first.
- [ ] Right-click → Delete confirms, then removes.
- [ ] Resize/move + sidebar width persist across quit/relaunch.
- [ ] ⌘, Settings: Launch at Login reflects/sets Login Items and is ON after a clean first run; Export writes JSON; Import upserts; bad file errors without data change.
- [ ] First run with an existing `scratchpad.md` imports it once.
- [ ] Still overlays a full-screen app and shows across Spaces.
- [ ] Fix any failures (focus/caret, `@Query` refresh — see the VERIFY notes), then `git commit`.

---

## Self-Review

**Spec coverage:** §4 storage → Tasks 2,5,6 (Note, repository, container). §4 title → Task 1. §5 UX (split view, new/delete/select, open-last, empty→create) → Task 7. §5 resizable+remembered → Task 8. §6 settings/launch-default/export/import → Tasks 6,9. §6 JSON schema → Task 3. §7 migration → Tasks 4,6. §8 menus → Task 10. §9 components → Tasks 1–11. §10 testing → Tasks 0–5 (+manual). §11 acceptance → Task 13. §12 risks → Task 0 + ⚠️ VERIFY flags. CLAUDE.md update → Task 12. ✓ no gaps.

**Placeholder scan:** No TBD/TODO. `⚠️ VERIFY` are intentional doc-check gates (required by CLAUDE.md), each with a concrete fallback.

**Type consistency:** `NoteTitle.title(from:)` (T1) used in `Note.title` (T2). `ExportedNote(_:Note)` (T2) used in export (T9). `NotesJSON.encode/decode` (T3) used in T9. `LegacyScratchpad.read/defaultURL` (T4) used in T6. `NotesRepository.allSortedByModified/create/delete/note(id:)/upsert/save` (T5) used in T6,7,9. `PanelController.init(container:)/showWithNewNote()` (T7) used in T6. `FloatingPanel.setHosted(_:container:)` (T7) used in T7. `appDelegate.container/showScratchpad()/newNote()` (T6) used in T10. Consistent. ✓
