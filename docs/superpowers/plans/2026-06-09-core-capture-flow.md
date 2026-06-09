# Core Capture Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Press ⌃⌘N from any app to overlay a focused, translucent scratchpad on the mouse's screen; type a note that autosaves to a single file; dismiss with Esc / click-outside / ⌃⌘N again, returning focus to the prior app.

**Architecture:** Two units. (1) `PopupNotesCore` — a SwiftPM library holding all pure logic (`HotKeyCombo` validation + Carbon-flag mapping, `NoteFile` persistence primitives, a `Debouncing` abstraction, and the `@Observable` `NoteStore`). It builds and unit-tests **today on the Command Line Tools** — no Xcode. (2) The `PopupNotes` Xcode app — depends on the package and adds the AppKit/SwiftUI shell (`MenuBarExtra`, `FloatingPanel`, `PanelController`, `ScratchpadView`, `HotKeyManager`, `AppDelegate`). The shell needs Xcode 26.5 to build and run.

**Tech Stack:** Swift 6 (strict concurrency), Swift Testing, Foundation + Observation (core); SwiftUI + AppKit + Carbon `RegisterEventHotKey` (app). Zero third-party dependencies.

---

## Progress

- **2026-06-09 — Phase 0–1 COMPLETE.** `PopupNotesCore` built and green (22 tests) on branch `feat/core-capture-flow`. Tasks 1–5 done: scaffold + CLT-aware test runner, `HotKeyCombo`, `NoteFile`, `Debouncing`, `NoteStore`.
- **Paused at the Phase 1 milestone**, awaiting the Xcode 26.5 install.
- **Resume at Task 6** (create the Xcode app project) once `xcodebuild -version` works. Run the core tests anytime with `./scripts/test-core.sh`.

---

## ⚠️ Environment facts (verified 2026-06-09 by running on this machine)

- **No Xcode installed.** `xcode-select -p` → `/Library/Developer/CommandLineTools`. Swift **6.2.4**; default SDK **MacOSX26.2.sdk**; host macOS **15.7.7**. Disk **~34 GB free** (Xcode needs ~40 GB+ — free space first).
- **`swift build` and `swift test` work on the CLT.** `@Observable` + Foundation compile and run.
- **Swift Testing runs green on the CLT**, *including* Foundation-using tests, but only with a flag incantation: the CLT ships `Testing.framework` off the default search path and ships **no `_Testing_Foundation` swiftmodule**, so we add the framework path and disable cross-import overlays. This is captured in `scripts/test-core.sh` (Task 1) — **always run core tests through that script**, never bare `swift test`, until Xcode is installed.
- **Phase split:** Tasks 1–5 (core) are doable **now**. Tasks 6–12 (app) require Xcode and are gated behind it.

---

## File Structure

```
popup-notes-mac/
├── scripts/
│   └── test-core.sh                         # NEW — swift test wrapper w/ verified CLT flags
├── PopupNotesCore/                          # NEW — SwiftPM package (builds/tests on CLT now)
│   ├── Package.swift
│   ├── Sources/PopupNotesCore/
│   │   ├── HotKeyCombo.swift                # KeyModifiers OptionSet + HotKeyCombo (validation, Carbon flags)
│   │   ├── NoteFile.swift                   # file URL resolution + read/atomic-write/dir-create
│   │   ├── Debouncing.swift                 # Debouncing protocol + Debouncer (real) + ManualDebouncer (test)
│   │   └── NoteStore.swift                  # @Observable: load, updateText, debounced + immediate save, safety
│   └── Tests/PopupNotesCoreTests/
│       ├── HotKeyComboTests.swift
│       ├── NoteFileTests.swift
│       ├── DebouncerTests.swift
│       └── NoteStoreTests.swift
├── PopupNotes.xcodeproj                     # NEW (Task 6, in Xcode) — depends on PopupNotesCore
└── PopupNotes/                              # NEW (Tasks 6–11) — app shell
    ├── PopupNotesApp.swift                  # @main App; MenuBarExtra; NSApplicationDelegateAdaptor
    ├── AppDelegate.swift                    # .accessory policy; wires store/hotkey/panel; flush on quit
    ├── HotKey/HotKeyManager.swift           # Carbon RegisterEventHotKey wrapper (uses HotKeyCombo)
    ├── Panel/FloatingPanel.swift            # NSPanel subclass: non-activating, floating, all-Spaces
    ├── Panel/PanelController.swift          # lifecycle: build/host/position/show/hide/monitor/Esc/focus
    ├── Views/ScratchpadView.swift           # SwiftUI TextEditor bound to NoteStore
    └── Info.plist                           # LSUIElement = true
```

**Boundary rule:** `PopupNotesCore` must not import AppKit, SwiftUI, or Carbon. It depends only on Foundation + Observation. Anything needing those frameworks lives in the app target. This is what keeps the core testable without Xcode.

---

# PHASE 0 — Core package scaffold (do now)

### Task 1: Create the SwiftPM package and the test runner

**Files:**
- Create: `PopupNotesCore/Package.swift`
- Create: `PopupNotesCore/Sources/PopupNotesCore/Placeholder.swift` (temporary, deleted in Task 2)
- Create: `PopupNotesCore/Tests/PopupNotesCoreTests/SmokeTests.swift`
- Create: `scripts/test-core.sh`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PopupNotesCore",
    platforms: [.macOS(.v14)], // Observation requires macOS 14+; app deploys to macOS 15.
    products: [
        .library(name: "PopupNotesCore", targets: ["PopupNotesCore"]),
    ],
    targets: [
        .target(name: "PopupNotesCore"),
        .testTarget(name: "PopupNotesCoreTests", dependencies: ["PopupNotesCore"]),
    ]
)
```

- [ ] **Step 2: Write a temporary placeholder source** (so the target compiles before Task 2)

`PopupNotesCore/Sources/PopupNotesCore/Placeholder.swift`:
```swift
// Temporary so the empty target compiles. Deleted in Task 2.
enum Placeholder {}
```

- [ ] **Step 3: Write a smoke test**

`PopupNotesCore/Tests/PopupNotesCoreTests/SmokeTests.swift`:
```swift
import Testing
import Foundation
@testable import PopupNotesCore

@Test func packageBuildsAndTestsRun() {
    #expect(Bool(true))
}
```

- [ ] **Step 4: Write `scripts/test-core.sh`** (the verified CLT-aware wrapper)

```bash
#!/usr/bin/env bash
# Runs the PopupNotesCore tests. On Command Line Tools, Swift Testing's
# Testing.framework is present but off the default search path, and the
# _Testing_Foundation cross-import overlay ships no swiftmodule — so we add
# the framework path and disable cross-import overlays. Under a full Xcode
# toolchain, Swift Testing resolves normally and no extra flags are needed.
set -euo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/PopupNotesCore"
DEVDIR="$(xcode-select -p)"
FWK="$DEVDIR/Library/Developer/Frameworks"

if [[ "$DEVDIR" == *CommandLineTools* && -d "$FWK/Testing.framework" ]]; then
  echo "Command Line Tools detected — using Swift Testing workaround flags."
  exec swift test --package-path "$PKG_DIR" \
    -Xswiftc -F -Xswiftc "$FWK" \
    -Xlinker -F -Xlinker "$FWK" \
    -Xlinker -rpath -Xlinker "$FWK" \
    -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
    "$@"
else
  echo "Full Xcode toolchain detected — running swift test normally."
  exec swift test --package-path "$PKG_DIR" "$@"
fi
```

- [ ] **Step 5: Make it executable and run it**

Run:
```bash
chmod +x scripts/test-core.sh && ./scripts/test-core.sh
```
Expected: build succeeds; output ends with `✔ Test run with 1 test in 0 suites passed`.

- [ ] **Step 6: Commit**

```bash
git add PopupNotesCore scripts/test-core.sh
git commit -m "chore: scaffold PopupNotesCore package + CLT-aware test runner"
```

---

# PHASE 1 — Core logic, TDD (do now; runs on CLT)

### Task 2: `HotKeyCombo` — modifiers, validation, Carbon flags

**Files:**
- Create: `PopupNotesCore/Sources/PopupNotesCore/HotKeyCombo.swift`
- Delete: `PopupNotesCore/Sources/PopupNotesCore/Placeholder.swift`
- Test: `PopupNotesCore/Tests/PopupNotesCoreTests/HotKeyComboTests.swift`

- [ ] **Step 1: Write the failing tests**

`HotKeyComboTests.swift`:
```swift
import Testing
@testable import PopupNotesCore

@Suite struct HotKeyComboTests {
    @Test func defaultIsControlCommandN() {
        let combo = HotKeyCombo.default
        #expect(combo.keyCode == 45)                 // kVK_ANSI_N
        #expect(combo.modifiers == [.control, .command])
        #expect(combo.isValidGlobalHotKey)
    }

    @Test func carbonModifierFlagsAreBitwiseOr() {
        let combo = HotKeyCombo(keyCode: 45, modifiers: [.control, .command])
        #expect(combo.carbonModifierFlags == 0x1000 | 0x0100) // controlKey | cmdKey
    }

    @Test func optionOnlyIsInvalid() {
        #expect(!HotKeyCombo(keyCode: 45, modifiers: [.option]).isValidGlobalHotKey)
    }

    @Test func optionShiftIsInvalid() {
        #expect(!HotKeyCombo(keyCode: 45, modifiers: [.option, .shift]).isValidGlobalHotKey)
    }

    @Test func noModifiersIsInvalid() {
        #expect(!HotKeyCombo(keyCode: 45, modifiers: []).isValidGlobalHotKey)
    }

    @Test func commandShiftIsValid() {
        #expect(HotKeyCombo(keyCode: 45, modifiers: [.command, .shift]).isValidGlobalHotKey)
    }

    @Test func controlOptionIsValid() {
        #expect(HotKeyCombo(keyCode: 45, modifiers: [.control, .option]).isValidGlobalHotKey)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./scripts/test-core.sh`
Expected: FAIL — `cannot find 'HotKeyCombo' in scope`.

- [ ] **Step 3: Write the implementation, delete the placeholder**

Delete `Placeholder.swift`. Create `HotKeyCombo.swift`:
```swift
/// A keyboard-shortcut definition, independent of Carbon.
///
/// `KeyModifiers` raw values intentionally mirror Carbon's HIToolbox modifier
/// masks (`cmdKey`, `shiftKey`, `optionKey`, `controlKey` from
/// <Carbon/HIToolbox/Events.h>) so `carbonModifierFlags` is a no-op cast.
/// ⚠️ VERIFY these equal the real Carbon constants — Task 7 adds an app-side
/// assertion (`assert(KeyModifiers.command.rawValue == UInt32(cmdKey))`, etc.).
public struct KeyModifiers: OptionSet, Sendable, Equatable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let command = KeyModifiers(rawValue: 0x0100) // cmdKey
    public static let shift   = KeyModifiers(rawValue: 0x0200) // shiftKey
    public static let option  = KeyModifiers(rawValue: 0x0800) // optionKey
    public static let control = KeyModifiers(rawValue: 0x1000) // controlKey
}

public struct HotKeyCombo: Sendable, Equatable {
    /// Virtual key code (Carbon `kVK_*`); 45 == `kVK_ANSI_N`.
    public var keyCode: UInt32
    public var modifiers: KeyModifiers

    public init(keyCode: UInt32, modifiers: KeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// The default shortcut: ⌃⌘N.
    public static let `default` = HotKeyCombo(keyCode: 45, modifiers: [.control, .command])

    /// Carbon modifier bitmask for `RegisterEventHotKey`.
    public var carbonModifierFlags: UInt32 { modifiers.rawValue }

    /// A safe global hotkey must include Command and/or Control. This rejects
    /// the empty, Shift-only, Option-only, and Option+Shift combos — the last
    /// two are documented broken with `RegisterEventHotKey` on macOS 15+.
    public var isValidGlobalHotKey: Bool {
        !modifiers.isDisjoint(with: [.command, .control])
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./scripts/test-core.sh`
Expected: PASS — all 7 `HotKeyComboTests` plus the smoke test.

- [ ] **Step 5: Commit**

```bash
git add PopupNotesCore
git commit -m "feat(core): HotKeyCombo with validation and Carbon-flag mapping"
```

---

### Task 3: `NoteFile` — persistence primitives

**Files:**
- Create: `PopupNotesCore/Sources/PopupNotesCore/NoteFile.swift`
- Test: `PopupNotesCore/Tests/PopupNotesCoreTests/NoteFileTests.swift`

- [ ] **Step 1: Write the failing tests**

`NoteFileTests.swift`:
```swift
import Testing
import Foundation
@testable import PopupNotesCore

@Suite struct NoteFileTests {
    /// A unique temp file URL inside a fresh directory we control.
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("popupnotes-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("scratchpad.md", isDirectory: false)
    }

    @Test func writeThenReadRoundTrips() throws {
        let file = NoteFile(url: tempFileURL())
        try file.write("hello 🌍\nsecond line")
        #expect(try file.read() == "hello 🌍\nsecond line")
        try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent())
    }

    @Test func writeCreatesIntermediateDirectories() throws {
        let file = NoteFile(url: tempFileURL())
        #expect(!file.exists)
        try file.write("x")
        #expect(file.exists)
        try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent())
    }

    @Test func readMissingFileThrows() {
        let file = NoteFile(url: tempFileURL())
        #expect(throws: (any Error).self) { try file.read() }
    }

    @Test func writeOverwritesExistingContent() throws {
        let file = NoteFile(url: tempFileURL())
        try file.write("first")
        try file.write("second")
        #expect(try file.read() == "second")
        try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent())
    }

    @Test func defaultFileIsUnderApplicationSupport() throws {
        let file = try NoteFile.defaultFile()
        #expect(file.url.lastPathComponent == "scratchpad.md")
        #expect(file.url.deletingLastPathComponent().lastPathComponent == "PopupNotes")
        #expect(file.url.path.contains("Application Support"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./scripts/test-core.sh`
Expected: FAIL — `cannot find 'NoteFile' in scope`.

- [ ] **Step 3: Write the implementation**

`NoteFile.swift`:
```swift
import Foundation

/// Reads and writes the single scratchpad file. Pure Foundation — no app deps.
public struct NoteFile: Sendable, Equatable {
    public let url: URL
    public init(url: URL) { self.url = url }

    /// `~/Library/Application Support/PopupNotes/scratchpad.md`.
    public static func defaultFile(fileManager: FileManager = .default) throws -> NoteFile {
        let base = try fileManager.url(for: .applicationSupportDirectory,
                                       in: .userDomainMask,
                                       appropriateFor: nil,
                                       create: true)
        let dir = base.appendingPathComponent("PopupNotes", isDirectory: true)
        return NoteFile(url: dir.appendingPathComponent("scratchpad.md", isDirectory: false))
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func read() throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// Atomic write: Foundation writes to a temp file and renames, so a crash
    /// mid-write cannot corrupt the note. Creates the parent directory first.
    public func write(_ text: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./scripts/test-core.sh`
Expected: PASS — all 5 `NoteFileTests`.

- [ ] **Step 5: Commit**

```bash
git add PopupNotesCore
git commit -m "feat(core): NoteFile read/atomic-write with default Application Support path"
```

---

### Task 4: `Debouncing` — protocol, manual test double, real debouncer

**Files:**
- Create: `PopupNotesCore/Sources/PopupNotesCore/Debouncing.swift`
- Test: `PopupNotesCore/Tests/PopupNotesCoreTests/DebouncerTests.swift`

- [ ] **Step 1: Write the failing tests**

`DebouncerTests.swift`:
```swift
import Testing
import Foundation
@testable import PopupNotesCore

@Suite @MainActor struct DebouncerTests {
    @Test func manualDebouncerKeepsOnlyLatestAndFiresOnDemand() {
        let d = ManualDebouncer()
        var fired: [Int] = []
        d.schedule { fired.append(1) }
        d.schedule { fired.append(2) } // replaces the first
        #expect(fired.isEmpty)         // nothing fires until we say so
        d.fireNow()
        #expect(fired == [2])
    }

    @Test func manualDebouncerCancelDropsPendingAction() {
        let d = ManualDebouncer()
        var fired = false
        d.schedule { fired = true }
        d.cancel()
        d.fireNow()
        #expect(!fired)
    }

    @Test func realDebouncerFiresOnceAfterInterval() async {
        let d = Debouncer(interval: .milliseconds(20))
        await confirmation("fires exactly once") { fulfilled in
            d.schedule { fulfilled() }
            d.schedule { fulfilled() } // coalesced into one
            try? await Task.sleep(for: .milliseconds(120))
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./scripts/test-core.sh`
Expected: FAIL — `cannot find 'ManualDebouncer'` / `'Debouncer'` in scope.

- [ ] **Step 3: Write the implementation**

`Debouncing.swift`:
```swift
import Foundation

/// Coalesces rapid calls into a single deferred action. `@MainActor` because
/// the fired action mutates `NoteStore` and touches the file system from the
/// store's isolation domain.
@MainActor
public protocol Debouncing {
    func schedule(_ action: @escaping @MainActor () -> Void)
    func cancel()
}

/// Production debouncer backed by a cancellable `Task` sleep.
@MainActor
public final class Debouncer: Debouncing {
    private let interval: Duration
    private var task: Task<Void, Never>?

    public init(interval: Duration) { self.interval = interval }

    public func schedule(_ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { [interval] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }
}

/// Test double: stores the latest scheduled action and fires it only when
/// `fireNow()` is called, making `NoteStore` save timing deterministic.
@MainActor
public final class ManualDebouncer: Debouncing {
    private var pending: (@MainActor () -> Void)?
    public init() {}

    public func schedule(_ action: @escaping @MainActor () -> Void) { pending = action }
    public func cancel() { pending = nil }

    public func fireNow() {
        let action = pending
        pending = nil
        action?()
    }
}
```

> ⚠️ VERIFY (strict concurrency): `Task { ... action() }` created in a `@MainActor`
> method runs `action` (a `@MainActor` closure) on the main actor — this should
> compile clean under Swift 6. If the compiler flags isolation, wrap as
> `Task { @MainActor in ... }`. Consult the **swift-concurrency** skill.

- [ ] **Step 4: Run tests to verify they pass**

Run: `./scripts/test-core.sh`
Expected: PASS — all 3 `DebouncerTests`. (The async one waits ~120 ms.)

- [ ] **Step 5: Commit**

```bash
git add PopupNotesCore
git commit -m "feat(core): Debouncing protocol with real and manual debouncers"
```

---

### Task 5: `NoteStore` — the observable brain

**Files:**
- Create: `PopupNotesCore/Sources/PopupNotesCore/NoteStore.swift`
- Test: `PopupNotesCore/Tests/PopupNotesCoreTests/NoteStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

`NoteStoreTests.swift`:
```swift
import Testing
import Foundation
@testable import PopupNotesCore

@Suite @MainActor struct NoteStoreTests {
    private func freshFile() -> NoteFile {
        NoteFile(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("popupnotes-store-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("scratchpad.md", isDirectory: false))
    }

    @Test func loadsEmptyWhenFileMissing() {
        let store = NoteStore(file: freshFile(), autosave: ManualDebouncer())
        #expect(store.text == "")
    }

    @Test func loadsExistingFileContents() throws {
        let file = freshFile()
        try file.write("existing note")
        let store = NoteStore(file: file, autosave: ManualDebouncer())
        #expect(store.text == "existing note")
    }

    @Test func updateTextSchedulesDebouncedSave() throws {
        let file = freshFile()
        let debouncer = ManualDebouncer()
        let store = NoteStore(file: file, autosave: debouncer)
        store.updateText("typed")
        #expect(!file.exists)        // not written until the debounce fires
        debouncer.fireNow()
        #expect(try file.read() == "typed")
    }

    @Test func rapidUpdatesCoalesceToLatestValue() throws {
        let file = freshFile()
        let debouncer = ManualDebouncer()
        let store = NoteStore(file: file, autosave: debouncer)
        store.updateText("a")
        store.updateText("ab")
        store.updateText("abc")
        debouncer.fireNow()
        #expect(try file.read() == "abc")
    }

    @Test func flushSavesImmediately() throws {
        let file = freshFile()
        let store = NoteStore(file: file, autosave: ManualDebouncer())
        store.updateText("note")
        store.flush()
        #expect(try file.read() == "note")
    }

    @Test func doesNotOverwriteUnreadableFileUntilEdited() throws {
        // Simulate an unreadable existing file by putting a *directory* at the
        // note's path, so read() throws.
        let file = freshFile()
        try FileManager.default.createDirectory(at: file.url, withIntermediateDirectories: true)
        let store = NoteStore(file: file, autosave: ManualDebouncer())
        #expect(store.text == "")            // started empty, load failed
        store.flush()                        // must NOT attempt to overwrite
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: file.url.path, isDirectory: &isDir))
        #expect(isDir.boolValue)             // still the original directory, untouched
        try? FileManager.default.removeItem(at: file.url)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./scripts/test-core.sh`
Expected: FAIL — `cannot find 'NoteStore' in scope`.

- [ ] **Step 3: Write the implementation**

`NoteStore.swift`:
```swift
import Foundation
import Observation

/// The single source of truth for the scratchpad text. Loads at init, persists
/// via a debounced autosave plus an immediate `flush()` on hide/quit. In-memory
/// `text` is authoritative; failed saves are retried on the next change/flush.
@MainActor
@Observable
public final class NoteStore {
    public private(set) var text: String = ""

    @ObservationIgnored private let file: NoteFile
    @ObservationIgnored private let autosave: any Debouncing
    /// False only when an existing file failed to read — we then refuse to
    /// overwrite it until the user actually edits (takes ownership).
    @ObservationIgnored private var safeToWrite = true

    public init(file: NoteFile, autosave: any Debouncing) {
        self.file = file
        self.autosave = autosave
        load()
    }

    private func load() {
        guard file.exists else { text = ""; safeToWrite = true; return }
        do {
            text = try file.read()
            safeToWrite = true
        } catch {
            text = ""
            safeToWrite = false   // do not clobber an unreadable file
        }
    }

    /// Called from the SwiftUI editor binding on every keystroke.
    public func updateText(_ newValue: String) {
        text = newValue
        safeToWrite = true        // user edit = they own the content now
        autosave.schedule { [weak self] in self?.flush() }
    }

    /// Persist immediately (on hide and on quit). Keeps in-memory text on failure.
    public func flush() {
        guard safeToWrite else { return }
        do { try file.write(text) }
        catch { /* retried on next change/flush; in-memory text is the source of truth */ }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./scripts/test-core.sh`
Expected: PASS — all 6 `NoteStoreTests`.

- [ ] **Step 5: Commit**

```bash
git add PopupNotesCore
git commit -m "feat(core): NoteStore with debounced autosave and unreadable-file safety"
```

> **Phase 1 done.** The entire core builds and is green on the Command Line
> Tools. Stop here until Xcode 26.5 is installed before starting Phase 2.

---

# PHASE 2 — App shell (requires Xcode 26.5)

> These tasks cannot be unit-tested (AppKit/SwiftUI/Carbon GUI) and cannot be
> built without Xcode. Each ends in a **build** and a **manual verification**
> step. Code is given in full, but per CLAUDE.md, **verify any AppKit/SwiftUI/
> Carbon API against current Apple docs before relying on it** — `⚠️ VERIFY`
> callouts mark the highest-risk spots. Invoke the **swiftui-expert-skill**,
> **swift-concurrency**, and **macos-design-guidelines** skills as you go.

### Task 6: Create the Xcode app project and link the core package

**Files:**
- Create (via Xcode UI): `PopupNotes.xcodeproj`, `PopupNotes/PopupNotesApp.swift` (replaced in Task 11), `PopupNotes/Info.plist`

- [ ] **Step 1: Confirm Xcode is active**

Run:
```bash
xcode-select -p && xcodebuild -version
```
Expected: a path under `/Applications/Xcode*.app/...` and `Xcode 26.x`. If it still shows `CommandLineTools`, run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` and `sudo xcodebuild -license accept`.

- [ ] **Step 2: Create the project in Xcode**

In Xcode: File ▸ New ▸ Project ▸ macOS ▸ **App**. Product Name `PopupNotes`; Interface **SwiftUI**; Language **Swift**. Save it at the repo root so `PopupNotes.xcodeproj` and `PopupNotes/` sit beside `PopupNotesCore/`.

- [ ] **Step 3: Set the Swift language version and deployment target**

Target ▸ Build Settings: **Swift Language Version = Swift 6**; **macOS Deployment Target = 15.0**.

- [ ] **Step 4: Make it a menu-bar accessory (no Dock icon)**

Target ▸ Info: add **Application is agent (UIElement)** = **YES** (this writes `LSUIElement` to `Info.plist`). Confirm `PopupNotes/Info.plist` contains:
```xml
<key>LSUIElement</key>
<true/>
```

- [ ] **Step 5: Add the local package dependency**

File ▸ Add Package Dependencies ▸ Add Local… ▸ select the `PopupNotesCore/` folder. Then Target ▸ General ▸ Frameworks, Libraries, and Embedded Content ▸ **+** ▸ add the `PopupNotesCore` library.

- [ ] **Step 6: Verify it builds**

Run:
```bash
xcodebuild -scheme PopupNotes -configuration Debug build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git add PopupNotes PopupNotes.xcodeproj
git commit -m "chore: create PopupNotes Xcode app linking PopupNotesCore"
```

---

### Task 7: `HotKeyManager` — Carbon global hotkey

**Files:**
- Create: `PopupNotes/HotKey/HotKeyManager.swift`

- [ ] **Step 1: Write the implementation**

`HotKeyManager.swift`:
```swift
import AppKit
import Carbon.HIToolbox
import PopupNotesCore

/// Wraps Carbon `RegisterEventHotKey`. The C event callback cannot capture
/// Swift context, so we pass `self` via an `Unmanaged` pointer and hop back to
/// the main actor to invoke the stored closure.
@MainActor
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onFire: (() -> Void)?

    /// Returns false if the combo is invalid or registration fails.
    @discardableResult
    func register(_ combo: HotKeyCombo, onFire: @escaping () -> Void) -> Bool {
        guard combo.isValidGlobalHotKey else { return false }
        // ⚠️ VERIFY: these mirrored constants equal Carbon's real values.
        assert(KeyModifiers.command.rawValue == UInt32(cmdKey))
        assert(KeyModifiers.control.rawValue == UInt32(controlKey))
        assert(KeyModifiers.option.rawValue  == UInt32(optionKey))
        assert(KeyModifiers.shift.rawValue   == UInt32(shiftKey))

        self.onFire = onFire

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData -> OSStatus in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { manager.fire() } }
            return noErr
        }
        let status = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec,
                                         Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        guard status == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: OSType(0x504E4F54), id: 1) // 'PNOT'
        let regStatus = RegisterEventHotKey(combo.keyCode, combo.carbonModifierFlags,
                                            hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        return regStatus == noErr
    }

    private func fire() { onFire?() }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef); self.hotKeyRef = nil }
        if let handlerRef { RemoveEventHandler(handlerRef); self.handlerRef = nil }
    }
}
```

> ⚠️ VERIFY: the `EventHandlerUPP` callback must be a non-capturing closure for
> the C-function-pointer conversion. The `MainActor.assumeIsolated` hop inside
> `DispatchQueue.main.async` is the strict-concurrency-safe pattern — confirm it
> compiles and consult **swift-concurrency** if it warns.

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme PopupNotes -configuration Debug build`
Expected: `BUILD SUCCEEDED`. (Functional verification happens in Task 11 once it's wired up.)

- [ ] **Step 3: Commit**

```bash
git add PopupNotes/HotKey/HotKeyManager.swift
git commit -m "feat(app): Carbon HotKeyManager wrapping RegisterEventHotKey"
```

---

### Task 8: `FloatingPanel` — the non-activating overlay window

**Files:**
- Create: `PopupNotes/Panel/FloatingPanel.swift`

- [ ] **Step 1: Write the implementation**

`FloatingPanel.swift`:
```swift
import AppKit

/// A borderless, non-activating panel that floats above other apps (including
/// full-screen) on every Space, yet can become key so the editor receives keys.
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear            // SwiftUI provides the material
        hasShadow = true
        isMovableByWindowBackground = false // fixed position per spec
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }   // required for text entry
    override var canBecomeMain: Bool { false } // never the app's main window
}
```

> ⚠️ VERIFY: `.nonactivatingPanel` + `canBecomeKey == true` is the documented
> way to type into a panel without activating the app. Confirm against current
> `NSPanel` / `NSWindow.StyleMask` docs and test on hardware (Task 12).

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme PopupNotes -configuration Debug build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add PopupNotes/Panel/FloatingPanel.swift
git commit -m "feat(app): FloatingPanel non-activating overlay window"
```

---

### Task 9: `ScratchpadView` — the SwiftUI editor

**Files:**
- Create: `PopupNotes/Views/ScratchpadView.swift`

- [ ] **Step 1: Write the implementation**

`ScratchpadView.swift`:
```swift
import SwiftUI
import PopupNotesCore

/// The chromeless editor: a TextEditor bound to NoteStore, a placeholder when
/// empty, material background, and Esc-to-dismiss.
struct ScratchpadView: View {
    @Bindable var store: NoteStore
    var onDismiss: () -> Void

    @FocusState private var editorFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: Binding(
                get: { store.text },
                set: { store.updateText($0) }
            ))
            .font(.body)
            .scrollContentBackground(.hidden)   // let the material show through
            .padding(12)
            .focused($editorFocused)

            if store.text.isEmpty {
                Text("Jot a note…")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 17)
                    .padding(.vertical, 20)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 480, height: 320)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear { editorFocused = true }
        .onExitCommand { onDismiss() }          // Esc
    }
}
```

> ⚠️ VERIFY (cursor-at-end): SwiftUI `TextEditor` exposes no caret API, so
> `@FocusState` focuses it but may not place the caret at the end. If the manual
> test (Task 12) shows the caret in the wrong place, replace `TextEditor` with a
> small `NSViewRepresentable` wrapping `NSTextView` and set
> `setSelectedRange(NSRange(location: text.count, length: 0))` on focus. Consult
> **swiftui-expert-skill**.

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme PopupNotes -configuration Debug build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add PopupNotes/Views/ScratchpadView.swift
git commit -m "feat(app): ScratchpadView chromeless TextEditor with placeholder and Esc"
```

---

### Task 10: `PanelController` — lifecycle, positioning, dismissal, focus

**Files:**
- Create: `PopupNotes/Panel/PanelController.swift`

- [ ] **Step 1: Write the implementation**

`PanelController.swift`:
```swift
import AppKit
import SwiftUI
import PopupNotesCore

/// Owns the panel: builds it lazily, hosts ScratchpadView, positions it centered
/// on the mouse's screen, toggles show/hide, watches for click-outside, and
/// hands focus back to the previous app on dismiss.
@MainActor
final class PanelController {
    private let store: NoteStore
    private var panel: FloatingPanel?
    private var clickMonitor: Any?
    private weak var previousApp: NSRunningApplication?

    private static let panelSize = NSSize(width: 480, height: 320)

    init(store: NoteStore) { self.store = store }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel

        previousApp = NSWorkspace.shared.frontmostApplication
        positionCenteredOnMouseScreen(panel)
        panel.makeKeyAndOrderFront(nil)
        installClickMonitor()
    }

    func hide() {
        guard let panel else { return }
        store.flush()
        removeClickMonitor()
        panel.orderOut(nil)
        // ⚠️ VERIFY: returning focus to the prior app. A non-activating panel
        // often returns focus automatically on orderOut; if not, reactivate:
        previousApp?.activate()
    }

    // MARK: - Build

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize))
        let host = NSHostingView(rootView: ScratchpadView(store: store) { [weak self] in
            self?.hide()
        })
        host.frame = NSRect(origin: .zero, size: Self.panelSize)
        panel.contentView = host
        return panel
    }

    // MARK: - Positioning

    private func positionCenteredOnMouseScreen(_ panel: FloatingPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let origin = NSPoint(
            x: visible.midX - Self.panelSize.width / 2,
            y: visible.midY - Self.panelSize.height / 2
        )
        panel.setFrame(NSRect(origin: origin, size: Self.panelSize), display: true)
    }

    // MARK: - Click-outside dismissal

    private func installClickMonitor() {
        // Global monitor fires for clicks in OTHER apps (i.e., outside our panel).
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    private func removeClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor); self.clickMonitor = nil }
    }
}
```

> ⚠️ VERIFY (focus handoff — highest-risk item in the spec): the
> `makeKeyAndOrderFront` → type → `orderOut` → `previousApp?.activate()` sequence
> is the fiddly part. Test on hardware (Task 12). If keystrokes don't reach the
> editor, or focus doesn't return cleanly, revisit the activation sequence
> against current `NSPanel`/`NSApplication` docs and the **macos-design-guidelines**
> skill before trying random combinations.

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme PopupNotes -configuration Debug build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add PopupNotes/Panel/PanelController.swift
git commit -m "feat(app): PanelController lifecycle, positioning, click-outside, focus return"
```

---

### Task 11: `AppDelegate` + `PopupNotesApp` — wire it together

**Files:**
- Create: `PopupNotes/AppDelegate.swift`
- Modify: `PopupNotes/PopupNotesApp.swift` (replace the Xcode template)

- [ ] **Step 1: Write `AppDelegate.swift`**

```swift
import AppKit
import PopupNotesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: NoteStore
    private let hotKey = HotKeyManager()
    private let panel: PanelController

    override init() {
        // ⚠️ VERIFY: 0.6 s debounce matches the spec; tune if needed.
        let file = (try? NoteFile.defaultFile()) ?? NoteFile(
            url: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("PopupNotes-scratchpad.md"))
        self.store = NoteStore(file: file, autosave: Debouncer(interval: .milliseconds(600)))
        self.panel = PanelController(store: store)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon
        let ok = hotKey.register(.default) { [weak self] in self?.panel.toggle() }
        if !ok {
            NSLog("PopupNotes: hotkey registration failed; use the menu-bar item.")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flush()
        hotKey.unregister()
    }

    /// Called by the menu-bar "Show Scratchpad" item.
    func showScratchpad() { panel.show() }
}
```

- [ ] **Step 2: Replace `PopupNotesApp.swift`**

```swift
import SwiftUI

@main
struct PopupNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Popup Notes", systemImage: "note.text") {
            Button("Show Scratchpad") { appDelegate.showScratchpad() }
                .keyboardShortcut("n", modifiers: [.control, .command])
            Divider()
            Button("Quit Popup Notes") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
```

> ⚠️ VERIFY: accessing `appDelegate` (the adaptor instance) inside the
> `MenuBarExtra` closure is supported. If SwiftUI complains about main-actor
> isolation on `appDelegate.showScratchpad()`, the closure already runs on the
> main actor — confirm and consult **swiftui-expert-skill**.

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme PopupNotes -configuration Debug build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Run and smoke-check**

Run the app from Xcode (⌘R). Expected: a menu-bar `note.text` icon appears, no Dock icon. (Full behavior verification is Task 12.)

- [ ] **Step 5: Commit**

```bash
git add PopupNotes/AppDelegate.swift PopupNotes/PopupNotesApp.swift
git commit -m "feat(app): wire store, hotkey, panel, and minimal MenuBarExtra"
```

---

### Task 12: Manual acceptance test (on hardware)

**Files:** none (verification only).

- [ ] **Step 1: Run through the acceptance checklist** (from the spec §11)

Launch the app, then verify each:
1. From another app, press ⌃⌘N → panel appears **centered on the mouse's screen**, editor focused, caret at end.
2. Type, press **Esc** → panel hides, focus returns to the prior app, text persists.
3. Press ⌃⌘N again → prior text present, caret at end.
4. **Click outside** the panel → it dismisses and saves.
5. Press ⌃⌘N while open → it **hides** (toggle).
6. Works over a **full-screen** app and on a **secondary Space**.
7. Menu bar shows the icon; **Show Scratchpad** opens the panel; **Quit** exits.
8. Quit via the menu, relaunch → text **persisted** (`~/Library/Application Support/PopupNotes/scratchpad.md`).
9. Force-kill mid-edit (`killall PopupNotes`) → file not corrupted; at most the last ≤0.6 s of typing lost.

- [ ] **Step 2: Fix any failures**

For focus/caret/overlay issues, return to the `⚠️ VERIFY` callouts in Tasks 8–11 and the spec §9; verify against current docs and the relevant skill before changing code. Re-run the checklist after each fix.

- [ ] **Step 3: Commit any fixes and finish the branch**

```bash
git add -A
git commit -m "fix(app): focus/overlay adjustments from hardware testing"
```
Then use the **superpowers:finishing-a-development-branch** skill to decide merge/PR.

---

## Self-Review

**Spec coverage** (against `2026-06-09-core-capture-flow-design.md`):
- §3 position centered on mouse screen → Task 10 `positionCenteredOnMouseScreen`. ✓
- §3 fixed 480×320 → Tasks 9, 10. ✓
- §3 minimal menu bar (icon/Show/Quit) → Task 11. ✓
- §3 cursor-at-end → Task 9 (`onAppear` focus) + ⚠️ VERIFY fallback. ✓
- §3 chromeless + placeholder → Task 9. ✓
- §3 dismiss triggers (Esc/click-outside/⌃⌘N) → Tasks 9 (Esc), 10 (click-outside), 11 (toggle). ✓
- §4 capture loop → Tasks 10, 11. ✓
- §6 panel style/collectionBehavior → Task 8. ✓
- §8 persistence (atomic, debounce, save-on-hide/quit, unreadable-file safety) → Tasks 3, 4, 5, 10 (hide flush), 11 (terminate flush). ✓
- §9 focus handoff + Carbon callback concurrency → Tasks 7, 10 with ⚠️ VERIFY gates. ✓
- §10 Swift Testing on CLT → Task 1 runner + Tasks 2–5. ✓
- §11 acceptance criteria → Task 12. ✓
- §1 hotkey validation (reject Option-only/Option+Shift) → Task 2. ✓

**Placeholder scan:** No "TBD/TODO/implement later". `⚠️ VERIFY` callouts are deliberate doc-verification gates (required by CLAUDE.md), each with a concrete fallback — not blanks.

**Type consistency:** `HotKeyCombo`/`KeyModifiers`/`carbonModifierFlags`/`isValidGlobalHotKey` (Task 2) used identically in Task 7. `NoteFile.read/write/exists/defaultFile` (Task 3) used in Tasks 5, 11. `Debouncing.schedule/cancel`, `Debouncer(interval:)`, `ManualDebouncer.fireNow` (Task 4) used in Tasks 5, 11. `NoteStore.text/updateText/flush` (Task 5) used in Tasks 9, 10, 11. `PanelController.toggle/show/hide` (Task 10) used in Task 11. Consistent. ✓
