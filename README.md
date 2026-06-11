# Popup Notes

**Press a hotkey anywhere on your Mac. A notes panel pops up over whatever
you're doing. Jot, hit Esc, back to work.**

Popup Notes is a free, open-source menu-bar utility for capturing thoughts
without breaking flow — no Dock icon, no window juggling, no cloud.

## Features

- **Global hotkey** — `⌃⌘N` by default, customizable in Settings. Works over
  any app, full-screen apps and all Spaces included.
- **Doesn't steal your context** — the panel floats over the current app
  without deactivating it, and focus returns the moment you dismiss.
- **Multiple notes** — a sidebar lists every note, titled by its first line.
  `⌘N` for a new one.
- **Fully local & private** — notes live in a SwiftData (SQLite) database on
  your Mac. No analytics, no tracking, no account, no network. JSON
  export/import is your backup and portability path.
- **Native and fast** — Swift 6 + SwiftUI + AppKit, zero third-party
  dependencies, instant keyboard focus.

## Install

Download the notarized DMG from
[Releases](https://github.com/Jetwriter-Labs/popup-notes-mac/releases), drag
**Popup Notes** to Applications, launch, and press `⌃⌘N`.

Or build from source (requires Xcode 26+):

```sh
git clone https://github.com/Jetwriter-Labs/popup-notes-mac.git
cd popup-notes-mac
xcodebuild -project PopupNotes/PopupNotes.xcodeproj -scheme PopupNotes build
```

## Project layout

| Path | What |
|---|---|
| `PopupNotes/` | The app: menu bar shell, floating panel, hotkey, Settings. |
| [`PopupNotesCore/`](PopupNotesCore/) | SwiftPM package — pure logic (notes model, repository, JSON codec, hotkey combo). Tested without Xcode: `./scripts/test-core.sh` |
| [`scripts/release.sh`](scripts/release.sh) | Build → sign → notarize → DMG. |
| [`docs/`](docs/) | Design specs and the release guide. |

## Tech

Swift 6 (strict concurrency) · SwiftUI + AppKit (`NSPanel`) · SwiftData ·
Carbon `RegisterEventHotKey` · Swift Testing · sandboxed · **no third-party
dependencies**.

## About the makers

Popup Notes is built by the team behind **[JetWriter](https://jetwriter.ai)** —
your personal AI writing assistant in the browser. It writes emails in your
voice (it learns from your past ones), fixes grammar, translates, and lets you
chat with any webpage — without switching tabs. If a notes popup saves you
seconds, JetWriter saves you the whole email.

## License

[MIT](LICENSE) © 2026 Gourav Goyal
