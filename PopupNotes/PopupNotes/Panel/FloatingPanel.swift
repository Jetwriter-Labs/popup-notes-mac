import AppKit
import SwiftUI
import SwiftData

/// A non-activating, floating panel that hosts the notes UI. Titled + resizable
/// (with a hidden, transparent title bar) so it can be resized and have its
/// frame remembered, yet still floats over other apps on every Space and can
/// become key for text entry. Esc and ⌘W forward to `onCancel`.
final class FloatingPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onBecomeKey: (() -> Void)?

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
        // The title is never drawn, but it names the window for VoiceOver
        // and window lists.
        title = "Popup Notes"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }   // required for text entry
    override var canBecomeMain: Bool { false } // never the app's main window

    override func cancelOperation(_ sender: Any?) { onCancel?() } // Esc

    override func becomeKey() {
        super.becomeKey()
        onBecomeKey?()
    }

    /// ⌘W dismisses, like Esc. Handled here because the panel isn't
    /// `.closable`, so the menu's Close item is disabled for it. Only plain
    /// ⌘W (Caps Lock aside) — ⇧⌘W, ⌥⌘W and the rest go on as usual.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if event.type == .keyDown, modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            onCancel?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
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

extension NSView {
    /// Depth-first search of the subview tree for the first view of `type`.
    func firstDescendant<T: NSView>(ofType type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T ?? subview.firstDescendant(ofType: type) { return match }
        }
        return nil
    }
}
