import AppKit
import SwiftUI
import SwiftData
import PopupNotesCore

/// Owns the notes panel: builds it (lazily, or ahead of time after a login
/// launch), hosts the SwiftData-backed NotesView, remembers its frame and
/// follows the user's display, toggles show/hide, watches for click-outside,
/// and returns focus to the prior app on dismiss.
@MainActor
final class PanelController {
    private static let frameName = "PopupNotesPanel"

    private let container: ModelContainer
    private var panel: FloatingPanel?
    private var clickMonitor: Any?
    private weak var previousApp: NSRunningApplication?
    /// True from "make the panel key" until it actually becomes key. AppKit
    /// may grant key a beat later, or not at all while an app-modal session
    /// (an open/save panel) runs — toggle() must not mistake that for a panel
    /// the user left, or the hotkey could never dismiss it.
    private var awaitingKey = false

    init(container: ModelContainer) {
        self.container = container
        let center = NotificationCenter.default
        // queue nil: delivered synchronously on the posting (main) thread.
        // ⌘H, "Hide Others" or a window manager hid the whole app — and the
        // panel with it — without going through hide().
        _ = center.addObserver(forName: NSApplication.didHideNotification, object: nil, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.appDidHide() }
        }
        _ = center.addObserver(forName: .popupNotesWillOpenSettings, object: nil, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideForSettings() }
        }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// The hotkey. Hides the panel while the user is in it; if it is up but
    /// unfocused (they ⌘-Tabbed away), brings them back into it instead.
    func toggle() {
        guard let panel, panel.isVisible else { show(); return }
        if panel.isKeyWindow || awaitingKey || panel.attachedSheet != nil || NSApp.modalWindow != nil {
            hide()
        } else {
            // The hotkey never activates this app, so the frontmost app is
            // where the user is now — that's where Esc should return them.
            previousApp = NSWorkspace.shared.frontmostApplication
            makeKey(panel)
        }
    }

    /// Puts the panel in front of the user: shows it when hidden, re-keys it
    /// when it is already on screen. Every "open the notes" request that is
    /// not a toggle goes through here — `show()` alone returns silently when
    /// the panel is already up, which makes such a request look ignored.
    func activate() {
        if let panel, panel.isVisible {
            makeKey(panel)
        } else {
            show()
        }
    }

    func show() {
        // Already on screen (e.g. menu-bar "Show Notes" while open): re-showing
        // would re-capture previousApp and leak a second click monitor.
        guard !isVisible else { return }
        let panel = panel ?? makePanel()
        self.panel = panel
        previousApp = NSWorkspace.shared.frontmostApplication
        restoreFrameOnFirstShow(panel)
        moveToMouseScreenIfNeeded(panel)
        // Ordering a window front would unhide a hidden app (after ⌘H) AND
        // activate it; this unhides without stealing activation.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        makeKey(panel)
        installClickMonitor()
    }

    /// `restoringFocus: false` when the user already chose where focus goes
    /// (they clicked another app) or Settings is taking it.
    func hide(restoringFocus: Bool = true) {
        guard let panel, panel.isVisible else { return }
        awaitingKey = false
        removeClickMonitor()
        panel.orderOut(nil)
        // Not while an open/save panel is up: activating the previous app
        // would bury it.
        if restoringFocus && NSApp.modalWindow == nil { previousApp?.activate() }
        // After orderOut, so the panel vanishes without waiting on disk I/O.
        container.mainContext.saveLoggingErrors("hiding the panel")
    }

    /// Builds the panel offscreen so the first show doesn't pay for it
    /// (~100–300 ms of SwiftUI layout). Never orders it in, never touches
    /// focus, and never writes the saved frame — displays may still be
    /// settling right after login, so `restoreFrameOnFirstShow` applies it.
    func prewarm() {
        guard panel == nil else { return }
        let panel = makePanel()
        self.panel = panel
        // Reading the saved frame (no autosave name yet, so nothing is
        // written) lets the offscreen layout run at the size it will open at.
        if !panel.setFrameUsingName(Self.frameName) { centerOnMouseScreen(panel) }
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    // MARK: - Focus

    private func makeKey(_ panel: FloatingPanel) {
        awaitingKey = !panel.isKeyWindow // becomeKey clears it, possibly within the next call
        panel.makeKeyAndOrderFront(nil)
        focusEditorIfNeeded(in: panel)
    }

    /// Hotkey-then-type must always land in the note: if focus was left in
    /// the sidebar (or fell back to the window after a note switch), move it
    /// to the editor. The caret stays where it was.
    private func focusEditorIfNeeded(in panel: FloatingPanel) {
        guard panel.attachedSheet == nil, !(panel.firstResponder is NSTextView),
              let editor = panel.contentView?.firstDescendant(ofType: NSTextView.self),
              editor.isEditable else { return }
        panel.makeFirstResponder(editor)
        editor.scrollRangeToVisible(editor.selectedRange())
    }

    // MARK: - Dismissal from outside

    /// Settings is about to open: get the floating panel out of its way (it
    /// would cover the Settings window). No focus hand-back — Settings takes
    /// it. Left alone while the delete confirmation is up on it.
    private func hideForSettings() {
        guard let panel, panel.attachedSheet == nil else { return }
        hide(restoringFocus: false)
    }

    /// The app was hidden. `isVisible` is already false here, so this cleans
    /// up directly instead of going through hide(). Ordering out also keeps a
    /// later unhide from bringing back a stale, unmonitored panel.
    private func appDidHide() {
        guard let panel else { return }
        awaitingKey = false
        removeClickMonitor()
        panel.orderOut(nil)
        container.mainContext.saveLoggingErrors("app hidden")
    }

    // MARK: - Build & placement

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 460))
        panel.contentMinSize = NSSize(width: 360, height: 220)   // allow shrinking to a compact size
        panel.onCancel = { [weak self] in self?.hide() }
        panel.onBecomeKey = { [weak self] in self?.awaitingKey = false }
        panel.setHosted(NotesView(onEscape: { [weak self] in self?.hide() }), container: container)
        return panel
    }

    private func restoreFrameOnFirstShow(_ panel: FloatingPanel) {
        guard panel.frameAutosaveName.isEmpty else { return }
        panel.setFrameAutosaveName(Self.frameName)
        if !panel.setFrameUsingName(Self.frameName) {
            centerOnMouseScreen(panel)
        }
    }

    /// Spotlight-style: the panel opens on the display the user is working
    /// on. If it sits on another display — or on one that's been unplugged —
    /// center it on the mouse's display, shrunk to fit if needed. On the same
    /// display the user's position and size are left alone.
    private func moveToMouseScreenIfNeeded(_ panel: FloatingPanel) {
        guard let screen = Self.mouseScreen() else { return }
        let frame = panel.frame
        guard !screen.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) else { return }
        let visible = screen.visibleFrame
        let size = NSSize(width: min(frame.width, visible.width), height: min(frame.height, visible.height))
        panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                              width: size.width, height: size.height), display: false)
    }

    private func centerOnMouseScreen(_ panel: FloatingPanel) {
        guard let visible = Self.mouseScreen()?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                     y: visible.midY - size.height / 2))
    }

    /// The screen under the mouse. NSMouseInRect (unlike NSRect.contains)
    /// includes the top edge, where the mouse sits right after a menu-bar click.
    private static func mouseScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    // MARK: - Click-outside dismissal

    private func installClickMonitor() {
        removeClickMonitor() // never leak a second monitor
        // Dismiss only when the click is genuinely OUTSIDE the panel. Without this
        // guard, dragging or resizing the panel (whose title-bar mouse events the
        // global monitor also observes) would hide it mid-interaction.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard let panel = self.panel, panel.isVisible else { self.removeClickMonitor(); return }
                // The click already chose (and activated) where the user is
                // going; handing focus back to the previous app would yank it.
                if !panel.frame.contains(NSEvent.mouseLocation) { self.hide(restoringFocus: false) }
            }
        }
    }

    private func removeClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor); self.clickMonitor = nil }
    }
}
