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
  editor — overlaid over the current app without stealing it away. Notes are
  **Markdown, styled live** as you type (our own parser, no dependency), and a
  note with headings gets a **sticky outline** pane beside the editor.
- **Model:** **multiple notes** in a local **SwiftData** database (SQLite under
  the hood). Each note's **title is its first line**. A **Settings** window
  offers launch-at-login and JSON export/import.
- **Shell:** a menu-bar accessory app (no Dock icon).

Current design (multiple notes + SwiftData + Settings — **supersedes the
single-note model**):
[`docs/superpowers/specs/2026-06-09-multiple-notes-swiftdata-design.md`](docs/superpowers/specs/2026-06-09-multiple-notes-swiftdata-design.md).
Markdown editing + outline (supersedes that spec's "no Markdown" non-goal):
[`docs/superpowers/specs/2026-10-17-markdown-outline-design.md`](docs/superpowers/specs/2026-10-17-markdown-outline-design.md).
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
  `./scripts/test-core.sh` (needs full Xcode — SwiftData's `@Model` macro
  plugin doesn't ship with the Command Line Tools).
- **`SMAppService.mainApp`** for launch-at-login (consent via the onboarding
  strip's Enable button — App Review 2.4.5(iii) forbids silent enabling).
- **Swift Testing** (`import Testing`) for tests.
- **Xcode 26.5** to build (Command Line Tools alone are not enough for a GUI
  app bundle).
- **Third-party dependencies: none.**

## Architecture (component map)

| Unit | Responsibility |
|---|---|
| `PopupNotesApp` | SwiftUI `App` entry; declares `MenuBarExtra` + the `Settings` scene; bridges to `AppDelegate`. |
| `AppDelegate` | Sets `.accessory` policy; builds the shared SwiftData `ModelContainer` (if the store won't open: an explanatory alert and quit, file untouched — never a crash loop); runs one-time legacy migration + first-launch onboarding (seed Welcome note, reconcile pre-consent login default); wires hotkey → panel and publishes its state in `HotKeyStatus`; opens the panel on a user launch and on reopen (Spotlight/Raycast/Finder), prewarms it after a login launch; saves on quit. |
| `HotKeyManager` | Wraps Carbon `RegisterEventHotKey`; fires a Swift closure on the hotkey. |
| `HotKeyStatus` · `HotKeyStore` | In-memory `@Observable` live hotkey state (combo + registered), observed by the menu bar, strip and Settings; `HotKeyStore` persists the combo in `UserDefaults`. |
| `PanelController` | Owns panel lifecycle: build (or prewarm offscreen), host `NotesView` (injecting the container), frame-remember + follow the mouse's display, show/hide/`activate`/toggle (re-keys an unfocused panel), editor focus on show, click-outside monitor, Esc/⌘W, ⌘H recovery, gets out of the way of Settings. |
| `FloatingPanel` | `NSPanel` subclass: non-activating, floating, **resizable** (frame remembered), becomes key for typing, all-Spaces + full-screen-aux; handles ⌘W and ⌃⌘O (outline) itself. |
| `NotesView` · `NotesListView` · `NoteDetailView` · `NoteTextEditor` | SwiftUI master-detail: `@Query` sidebar (title, then `date · preview`; ⌘N stays in an open blank note; delete via context menu or ⌫ in the list — confirmed unless blank — then the neighbor is selected; blank notes are discarded once you leave them) + the selected note's `NSTextView`-backed editor (own undo history per note) and, beside it, its outline. |
| `MarkdownTextView` · `MarkdownStyler` · `MarkdownTheme` | The editor (`Editor/`): a TextKit 2 `NSTextView` whose text stays plain Markdown. The styler (text-storage delegate, `didProcessEditing` — never `willProcessEditing`, which misplaces the caret) restyles only the lines an edit changed; the view draws code-block/quote/rule backgrounds, continues lists on Return, nests with Tab/Shift-Tab, toggles ⌘B/⌘I (each its own undo step), checks task boxes on click, and scrolls to a heading. Never touch its `layoutManager` (falls back to TextKit 1). |
| `NoteOutline` · `NoteOutlineView` | The sticky outline: `@Observable` headings + current section (caret's, or the top line's when the caret is off screen), kept current by the editor's coordinator; the pane lists them, highlights the current one, jumps on click. Shown with ≥ 2 headings while "Show Outline" (⋯ menu, ⌃⌘O, `showsOutline` default) is on and the detail is ≥ 420 pt wide. |
| `OnboardingStripView` · `OnboardingDefaults` | Self-retiring bottom strip: hotkey hint (until first hotkey use or dismissal; failure variant when registration fails) + launch-at-login Enable/Not Now consent; one-time `UserDefaults` flags. |
| `SettingsView` · `HotKeyRecorderView` · `SettingsButton` | `Settings` scene, two tabs — General: launch-at-login toggle (shows the real `SMAppService` status, "Open Login Items…" when approval is needed), global-shortcut recorder (persisted by `HotKeyStore`), JSON export/import; About: local-only/no-analytics statement, GitHub + jetwriter.ai links. `SettingsButton` is the one "Settings…" path (panel ⋯ menu, strip, menu bar, ⌘,): it hides the floating panel and activates the app first. |
| `Note` (`@Model`) · `NotesRepository` · `NoteSelection` | SwiftData model (id, text, created, modified; first-line `title` and `preview` read without Markdown syntax, `isBlank`, `isAlive`) + CRUD and newer-wins `importNotes` (one fetch, throws rather than treating a failed fetch as empty); neighbor-on-delete rule. In `PopupNotesCore`. |
| `NotesJSON` · `ExportedNote` · `LegacyScratchpad` | JSON export/import codec + DTO; one-time legacy-scratchpad import; `WelcomeNote` seeded first-run note content (Markdown, so its headings fill the outline). In `PopupNotesCore`. |
| `MarkdownBlocks` · `MarkdownInline` · `MarkdownOutline` · `MarkdownEditing` | Dependency-free Markdown in UTF-16 `NSRange`s: line kinds (headings, lists, tasks, quotes, fences, rules), inline spans (CommonMark emphasis rules, code, links, bare URLs), the heading outline, and pure edits for Return/Tab/⌘B/⌘I/tasks. In `PopupNotesCore`. |
| `AppLaunchKind` · `LaunchEvent` | Tells a user launch from a login/Services launch via the `kAEOpenApplication` event's `keyAELaunchedAsLogInItem`/`…ServiceItem` markers, so the panel opens for the former and stays hidden for the latter. Classifier in `PopupNotesCore`; Carbon event reader in the app. |

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

# Test (the PopupNotesCore package holds all unit tests; the app target has none)
./scripts/test-core.sh
```

Or open `PopupNotes.xcodeproj` in Xcode and Run (⌘R).

Manual smoke test: reset state (`defaults delete ai.jetwriter.popupnotes`;
for a true fresh install also quit the app and delete
`~/Library/Containers/ai.jetwriter.popupnotes` — this erases all notes).
Launch: the panel auto-opens showing the seeded "Welcome to Popup Notes 👋"
note with the onboarding strip at the bottom (hotkey hint + launch-at-login
row). Press **⌃⌘N**: the panel toggles and the hint row is gone for good.
Click **Enable**: the app appears in System Settings ▸ General ▸ Login
Items and the consent row disappears. Create a note (**⌘N**), type a first
line (it becomes the sidebar title), switch notes, press **Esc**; reopen
and confirm persistence. Markdown: type `# Title` (the sidebar shows
"Title"), `**bold**`, `` `code` ``, a fenced block; in `- item` press Return
(the list continues), Tab (it nests), Return on the empty item (it ends);
select a word and ⌘B, then ⌘Z (only the bold goes); click a `- [ ]` box.
Outline: the Welcome note shows it; a new note gets it at its second
heading; the highlight follows the caret, and the top of the note while
scrolling with the caret off screen; clicking a heading brings it to the
top; ⌃⌘O and the pane's button hide it; a narrow panel drops it. Relaunch: the panel opens (a user launch is a
request to see the notes) but the strip is gone. Press **Esc**, then open
"Popup Notes" from Spotlight or Raycast *while it is still running* — the
panel must come back; that reopen path once did nothing at all. With
launch-at-login enabled, log out and back in: the app must come up in the
menu bar **silently**, no panel (this is the one path `open -a` cannot
exercise — it needs a real login). Open
**Settings (⌘,)**, record a new shortcut and confirm the hint (after
resetting only its flags) mirrors it; try export/import; test once over a
full-screen app.

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
