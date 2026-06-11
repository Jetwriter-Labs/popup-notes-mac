# First-Run Onboarding Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the launch-moment consent `NSAlert` with in-product onboarding: auto-show the panel once with a seeded Welcome note, plus a self-retiring bottom strip carrying the hotkey hint and inline launch-at-login consent.

**Architecture:** A pure `WelcomeNote` text generator joins `PopupNotesCore` (TDD'd). In the app, a new `OnboardingDefaults` enum centralizes the one-time `UserDefaults` flags, a new `OnboardingStripView` renders the two self-retiring rows from those flags via `@AppStorage`, `NotesView` pins the strip to the panel's bottom edge, and `AppDelegate` orchestrates first-launch seeding + auto-show and records hotkey-registration status. `LaunchAtLogin.promptForConsentIfNeeded` is deleted.

**Tech Stack:** Swift 6 / SwiftUI (macOS 15 SDK), SwiftData, Swift Testing, `SMAppService`. Zero third-party deps.

**Spec:** [`docs/superpowers/specs/2026-06-11-onboarding-flow-design.md`](../specs/2026-06-11-onboarding-flow-design.md)

**Repo conventions (override skill defaults):** work directly on `main` — no feature branch, no worktree, no PR. Commit after every task; a PostToolUse hook auto-pushes.

**Toolchain note:** Tasks 2–5 need full Xcode (the GUI app target). If `xcode-select -p` points at CommandLineTools, Task 1 still works (`./scripts/test-core.sh`); for the rest, either run the builds in Xcode or fix the toolchain first. Verify with `xcodebuild -version` (CLAUDE.md expects Xcode 26.5 — re-verify, the number may have moved). The Xcode project uses synchronized folder groups, so **new files are picked up automatically — no `project.pbxproj` edits**.

**SwiftUI API notes for the executor:** `@AppStorage` has a `Data` initializer (macOS 11+); `.safeAreaInset(edge:spacing:content:)` is macOS 12+; `.background(.bar)` is macOS 12+. All are long-stable on the macOS 15 target, but per CLAUDE.md, confirm against current docs if the build disagrees, and verify rendering on hardware in Task 5.

---

### Task 1: `WelcomeNote` content generator in `PopupNotesCore` (TDD)

**Files:**
- Test: `PopupNotesCore/Tests/PopupNotesCoreTests/WelcomeNoteTests.swift` (create)
- Create: `PopupNotesCore/Sources/PopupNotesCore/WelcomeNote.swift`

- [ ] **Step 1: Write the failing tests**

Create `PopupNotesCore/Tests/PopupNotesCoreTests/WelcomeNoteTests.swift`:

```swift
import Testing
import SwiftData
import Foundation
@testable import PopupNotesCore

@MainActor
@Suite struct WelcomeNoteTests {
    @Test func embedsTheHotkeyDisplayString() {
        #expect(WelcomeNote.text(hotKeyDisplay: "⌃⌘N").contains("⌃⌘N"))
        #expect(WelcomeNote.text(hotKeyDisplay: "⌥⌘J").contains("⌥⌘J"))
    }

    @Test func firstLineBecomesTheWelcomeTitle() {
        let text = WelcomeNote.text(hotKeyDisplay: "⌃⌘N")
        #expect(text.hasPrefix("Welcome to Popup Notes 👋\n"))
        #expect(NoteTitle.title(from: text) == "Welcome to Popup Notes 👋")
    }

    @Test func seedingCreatesExactlyOneWelcomeNote() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Note.self, configurations: config)
        let repo = NotesRepository(context: ModelContext(container))
        repo.create(text: WelcomeNote.text(hotKeyDisplay: "⌃⌘N"))
        repo.save()
        let all = repo.allSortedByModified()
        #expect(all.count == 1)
        #expect(all.first.map { NoteTitle.title(from: $0.text) } == "Welcome to Popup Notes 👋")
    }
}
```

(`@MainActor` on the suite because `NotesRepository` is `@MainActor` — same pattern as `NotesRepositoryTests.swift`.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./scripts/test-core.sh`
Expected: FAIL to compile — `cannot find 'WelcomeNote' in scope`.

- [ ] **Step 3: Write the minimal implementation**

Create `PopupNotesCore/Sources/PopupNotesCore/WelcomeNote.swift`:

```swift
/// Generates the seeded first-run "Welcome" note. Pure text; the first line
/// doubles as the note's sidebar title (see `NoteTitle`), which itself
/// demonstrates the title-from-first-line rule to the new user.
public enum WelcomeNote {
    public static func text(hotKeyDisplay: String) -> String {
        """
        Welcome to Popup Notes 👋

        Press \(hotKeyDisplay) in any app to open this panel — Esc or a click outside dismisses it.

        A few basics:
        • The first line of a note is its title in the sidebar.
        • ⌘N makes a new note · right-click a note to delete it.
        • Notes save automatically and live only on this Mac.
        • Settings (⌘,): change the shortcut, launch at login, export your notes.

        Delete this note whenever you're done with it.
        """
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./scripts/test-core.sh`
Expected: all suites PASS, including the 3 new `WelcomeNoteTests`.

- [ ] **Step 5: Commit**

```bash
git add PopupNotesCore/Sources/PopupNotesCore/WelcomeNote.swift PopupNotesCore/Tests/PopupNotesCoreTests/WelcomeNoteTests.swift
git commit -m "feat(core): WelcomeNote first-run note content generator"
```

---

### Task 2: `OnboardingDefaults` flags + `OnboardingStripView`

**Files:**
- Create: `PopupNotes/PopupNotes/Support/OnboardingDefaults.swift`
- Create: `PopupNotes/PopupNotes/Views/OnboardingStripView.swift`

No test target exists for the app; verification is a clean build (behavior is exercised in Task 5's smoke test).

- [ ] **Step 1: Create the flags namespace**

Create `PopupNotes/PopupNotes/Support/OnboardingDefaults.swift`:

```swift
import Foundation

/// One-time onboarding flags in `UserDefaults`. Each retires a piece of
/// first-run UI; `defaults delete ai.jetwriter.popupnotes` resets them all.
/// Key strings are shared with `OnboardingStripView`'s `@AppStorage`.
enum OnboardingDefaults {
    static let didRunFirstLaunchOnboardingKey = "didRunFirstLaunchOnboarding"
    static let didUseHotkeyOnceKey = "didUseHotkeyOnce"
    static let didDismissHotkeyHintKey = "didDismissHotkeyHint"
    static let didPromptLaunchAtLoginKey = "didPromptLaunchAtLogin" // reused legacy key — upgraders keep their answer
    static let hotKeyRegisteredKey = "hotKeyRegistered"

    static var didRunFirstLaunchOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: didRunFirstLaunchOnboardingKey) }
        set { UserDefaults.standard.set(newValue, forKey: didRunFirstLaunchOnboardingKey) }
    }

    static var didUseHotkeyOnce: Bool {
        get { UserDefaults.standard.bool(forKey: didUseHotkeyOnceKey) }
        set { UserDefaults.standard.set(newValue, forKey: didUseHotkeyOnceKey) }
    }

    /// Whether the most recent `RegisterEventHotKey` attempt succeeded.
    /// Defaults to true so the strip never flashes the failure text before
    /// the first registration attempt has written a real value.
    static var hotKeyRegistered: Bool {
        get { UserDefaults.standard.object(forKey: hotKeyRegisteredKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: hotKeyRegisteredKey) }
    }
}
```

- [ ] **Step 2: Create the strip view**

Create `PopupNotes/PopupNotes/Views/OnboardingStripView.swift`:

```swift
import SwiftUI
import PopupNotesCore

/// One-time first-run helpers pinned under the notes UI: a hotkey hint that
/// retires itself after the first real hotkey use (or its X button), and the
/// launch-at-login consent row — App Review 2.4.5(iii): explicit opt-in via
/// the Enable button, never a silent default. Renders nothing once both rows
/// have retired.
struct OnboardingStripView: View {
    @AppStorage(OnboardingDefaults.didUseHotkeyOnceKey) private var didUseHotkey = false
    @AppStorage(OnboardingDefaults.didDismissHotkeyHintKey) private var didDismissHint = false
    @AppStorage(OnboardingDefaults.didPromptLaunchAtLoginKey) private var didAnswerLogin = false
    @AppStorage(OnboardingDefaults.hotKeyRegisteredKey) private var hotKeyRegistered = true
    // Same defaults key HotKeyStore writes, so the hint live-updates when the
    // user records a new shortcut in Settings.
    @AppStorage("hotKeyCombo") private var comboData = Data()

    private var showHotkeyHint: Bool { !didUseHotkey && !didDismissHint }

    private var comboDisplay: String {
        ((try? JSONDecoder().decode(HotKeyCombo.self, from: comboData)) ?? .default).displayString
    }

    var body: some View {
        if showHotkeyHint || !didAnswerLogin {
            VStack(spacing: 0) {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    if showHotkeyHint { hotkeyRow }
                    if !didAnswerLogin { loginRow }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(.bar)
        }
    }

    private var hotkeyRow: some View {
        HStack(spacing: 6) {
            Image(systemName: hotKeyRegistered ? "keyboard" : "exclamationmark.triangle")
            Text(hotKeyRegistered
                 ? "Press \(comboDisplay) in any app to open Popup Notes"
                 : "Your shortcut is unavailable — set a new one in Settings (⌘,)")
            Spacer()
            Button { didDismissHint = true } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss shortcut hint")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var loginRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "power")
            Text("Start at login so your shortcut is ready after a restart")
            Spacer()
            Button("Enable") {
                LaunchAtLogin.isEnabled = true
                didAnswerLogin = true
            }
            Button("Not Now") { didAnswerLogin = true }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .controlSize(.small)
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run (from the repo root): `xcodebuild -project PopupNotes/PopupNotes.xcodeproj -scheme PopupNotes -configuration Debug build`
Expected: `BUILD SUCCEEDED`. (The view is not referenced yet — that's Task 4.)

- [ ] **Step 4: Commit**

```bash
git add PopupNotes/PopupNotes/Support/OnboardingDefaults.swift PopupNotes/PopupNotes/Views/OnboardingStripView.swift
git commit -m "feat(app): onboarding flags + self-retiring onboarding strip view"
```

---

### Task 3: `AppDelegate` orchestration + delete the consent alert

**Files:**
- Modify: `PopupNotes/PopupNotes/AppDelegate.swift` (lines 28–51: `applicationDidFinishLaunching`, `applyHotKey`; add two methods)
- Modify: `PopupNotes/PopupNotes/Support/LaunchAtLogin.swift` (delete `promptForConsentIfNeeded`, lines 23–51, and now-unused imports)

- [ ] **Step 1: Rewire `AppDelegate`**

In `PopupNotes/PopupNotes/AppDelegate.swift`, replace `applicationDidFinishLaunching` and `applyHotKey` with:

```swift
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon
        migrateLegacyIfNeeded()
        let ok = hotKey.register(currentHotKey) { [weak self] in self?.handleHotKeyFire() }
        OnboardingDefaults.hotKeyRegistered = ok
        if !ok {
            NSLog("PopupNotes: hotkey registration failed; use the menu-bar item.")
        }
        runFirstLaunchOnboardingIfNeeded()
    }

    /// Re-registers the global hotkey; restores the old combo and returns
    /// false if the new one is rejected (invalid or already taken).
    func applyHotKey(_ combo: HotKeyCombo) -> Bool {
        guard combo != currentHotKey else { return true }
        hotKey.unregister()
        if hotKey.register(combo, onFire: { [weak self] in self?.handleHotKeyFire() }) {
            currentHotKey = combo
            HotKeyStore.saved = combo
            OnboardingDefaults.hotKeyRegistered = true
            return true
        }
        let restored = hotKey.register(currentHotKey) { [weak self] in self?.handleHotKeyFire() }
        OnboardingDefaults.hotKeyRegistered = restored
        return false
    }

    /// Records the first real hotkey use (retires the strip's hint row),
    /// then toggles the panel. The guarded write keeps the hot path lean.
    private func handleHotKeyFire() {
        if !OnboardingDefaults.didUseHotkeyOnce {
            OnboardingDefaults.didUseHotkeyOnce = true
        }
        panel.toggle()
    }

    /// First launch only (also fires once for users upgrading from builds
    /// without this flag): seed the Welcome note when the database is empty
    /// — after legacy migration, so importers keep their own content — and
    /// show the panel so the user experiences the popup immediately.
    private func runFirstLaunchOnboardingIfNeeded() {
        guard !OnboardingDefaults.didRunFirstLaunchOnboarding else { return }
        OnboardingDefaults.didRunFirstLaunchOnboarding = true
        let repo = NotesRepository(context: container.mainContext)
        if repo.allSortedByModified().isEmpty {
            repo.create(text: WelcomeNote.text(hotKeyDisplay: currentHotKey.displayString))
            repo.save()
        }
        panel.show()
    }
```

Everything else in the file (`init`, `applicationWillTerminate`, `showNotes`, `migrateLegacyIfNeeded`) is unchanged. Note the old `LaunchAtLogin.promptForConsentIfNeeded(hotKeyDisplay:)` call is gone.

- [ ] **Step 2: Shrink `LaunchAtLogin` to the toggle**

Replace the entire contents of `PopupNotes/PopupNotes/Support/LaunchAtLogin.swift` with:

```swift
import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` for the "Launch at Login" toggle.
/// Registering adds the app to System Settings ▸ General ▸ Login Items.
/// Consent (App Review 2.4.5(iii)) is collected by the onboarding strip's
/// Enable button — never enabled silently.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("PopupNotes: Launch at Login toggle failed: \(error.localizedDescription)")
            }
        }
    }
}
```

(`promptForConsentIfNeeded` and the `AppKit` import are deleted; the pre-consent-default cleanup moves to a one-time reconciliation in runFirstLaunchOnboardingIfNeeded, keyed on the legacy didApplyFirstRunDefaults flag — review found upgraders straight from the silent-enable era would otherwise keep an unconsented login item.)

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project PopupNotes/PopupNotes.xcodeproj -scheme PopupNotes -configuration Debug build`
Expected: `BUILD SUCCEEDED`, no references to `promptForConsentIfNeeded` remain (`grep -rn "promptForConsentIfNeeded" PopupNotes/` returns nothing).

- [ ] **Step 4: Commit**

```bash
git add PopupNotes/PopupNotes/AppDelegate.swift PopupNotes/PopupNotes/Support/LaunchAtLogin.swift
git commit -m "feat(app): first-launch onboarding (seed + auto-show), drop consent alert"
```

---

### Task 4: Pin the strip into `NotesView`

**Files:**
- Modify: `PopupNotes/PopupNotes/Views/NotesView.swift` (the `body`, currently lines 16–37)

- [ ] **Step 1: Add the safe-area inset**

In `PopupNotes/PopupNotes/Views/NotesView.swift`, insert `.safeAreaInset` between the `NavigationSplitView`'s closing brace and `.frame`:

```swift
        } detail: {
            if let id = selection, let note = notes.first(where: { $0.id == id }) {
                NoteDetailView(note: note).id(id)
            } else {
                ContentUnavailableView("No Note Selected", systemImage: "note.text",
                                       description: Text("Select a note or create one."))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { OnboardingStripView() }
        .frame(minWidth: 360, minHeight: 220)
```

The inset spans the panel's full width below both split-view columns and pushes scrollable content up rather than covering it.

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project PopupNotes/PopupNotes.xcodeproj -scheme PopupNotes -configuration Debug build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add PopupNotes/PopupNotes/Views/NotesView.swift
git commit -m "feat(app): show the onboarding strip at the panel's bottom edge"
```

---

### Task 5: Docs + manual smoke test

**Files:**
- Modify: `CLAUDE.md` (component map, SMAppService bullet, smoke-test paragraph)

- [ ] **Step 1: Update CLAUDE.md**

Three edits:

1. In the **Tech stack** list, replace the `SMAppService` bullet's parenthetical:
   - Old: `**\`SMAppService.mainApp\`** for launch-at-login (one-time consent prompt on first run — App Review 2.4.5(iii) forbids silent enabling).`
   - New: `**\`SMAppService.mainApp\`** for launch-at-login (consent via the onboarding strip's Enable button — App Review 2.4.5(iii) forbids silent enabling).`

2. In the **Architecture** table:
   - `AppDelegate` row → `Sets \`.accessory\` policy; builds the shared SwiftData \`ModelContainer\`; runs one-time legacy migration + first-launch onboarding (seed Welcome note, auto-show panel); wires hotkey → panel and records registration status; saves on quit.`
   - Add a row after `NotesView · NotesListView · NoteDetailView`:
     `| \`OnboardingStripView\` · \`OnboardingDefaults\` | Self-retiring bottom strip: hotkey hint (until first hotkey use or dismissal; failure variant when registration fails) + launch-at-login Enable/Not Now consent; one-time \`UserDefaults\` flags. |`
   - `NotesJSON · ExportedNote · LegacyScratchpad` row: append `\`WelcomeNote\` (seeded first-run note content)` to the description's "In \`PopupNotesCore\`." sentence, e.g. `JSON export/import codec + DTO; one-time legacy-scratchpad import; \`WelcomeNote\` seeded first-run note content. In \`PopupNotesCore\`.`

3. Replace the **manual smoke test** paragraph under *Build & run* with:
   ```
   Manual smoke test: reset state (`defaults delete ai.jetwriter.popupnotes`;
   for a true fresh install also quit the app and delete
   `~/Library/Containers/ai.jetwriter.popupnotes` — this erases all notes).
   Launch: the panel auto-opens showing the seeded "Welcome to Popup Notes 👋"
   note with the onboarding strip at the bottom (hotkey hint + launch-at-login
   row). Press **⌃⌘N**: the panel toggles and the hint row is gone for good.
   Click **Enable**: the app appears in System Settings ▸ General ▸ Login
   Items and the consent row disappears. Create a note (**⌘N**), type a first
   line (it becomes the sidebar title), switch notes, press **Esc**; reopen
   and confirm persistence. Relaunch: no auto-show, no strip. Open
   **Settings (⌘,)**, record a new shortcut and confirm the hint (after
   resetting only its flags) mirrors it; try export/import; test once over a
   full-screen app.
   ```

- [ ] **Step 2: Run the full manual smoke test on hardware**

Follow the new CLAUDE.md paragraph end-to-end, including the upgrade path: with flags intact from a previous run, relaunch and confirm no second auto-show. Also verify the failure variant: set the shortcut to a combo another app owns (or temporarily register a conflicting hotkey via any running app that has one), relaunch after `defaults delete` of only `didUseHotkeyOnce`/`didDismissHotkeyHint`, and confirm the "shortcut unavailable" text shows.

Expected: every step behaves as written; no consent alert appears anywhere.

- [ ] **Step 3: Run the core tests one last time**

Run: `./scripts/test-core.sh`
Expected: all PASS.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update component map + smoke test for in-product onboarding"
```

---

## Spec coverage map (self-review)

| Spec section | Task |
|---|---|
| §4 first-launch flow (no alert, seed-if-empty, auto-show) | Task 3 |
| §4 Welcome note content | Task 1 |
| §5 strip rows, visibility rules, failure variant, a11y label | Task 2 |
| §5 strip placement | Task 4 |
| §6 state keys (incl. reused `didPromptLaunchAtLogin`, `hotKeyRegistered` default-true) | Tasks 2–3 |
| §7 `LaunchAtLogin` deletion | Task 3 |
| §8 upgraders (one auto-show, no re-consent) | Task 3 logic + Task 5 verification |
| §9 edge cases | Tasks 2–3 logic + Task 5 verification |
| §10 automated + manual testing | Tasks 1, 5 |
