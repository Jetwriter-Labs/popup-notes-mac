# Popup Notes — Core Capture Flow Design

- **Date:** 2026-06-09
- **Status:** Approved (design phase) — ready for implementation planning
- **Parent spec:** [`2026-06-09-popup-notes-architecture-design.md`](2026-06-09-popup-notes-architecture-design.md)
- **Scope of this doc:** the core capture loop only (hotkey → panel → type → save → dismiss), plus the minimal menu-bar presence needed to make that loop runnable. Everything in the parent spec still holds; this doc only refines and narrows it.

## 1. Summary

The product's heart: press **⌃⌘N** from any app, a translucent fixed-size panel
fades in centered on the display under the mouse, already focused for typing
with the cursor at the end of the existing note. Jot text; it autosaves.
Dismiss with Esc, a click outside, or ⌃⌘N again — the panel saves immediately,
disappears, and focus returns to the app you were in.

This is a focused slice of the parent architecture. Big decisions (single
scratchpad, Carbon hotkey, non-activating `NSPanel` + SwiftUI `TextEditor`,
`.accessory` app, atomic file persistence, zero third-party deps) are inherited
unchanged. This doc records the details settled in the 2026-06-09 design
session and the implementation-time risks to verify.

## 2. Scope

**In scope (this round)**
- Global hotkey registration (⌃⌘N) and toggle behavior.
- The floating panel: build, position, show/hide, focus, dismiss.
- The text editor and its binding to the note.
- Single-file persistence (load, debounced autosave, atomic write, save on
  hide/quit).
- A **minimal** `MenuBarExtra`: icon, *Show Scratchpad*, *Quit*.

**Deferred (explicitly out, per the approved scope)**
- *Open Notes File* menu item.
- *Launch at Login* (`SMAppService`) — `LaunchAtLogin.swift` not built yet.
- Any Settings/Preferences window.
- Resizable or position/size-remembering panel.
- Everything in the parent spec's §12 "Future."

## 3. Decisions settled this session

| Topic | Decision | Notes |
|---|---|---|
| Popup position | **Centered on the display the mouse is on** | Resolves the parent spec's §5/§6 inconsistency in favor of "screen under the mouse." Predictable, Spotlight-like, nothing to persist. |
| Panel size | **Fixed ~480×320 pt, non-resizable** | Long notes scroll internally. No window-frame state on disk. |
| Menu-bar presence | **Minimal: icon + *Show Scratchpad* + *Quit*** | Required — an `LSUIElement` app has no Dock icon, so without this there is no way to quit it and no fallback if the hotkey fails to register. |
| Reopen behavior | **Focus editor, cursor at end** of existing text | Append-style. Never select-all / auto-overwrite — it is a persistent document. |
| Chrome | **Fully chromeless** — no title bar/header/footer | Faint `"Jot a note…"` placeholder when empty. |
| Show/hide animation | **Short fade ~0.12 s** | Cosmetic; keep it off the critical focus path. Drop to instant if it ever costs perceived latency. |
| Dismiss triggers | **Esc**, **click outside**, **⌃⌘N again** (toggles) | All three per parent spec §6. |

## 4. Behavior — the capture loop

1. **Launch** → set `.accessory` activation policy → `NoteStore` loads the file
   into memory → `HotKeyManager` registers ⌃⌘N → `MenuBarExtra` icon appears.
2. **⌃⌘N pressed (anywhere)** → `PanelController`:
   - computes the frame centered on the `NSScreen` containing the mouse,
   - shows the panel and makes it key (non-activating),
   - focuses the `TextEditor` with the insertion point at the end of the text,
   - installs a global click-outside monitor.
   If the panel is already visible, ⌃⌘N **hides** it instead (toggle).
3. **Typing** → SwiftUI binding updates `NoteStore.text` → debounced autosave
   (~0.6 s after the last keystroke).
4. **Dismiss** (Esc / click outside / ⌃⌘N again) → **immediate save** →
   `orderOut` → remove the click-outside monitor → focus returns to the
   previously active app.

## 5. Components (core-flow subset)

Same units and responsibilities as the parent spec §5; this round builds all of
them except `LaunchAtLogin.swift` (deferred) and only the minimal slice of the
menu.

- **`PopupNotesApp`** — SwiftUI `App`; declares the minimal `MenuBarExtra`;
  bridges to `AppDelegate` via `NSApplicationDelegateAdaptor`.
- **`AppDelegate`** — sets `.accessory` policy; constructs `NoteStore`,
  `HotKeyManager`, `PanelController`; wires the hotkey callback to
  `PanelController.toggle()`; flushes a save on terminate.
- **`HotKeyManager`** — wraps `RegisterEventHotKey` / `InstallEventHandler`;
  fixed keycode + ⌃⌘ modifiers; invokes a Swift closure on fire. Hides all
  Carbon interop behind one clean, `@MainActor` API.
- **`PanelController`** — owns panel lifecycle: lazily build `FloatingPanel`,
  host `ScratchpadView` via `NSHostingView`, position on the mouse's screen,
  `toggle()` / show / hide, click-outside monitor, Esc handling, focus the
  editor on show.
- **`FloatingPanel`** — `NSPanel` subclass: `.nonactivatingPanel`, `.floating`
  level, borderless, `.ultraThinMaterial`, rounded; `canBecomeKey = true`;
  `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`.
- **`ScratchpadView`** — SwiftUI `TextEditor` bound to `NoteStore.text`; padded;
  chromeless; placeholder when empty; forwards Esc to the controller.
- **`NoteStore`** — `@Observable`; loads the file at launch; debounced autosave
  + immediate save on hide/quit; atomic writes.

## 6. Panel details

- Style: `.nonactivatingPanel` + `.borderless`; level `.floating`;
  `.ultraThinMaterial` background with rounded corners; `hasShadow = true`.
- `canBecomeKey = true` (so the editor receives keystrokes); the panel does
  **not** activate the app (no Dock bounce, no app switch).
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]` so it appears
  over full-screen apps and on every Space.
- Fixed content size ~480×320 pt; non-resizable; long text scrolls inside.
- Positioning: center within `visibleFrame` of the `NSScreen` whose frame
  contains `NSEvent.mouseLocation`; fall back to `NSScreen.main` if none.

## 7. Editor details

- SwiftUI `TextEditor` bound to `NoteStore.text`, with internal padding and a
  material background; no title/header/footer.
- Empty state: a faint `"Jot a note…"` placeholder.
- On show: editor becomes first responder; insertion point set to the end of
  the current text. No select-all.
- Esc dismisses (forwarded to `PanelController`).

## 8. Persistence (inherited from parent §7, restated for safety)

- **Location:** `~/Library/Application Support/PopupNotes/scratchpad.md`,
  UTF-8, created on first run.
- **Atomic writes:** write a temp file then rename, so a crash mid-write can't
  corrupt the note.
- **Debounce:** autosave ~0.6 s after the last keystroke; **immediate** save on
  hide and on quit.
- **No data loss:** in-memory text is the source of truth; a failed save is
  retried on the next change and on quit. If the file cannot be **read** at
  launch, start empty and do **not** overwrite it until the user actually edits.

## 9. Highest-risk detail — focus handoff & concurrency

- **Focus handoff** is the one genuinely fiddly area: a non-activating panel
  that must still become key to receive typing, then return focus cleanly to
  the previously frontmost app on dismiss. The exact
  `NSApp.activate` / `makeKeyAndOrderFront` / first-responder / `orderOut`
  sequence will be **verified against current Apple docs and tested on real
  hardware** during implementation (consult `swiftui-expert-skill` and
  `macos-design-guidelines`). Do not write this from memory.
- **Carbon C-callback boundary:** `InstallEventHandler` calls a global C
  function that cannot capture Swift context; pass `self` via an
  `Unmanaged` pointer in `userData` and hop to `@MainActor` to invoke the
  closure. Must satisfy Swift 6 strict concurrency with no data race. Consult
  `swift-concurrency` for the safe pattern.

## 10. Testing

- **Framework:** Swift Testing (`@Test`, `#expect`).
- **Unit-testable now (likely without Xcode):** `NoteStore` and the
  `HotKeyManager` keycode/modifier **mapping** logic depend only on
  Foundation/Observation, so they should run via a SwiftPM package + `swift
  test` on the installed Command Line Tools. **To be confirmed during
  planning.** Cover: load/save round-trip, atomic-write behavior, debounce
  timing (inject a clock/scheduler + a temp directory), keycode/modifier
  mapping.
- **Needs Xcode (manual checklist):** panel show/hide, focus handoff, overlay
  reach, menu-bar items — verified by running the app (see §11).

## 11. Acceptance criteria (manual smoke test)

Runnable only after Xcode 26.5 is installed; this is the verification gate
before claiming the feature works.

1. From another app, press ⌃⌘N → panel appears centered on the mouse's screen,
   editor focused, cursor at end.
2. Type, press Esc → panel hides, focus returns to the prior app, text persists.
3. Press ⌃⌘N again → prior text is present, cursor at end.
4. Click outside the panel → it dismisses and saves.
5. Press ⌃⌘N while open → it hides (toggle).
6. Works over a full-screen app and on a secondary Space.
7. Menu bar shows the icon; *Show Scratchpad* opens the panel; *Quit* exits.
8. Quit via the menu, relaunch → text persisted.
9. Force-kill mid-edit (simulated crash) → file is not corrupted; at most the
   last ≤0.6 s of unsaved typing is lost.

## 12. Build-environment reality (must address before verification)

- This machine currently has **only Command Line Tools** (`xcode-select -p` →
  `/Library/Developer/CommandLineTools`); `xcodebuild` is unavailable. Installed
  Swift is **6.2.4**; macOS is **15.7.7**.
- The parent spec / CLAUDE.md assume **Swift 6.3 / Xcode 26.5** — those ship
  *with* Xcode, which is **not installed yet**. No contradiction; just not
  present.
- **Consequence:** the app target (`MenuBarExtra`, panel, focus handoff) cannot
  be built or run here until **Xcode 26.5** is installed. Pure-logic unit tests
  may run via SwiftPM in the meantime. Any code written before Xcode is
  installed is **unverified** — it will not be claimed to "work" until actually
  built and exercised against §11.

## 13. Open items / risks

- **Focus/activation sequence** (see §9) — highest risk; verify against docs +
  hardware.
- **`swift test` viability on CLT** for `NoteStore`/`HotKeyManager` — confirm
  early in planning; it determines whether we can TDD the core logic before
  Xcode lands.
- **Default shortcut conflict:** ⌃⌘N may collide with some apps; it is a
  one-line constant to change. Customization remains deferred (parent §12).
- **Carbon longevity:** `RegisterEventHotKey` is legacy but still the only
  native path; watch Apple release notes.
