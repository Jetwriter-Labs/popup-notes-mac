import SwiftUI
import AppKit

/// A lightweight `NSTextView`-backed plain-text editor.
///
/// SwiftUI's `TextEditor` has a fixed internal inset we can't tighten; wrapping
/// `NSTextView` lets us set a small `textContainerInset` (so text starts right
/// under the toolbar) and place the caret at the end with focus when a note is
/// shown. The detail view is re-created per selection (`.id(note.id)`), so
/// `makeNSView` runs once per note — caret-at-end therefore applies on each
/// selection, not just first launch.
struct NoteTextEditor: NSViewRepresentable {
    @Binding var text: String
    /// Changing it puts keyboard focus in the editor (caret kept) — for when
    /// no new editor is created to take focus itself.
    var focusRequest = 0
    /// False when the user is working in the sidebar and must keep its focus.
    var takesFocusOnAppear = true

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .preferredFont(forTextStyle: .body)
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 6) // tight top/leading padding
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.scrollerStyle = .overlay      // prefer the thin floating style
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true     // only appears while scrolling
        scrollView.verticalScroller = MinimalScroller() // stay thin even if the system pref is "Always"
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        // SwiftUI already lays the editor out below the toolbar; without this the
        // scroll view ALSO insets for the title bar (.fullSizeContentView),
        // double-counting the toolbar height as a large top gap.
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets()

        // Caret at end, focused, once the view is in a window.
        let end = NSRange(location: (text as NSString).length, length: 0)
        textView.setSelectedRange(end)
        if takesFocusOnAppear {
            Task { @MainActor in
                textView.window?.makeFirstResponder(textView)
                textView.scrollRangeToVisible(end)
            }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Only overwrite when the model genuinely diverged (e.g. import), so we
        // never clobber the user's caret/selection while they type. That
        // replacement isn't undoable, and the earlier undo entries now point
        // at ranges that may not exist (⌘Z would throw), so drop them.
        if textView.string != text {
            textView.string = text
            context.coordinator.undoManager.removeAllActions()
        }
        if focusRequest != context.coordinator.focusRequest {
            context.coordinator.focusRequest = focusRequest
            Task { @MainActor in textView.window?.makeFirstResponder(textView) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, focusRequest: focusRequest) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        var focusRequest: Int
        /// This editor's own undo history. Without it every editor shares the
        /// panel window's undo manager, so ⌘Z could reach into the history of
        /// notes viewed earlier.
        let undoManager = UndoManager()

        init(text: Binding<String>, focusRequest: Int) {
            self.text = text
            self.focusRequest = focusRequest
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        func undoManager(for view: NSTextView) -> UndoManager? { undoManager }
    }
}

/// A deliberately thin scroller: a narrow track and no slot background, so the
/// editor shows only a subtle knob regardless of the system "Show scroll bars"
/// setting (which would otherwise force the wide legacy scroller).
final class MinimalScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override class func scrollerWidth(for controlSize: NSControl.ControlSize,
                                      scrollerStyle: NSScroller.Style) -> CGFloat {
        8
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // Intentionally empty — no track background.
    }
}
