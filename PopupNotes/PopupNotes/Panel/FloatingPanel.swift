import AppKit

/// A borderless, non-activating panel that floats above other apps (including
/// full-screen) on every Space, yet can become key so the editor receives keys.
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear            // SwiftUI provides the material
        hasShadow = true
        isMovableByWindowBackground = false // fixed position per spec
        hidesOnDeactivate = false
        animationBehavior = .none           // instant show/hide — snappy, no fade
    }

    override var canBecomeKey: Bool { true }   // required for text entry
    override var canBecomeMain: Bool { false } // never the app's main window
}
