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
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        // Caret at end, focused, once the view is in a window.
        let end = NSRange(location: (text as NSString).length, length: 0)
        textView.setSelectedRange(end)
        Task { @MainActor in
            textView.window?.makeFirstResponder(textView)
            textView.scrollRangeToVisible(end)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Only overwrite when the model genuinely diverged (e.g. import), so we
        // never clobber the user's caret/selection while they type.
        if textView.string != text { textView.string = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
