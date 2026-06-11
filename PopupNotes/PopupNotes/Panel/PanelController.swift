import AppKit
import SwiftUI
import SwiftData
import PopupNotesCore

/// Owns the notes panel: builds it lazily, hosts the SwiftData-backed NotesView,
/// remembers its frame, toggles show/hide, watches for click-outside, and
/// returns focus to the prior app on dismiss.
@MainActor
final class PanelController {
    private let container: ModelContainer
    private var panel: FloatingPanel?
    private var clickMonitor: Any?
    private weak var previousApp: NSRunningApplication?

    init(container: ModelContainer) { self.container = container }

    var isVisible: Bool { panel?.isVisible ?? false }
    func toggle() { isVisible ? hide() : show() }

    func show() {
        // Already on screen (e.g. menu-bar "Show Notes" while open): re-showing
        // would re-capture previousApp and leak a second click monitor.
        guard !isVisible else { return }
        let panel = panel ?? makePanel()
        self.panel = panel
        previousApp = NSWorkspace.shared.frontmostApplication
        panel.makeKeyAndOrderFront(nil)
        installClickMonitor()
    }

    func hide() {
        guard let panel else { return }
        try? container.mainContext.save()
        removeClickMonitor()
        panel.orderOut(nil)
        previousApp?.activate()
    }

    // MARK: - Build

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 460))
        panel.contentMinSize = NSSize(width: 360, height: 220)   // allow shrinking to a compact size
        panel.onCancel = { [weak self] in self?.hide() }
        panel.setHosted(NotesView(onEscape: { [weak self] in self?.hide() }), container: container)
        panel.setFrameAutosaveName("PopupNotesPanel")
        if !panel.setFrameUsingName("PopupNotesPanel") {
            centerOnMouseScreen(panel)
        }
        return panel
    }

    private func centerOnMouseScreen(_ panel: FloatingPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                     y: visible.midY - size.height / 2))
    }

    // MARK: - Click-outside dismissal

    private func installClickMonitor() {
        // Dismiss only when the click is genuinely OUTSIDE the panel. Without this
        // guard, dragging or resizing the panel (whose title-bar mouse events the
        // global monitor also observes) would hide it mid-interaction.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel else { return }
                if !panel.frame.contains(NSEvent.mouseLocation) { self.hide() }
            }
        }
    }

    private func removeClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor); self.clickMonitor = nil }
    }
}
