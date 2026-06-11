# CLAUDE.md — Popup Notes for macOS

Guidance for Claude (and humans) working in this repository.

A native macOS background utility: press a global keyboard shortcut anywhere
to overlay a popup over the current app, jot notes, and dismiss it. A resizable
panel shows a sidebar of notes (each titled by its first line) beside the
selected note's editor, backed by a local **SwiftData** database. Native, fast,
zero third-party dependencies.

---

## ⚠️ READ FIRST: Your training data is stale — verify against current docs

**Your knowledge cutoff is January 2026. This project is being built in
mid-2026 or later. Apple's tooling (macOS, Swift, SwiftUI, AppKit, Xcode)
moves fast, deprecates APIs, and renames things between releases.**

Treat your memory as a *starting hypothesis, never a source of truth.* Before
you use, recommend, or claim anything about an Apple/Swift API, version, or
behavior:

1. **Verify against the latest official Apple documentation and release
   notes** (links at the bottom of this file). Prefer first-party sources.
2. **Confirm current version numbers** — do not assume. The numbers in this
   file (below) were accurate at authoring time and may already be behind.
   Check `xcodebuild -version`, `swift --version`, and `sw_vers` locally, and
   the official release notes for the latest available.
3. **Check API availability and deprecations** for the deployment target
   (macOS 15) — an API you "remember" may be newer, older, renamed, or
   removed. Use `@available` / availability docs to confirm.
4. **When memory and the docs disagree, the docs win.** If you cannot verify
   something, say so explicitly rather than guessing.

This applies with extra force to: version numbers, SwiftUI/AppKit API names
and signatures, Swift concurrency rules, the Carbon hotkey path, the
non-activating-panel focus sequence, and `SMAppService`.

**Do not write code from memory for an API you have not verified.** Look it
up first.

---

## What this app is

- **Trigger:** a global shortcut (default **⌃⌘N**, user-customizable via the
  Settings recorder) registered via Carbon `RegisterEventHotKey`.
- **UI:** a non-activating, floating, **resizable** `NSPanel` hosting a SwiftUI
  `NavigationSplitView` — a sidebar list of notes beside the selected note's
  `TextEditor` — overlaid over the current app without stealing it away.
- **Model:** **multiple notes** in a local **SwiftData** database (SQLite under
  the hood). Each note's **title is its first line**. A **Settings** window
  offers launch-at-login and JSON export/import.
- **Shell:** a menu-bar accessory app (no Dock icon).

Current design (multiple notes + SwiftData + Settings — **supersedes the
single-note model**):
[`docs/superpowers/specs/2026-06-09-multiple-notes-swiftdata-design.md`](docs/superpowers/specs/2026-06-09-multiple-notes-swiftdata-design.md).
Original architecture & scope rationale:
[`docs/superpowers/specs/2026-06-09-popup-notes-architecture-design.md`](docs/superpowers/specs/2026-06-09-popup-notes-architecture-design.md).

## Tech stack (as of June 2026 — **re-verify, see warning above**)

- **Swift 6.3** (Swift 6 language mode, strict concurrency).
- **SwiftUI** (macOS 15 SDK) for views; **AppKit** interop for the panel.
- **Observation** framework (`@Observable`) for state — not `ObservableObject`.
- **`NSPanel`** (`.nonactivatingPanel`, `.floating`) + `NSHostingView` for the
  popup.
- **`MenuBarExtra`** + `NSApplicationDelegateAdaptor`; `.accessory` policy
  (`LSUIElement = true`).
- **Carbon `RegisterEventHotKey`** for the global hotkey (the only native
  option — confirmed still true in 2026).
- **SwiftData** (`@Model`, SQLite-backed) for the notes database — first-party,
  so still zero third-party deps. Pure logic + the SwiftData repository live in
  the **`PopupNotesCore`** SwiftPM package; run its tests with
  `./scripts/test-core.sh` (works on Command Line Tools or full Xcode).
- **`SMAppService.mainApp`** for launch-at-login (one-time consent prompt on
  first run — App Review 2.4.5(iii) forbids silent enabling).
- **Swift Testing** (`import Testing`) for tests.
- **Xcode 26.5** to build (Command Line Tools alone are not enough for a GUI
  app bundle).
- **Third-party dependencies: none.**

## Architecture (component map)

| Unit | Responsibility |
|---|---|
| `PopupNotesApp` | SwiftUI `App` entry; declares `MenuBarExtra` + the `Settings` scene; bridges to `AppDelegate`. |
| `AppDelegate` | Sets `.accessory` policy; builds the shared SwiftData `ModelContainer`; runs one-time legacy migration + first-run launch-at-login consent prompt; wires hotkey → panel; saves on quit. |
| `HotKeyManager` | Wraps Carbon `RegisterEventHotKey`; fires a Swift closure on the hotkey. |
| `PanelController` | Owns panel lifecycle: build, host `NotesView` (injecting the container), frame-remember, show/hide, click-outside monitor, Esc. |
| `FloatingPanel` | `NSPanel` subclass: non-activating, floating, **resizable** (frame remembered), becomes key for typing, all-Spaces + full-screen-aux. |
| `NotesView` · `NotesListView` · `NoteDetailView` | SwiftUI master-detail: `@Query` sidebar (title + date, new/delete-with-confirm) + the selected note's `TextEditor`. |
| `SettingsView` · `HotKeyRecorderView` | `Settings` scene, two tabs — General: launch-at-login toggle, global-shortcut recorder (persisted by `HotKeyStore`), JSON export/import; About: local-only/no-analytics statement, GitHub + jetwriter.ai links. |
| `Note` (`@Model`) · `NotesRepository` | SwiftData model (id, text, created, modified; first-line `title`) + CRUD (create/delete/sort/upsert). In `PopupNotesCore`. |
| `NotesJSON` · `ExportedNote` · `LegacyScratchpad` | JSON export/import codec + DTO; one-time legacy-scratchpad import. In `PopupNotesCore`. |

## Conventions & principles

- **Native-first.** Use Apple frameworks. Prefer the platform idiom over
  clever abstractions.
- **Zero third-party dependencies by default.** Do **not** add a package
  unless it provides *genuine, hard-to-replicate* value, and call that
  trade-off out explicitly for human sign-off first. (Example where it *would*
  be justified: a user-customizable shortcut recorder UI — out of scope for
  v1.) Re-implementing ~50 lines of Carbon glue does **not** justify a dep.
- **Performance is a feature.** Popup latency and instant keyboard focus are
  the product. Keep the show path lean; avoid heavy work on the main actor
  during show/hide.
- **Modern Swift.** Swift 6 language mode; `async`/`await`; `@MainActor` on UI
  types; honor strict concurrency (no data races). Use `@Observable`, not the
  legacy `ObservableObject`/`@Published`.
- **Small, single-responsibility files** with clear interfaces (see the
  component map). If a file grows to do several things, split it.
- **Data safety over cleverness.** SwiftData autosaves; also `save()` on panel
  hide and on quit. Migration never deletes the legacy file. JSON export is the
  user's backup / portability path.
- **Verify, then claim.** Run the build/tests and observe real behavior before
  saying something works (see warning at top re: docs).

## Project skills (installed)

Project-scoped skills live under `.agents/skills/` (symlinked into
`.claude/skills/`) and load on the **next** session. Invoke the relevant one
before the matching work:

- **swiftui-expert-skill** (avdlee) — SwiftUI views, state, performance, Liquid
  Glass; consults its own `references/latest-apis.md` to avoid deprecated APIs.
- **swift-concurrency** (avdlee) — Swift 6 strict concurrency, `@MainActor`,
  `Sendable`, data races, the Carbon C-callback boundary.
- **macos-design-guidelines** — Apple HIG for Mac: menu bar, keyboard
  shortcuts, window/panel behavior.
- **swift-testing** — Swift Testing (`@Test`, `#expect`) for the test target.
- **xcode-build-fixer** (avdlee) — apply/verify Xcode build-setting fixes.

These are tools, not overrides — the "verify against current docs" rule at the
top still governs anything they suggest.

## Build & run

> Requires **Xcode 26.5** installed (this machine may have only Command Line
> Tools — check `xcode-select -p` and `xcodebuild -version`).

```sh
# Build
xcodebuild -scheme PopupNotes -configuration Debug build

# Test
xcodebuild -scheme PopupNotes -destination 'platform=macOS' test
```

Or open `PopupNotes.xcodeproj` in Xcode and Run (⌘R) / Test (⌘U).

Manual smoke test: launch, confirm the menu-bar icon (no Dock icon), press
**⌃⌘N**, create a note (**⌘N**) and type a first line (it becomes the sidebar
title), switch between notes, press **Esc**; reopen and confirm notes persisted;
open **Settings (⌘,)** and try export/import; test once over a full-screen app.

## Key gotchas / constraints

- **Hotkey modifiers:** Option-only and Option+Shift combos are broken with
  `RegisterEventHotKey` on macOS 15+. Don't use them for the default.
- **Panel focus handoff** is the trickiest detail: the panel is *non-activating*
  yet must become key to receive typing, then return focus to the prior app on
  dismiss. Verify the exact `NSApp.activate` / first-responder sequence against
  current docs and test on hardware.
- **Accessory app:** `LSUIElement = true` means no Dock icon — the menu-bar
  item is the only visible affordance and the way to quit.
- **Overlay reach:** set `collectionBehavior` to `.canJoinAllSpaces` +
  `.fullScreenAuxiliary` so the panel shows over full-screen apps and on all
  Spaces.
- **Sandboxed** — the Xcode app template enabled App Sandbox and we kept it
  (this **supersedes the original specs' non-sandboxed plan**). Data lives in
  the app container, e.g. `~/Library/Containers/ai.jetwriter.popupnotes/Data/
  Library/Application Support/PopupNotes/Notes.store`, **not** a user-visible
  folder. File-picker export/import works via the sandbox powerbox; SwiftData,
  the Carbon hotkey, and `SMAppService` all work sandboxed.

## Official docs to verify against (first-party first)

- Apple Developer Documentation: https://developer.apple.com/documentation/
- SwiftUI: https://developer.apple.com/documentation/swiftui/
- `MenuBarExtra`: https://developer.apple.com/documentation/swiftui/menubarextra
- AppKit `NSPanel`: https://developer.apple.com/documentation/appkit/nspanel
- `NSWindow.StyleMask` (`.nonactivatingPanel`): https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct
- Observation: https://developer.apple.com/documentation/observation
- `SMAppService`: https://developer.apple.com/documentation/servicemanagement/smappservice
- `RegisterEventHotKey` (Carbon): https://developer.apple.com/documentation/carbon/1465359-registereventhotkey
- Swift Testing: https://developer.apple.com/documentation/testing/
- Xcode release notes: https://developer.apple.com/documentation/xcode-release-notes/
- Swift (language/toolchain): https://www.swift.org/documentation/

When in doubt, search the latest Apple docs and release notes before acting —
your memory may be out of date.
