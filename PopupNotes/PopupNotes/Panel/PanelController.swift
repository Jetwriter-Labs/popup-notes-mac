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
        // Returning focus to the prior app. A non-activating panel often returns
        // focus automatically on orderOut; if not, reactivate explicitly.
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
