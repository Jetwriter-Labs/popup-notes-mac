# Popup Notes for macOS — Architecture & Tech Stack Design

- **Date:** 2026-06-09
- **Status:** Approved (design phase)
- **Author:** Design session (Claude)

## 1. Summary

A native macOS background utility. The user presses a global keyboard
shortcut from anywhere; a translucent panel fades in over the current app,
already focused for typing. The user jots into a single persistent
scratchpad and dismisses it (Esc / click-away / press the shortcut again).
The panel saves and disappears, returning focus to the previous app.

The defining goals: **native, fast, latest Apple tooling, and zero
third-party dependencies.** The chosen scope makes all three achievable
simultaneously.

## 2. Decisions locked in this session

| Question | Decision | Consequence |
|---|---|---|
| Note model | **Single scratchpad** (one persistent document) | No notes list, no search, no database. One text file. |
| Deployment target | **macOS 15 floor** (built with latest Xcode 26 / Swift 6.3) | Runs on the developer's current Mac (15.7.7); forgoes macOS-26-only APIs (none required). |
| Global shortcut | **Fixed default in code** (⌃⌘N) | No recorder UI, no shortcut-persistence — therefore no third-party hotkey library. |
| Distribution | **Personal / direct, non-sandboxed** | No App Sandbox entitlements; notes stored in `~/Library/Application Support`. |

Net effect: **no third-party dependencies at all.** Everything is a
first-party Apple framework.

## 3. Goals / Non-goals

**Goals**
- Sub-perceptible popup latency; instant keyboard focus.
- Survive crashes without losing notes (atomic, debounced autosave).
- Overlay the current app without yanking the user out of it.
- Work over full-screen apps and across all Spaces.

**Non-goals (YAGNI for v1)**
- Multiple notes, sticky notes, tags, search.
- User-customizable shortcut + recorder UI.
- Rich text / Markdown rendering (plain-text editing only).
- iCloud / sync / sharing.
- App Store distribution & sandboxing.
- A separate Settings/Preferences window (the menu-bar menu suffices).

## 4. Tech stack (current as of June 2026 — re-verify before use)

| Concern | Choice | Rationale |
|---|---|---|
| Language | Swift 6.3 (Swift 6 language mode, strict concurrency) | Latest; compile-time data-race safety. |
| UI | SwiftUI (macOS 15 SDK) | Native, declarative, latest. |
| App shell | `MenuBarExtra` + `NSApplicationDelegateAdaptor`; `.accessory` activation policy (`LSUIElement`) | Menu-bar presence, no Dock icon. |
| Popup window | `NSPanel` subclass (`.nonactivatingPanel`, `.floating` level) hosting SwiftUI via `NSHostingView` | Overlays the current app without stealing it away; can float over full-screen apps and join all Spaces. |
| State | Observation framework (`@Observable`, macOS 14+) | Modern replacement for `ObservableObject` / `@Published`. |
| Global hotkey | Carbon `RegisterEventHotKey` + `InstallEventHandler`, wrapped (~50 LOC) | Confirmed the only native option in 2026; zero deps. |
| Persistence | Single UTF-8 `.md` file via Foundation; atomic writes + debounced autosave | Trivial model — no DB; fast; user-inspectable; future-proof. |
| Launch at login | `SMAppService.mainApp` (ServiceManagement, macOS 13+) | Native; no login-item helper. |
| Build / test | Xcode 26.5 project + Swift Testing (`import Testing`) | First-party toolchain; modern test framework. |
| Third-party deps | **None** | Matches the project's core constraint. |

### Prerequisite
The dev machine currently has only Command Line Tools. Building a macOS GUI
app requires **Xcode 26.5** (App Store or developer.apple.com/download).
This is Apple's own toolchain, not a project dependency.

## 5. Architecture — components

Each unit has a single responsibility and a small, clear interface.

- **`PopupNotesApp`** (SwiftUI `App`) — entry point. Declares the
  `MenuBarExtra` menu and bridges to `AppDelegate` via
  `NSApplicationDelegateAdaptor`.
- **`AppDelegate`** (`NSApplicationDelegate`) — on launch sets `.accessory`
  policy, constructs `NoteStore`, `HotKeyManager`, `PanelController`, and
  wires the hotkey callback to `PanelController.toggle()`. Flushes a save on
  terminate.
- **`HotKeyManager`** — wraps `RegisterEventHotKey` / `InstallEventHandler`.
  Registers a fixed keycode + modifiers and invokes a Swift closure when the
  hotkey fires. Hides all Carbon interop behind one clean API. Default
  **⌃⌘N** (a code constant). Avoids Option-only / Option+Shift modifiers
  (broken with this API on macOS 15+).
- **`PanelController`** — owns the panel lifecycle: lazily builds the
  `FloatingPanel`, hosts `ScratchpadView` via `NSHostingView`, positions it
  centered on the active screen, toggles show/hide, installs a click-outside
  global event monitor, and handles Esc-to-dismiss.
- **`FloatingPanel`** (`NSPanel` subclass) — `.nonactivatingPanel`,
  `.floating` level, borderless with `.ultraThinMaterial`;
  `canBecomeKey = true` so the editor receives keystrokes;
  `collectionBehavior` = `.canJoinAllSpaces` + `.fullScreenAuxiliary`.
- **`ScratchpadView`** (SwiftUI) — a `TextEditor` bound to the note text,
  minimal chrome, material background. Esc dismisses (forwarded to the
  controller).
- **`NoteStore`** (`@Observable`) — loads the scratchpad file at launch,
  exposes the text, performs debounced autosave (~0.6 s after the last
  keystroke) plus an immediate save on hide/quit, using atomic writes.

The **`MenuBarExtra` menu** holds: *Show Scratchpad*, *Open Notes File*,
*Launch at Login* (toggle, via `SMAppService`), *Quit*. This replaces a
dedicated Settings window for v1.

## 6. Data flow

1. **Launch** → `.accessory` policy set → `NoteStore` loads file into memory
   → `HotKeyManager` registers ⌃⌘N → `MenuBarExtra` icon appears.
2. **⌃⌘N pressed (anywhere)** → `PanelController` positions the panel on the
   screen containing the mouse, `makeKeyAndOrderFront`, focuses the editor,
   installs the click-outside monitor.
3. **Typing** → SwiftUI binding updates `NoteStore.text` → debounced save to
   disk.
4. **Esc / click-outside / ⌃⌘N again** → immediate save → `orderOut` → remove
   monitor → focus returns to the previous app.

## 7. Persistence & data safety

- **Location:** `~/Library/Application Support/PopupNotes/scratchpad.md`
  (created on first run). Plain UTF-8 text; `.md` extension for friendly
  viewing/grepping. (Constant — easy to change to `~/Documents` if desired.)
- **Atomic writes:** write to a temp file and rename, so a crash mid-write
  cannot corrupt the note.
- **No data loss on failure:** in-memory text is the source of truth; a
  failed save is retried on the next change and on quit. If the file cannot
  be *read* at launch, start empty but do **not** overwrite the existing file
  until the user actually edits.

## 8. Error handling & edge cases

- **Focus handoff** (the one fiddly area): a non-activating panel that must
  still become key for text entry and then return focus cleanly. Exact
  `activate` / first-responder sequence to be verified against current Apple
  docs during implementation.
- **Full-screen / multi-display:** `collectionBehavior` lets the panel appear
  over full-screen apps and on every Space; the panel centers on the screen
  under the mouse.
- **Hotkey registration failure / conflict:** logged; the menu-bar *Show
  Scratchpad* item is always an alternate way to open the panel.

## 9. Testing

- Framework: **Swift Testing** (`@Test`, `#expect`).
- Unit-tested core (isolated behind clean interfaces):
  - `NoteStore`: load/save round-trip, atomic write, debounce timing (against
    a temp directory; inject the clock/scheduler).
  - `HotKeyManager`: keycode/modifier mapping logic.
- Panel show/hide, focus handoff, and overlay behavior: verified via a short
  manual test checklist (run the app, exercise the shortcut in several
  contexts including a full-screen app).

## 10. Project layout (proposed)

```
popup-notes-mac/
├── CLAUDE.md
├── docs/superpowers/specs/2026-06-09-popup-notes-architecture-design.md
├── PopupNotes.xcodeproj
├── PopupNotes/
│   ├── PopupNotesApp.swift
│   ├── AppDelegate.swift
│   ├── HotKey/HotKeyManager.swift
│   ├── Panel/PanelController.swift
│   ├── Panel/FloatingPanel.swift
│   ├── Views/ScratchpadView.swift
│   ├── Store/NoteStore.swift
│   ├── Support/LaunchAtLogin.swift   // SMAppService wrapper
│   └── Info.plist                    // LSUIElement = true
└── PopupNotesTests/
    ├── NoteStoreTests.swift
    └── HotKeyManagerTests.swift
```

## 11. Risks & open items

- **Focus/activation sequence** for a non-activating panel hosting an editor
  is the highest-risk detail; budget time to verify against current docs and
  test on real hardware.
- **Carbon `RegisterEventHotKey`** is legacy but still the only native path;
  monitor Apple release notes in case a modern replacement ships.
- **Default shortcut conflict:** ⌃⌘N may collide with some apps; it is a
  one-line constant to change, and customization is a known future option.

## 12. Future (explicitly deferred)

User-customizable shortcut (would justify `sindresorhus/KeyboardShortcuts`),
multiple notes / capture inbox, search, Markdown preview, iCloud sync, App
Store build with sandboxing.
