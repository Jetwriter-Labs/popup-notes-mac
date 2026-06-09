import AppKit
import SwiftUI
import SwiftData

/// A non-activating, floating panel that hosts the notes UI. Titled + resizable
/// (with a hidden, transparent title bar) so it can be resized and have its
/// frame remembered, yet still floats over other apps on every Space and can
/// become key for text entry. Esc forwards to `onCancel`.
final class FloatingPanel: NSPanel {
    var onCancel: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        animationBehavior = .none           // instant show/hide — snappy, no fade

        // Chromeless-but-resizable: hide the title and traffic-light buttons.
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }   // required for text entry
    override var canBecomeMain: Bool { false } // never the app's main window

    override func cancelOperation(_ sender: Any?) { onCancel?() } // Esc
}

extension FloatingPanel {
    /// Hosts a SwiftUI view as the panel's content, injecting the SwiftData
    /// container and resizing with the window.
    func setHosted(_ view: some View, container: ModelContainer) {
        let host = NSHostingView(rootView: view.modelContainer(container))
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        contentView = host
    }
}
