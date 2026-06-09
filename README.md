# Popup Notes for macOS

A native macOS menu-bar utility: press a global shortcut (**⌃⌘N**) from any app
to overlay a translucent scratchpad over whatever you're doing, jot a quick
note, and dismiss it. One persistent plain-text file. Native, fast, zero
third-party dependencies.

> **Status: early development.** The core logic is built and tested; the app
> shell is in progress (needs Xcode — see below).

## How it works

- **Trigger:** a fixed global hotkey (⌃⌘N) via Carbon `RegisterEventHotKey`.
- **UI:** a non-activating, floating `NSPanel` hosting a SwiftUI `TextEditor`,
  centered on the display under the mouse — overlays the current app without
  stealing focus away from it.
- **Model:** a single persistent scratchpad at
  `~/Library/Application Support/PopupNotes/scratchpad.md`, saved with debounced
  atomic writes.
- **Shell:** a menu-bar accessory app (no Dock icon).

## Project layout

| Path | What |
|---|---|
| [`PopupNotesCore/`](PopupNotesCore/) | SwiftPM package — pure logic (hotkey, persistence, store). Built & unit-tested without Xcode. |
| `PopupNotes/` | The Xcode app shell (menu bar, panel, focus handoff). *In progress.* |
| [`docs/superpowers/specs/`](docs/superpowers/specs/) | Design specs. |
| [`docs/superpowers/plans/`](docs/superpowers/plans/) | Implementation plan + progress. |

## Build & test

**Core logic** (no Xcode required — works on the Command Line Tools):

```sh
./scripts/test-core.sh
```

**The app** (requires **Xcode 26.5**):

```sh
xcodebuild -scheme PopupNotes -configuration Debug build
xcodebuild -scheme PopupNotes -destination 'platform=macOS' test
```

## Tech stack

Swift 6 (strict concurrency) · SwiftUI + AppKit · Observation (`@Observable`) ·
Carbon hotkey · Foundation persistence · Swift Testing · **no third-party
dependencies**.
