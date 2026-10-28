import SwiftUI
import AppKit
import PopupNotesCore

/// A lightweight `NSTextView`-backed editor for a note's Markdown.
///
/// SwiftUI's `TextEditor` has a fixed internal inset we can't tighten; wrapping
/// `NSTextView` lets us set a small `textContainerInset` (so text starts right
/// under the toolbar) and place the caret at the end with focus when a note is
/// shown. The detail view is re-created per selection (`.id(note.id)`), so
/// `makeNSView` runs once per note — caret-at-end therefore applies on each
/// selection, not just first launch. The text view styles the Markdown as
/// it's typed (see `MarkdownTextView`) and keeps `outline` current.
struct NoteTextEditor: NSViewRepresentable {
    @Binding var text: String
    /// Called after each edit — not when a toggle opens or closes, which
    /// changes the text but isn't an edit.
    var onEdit: () -> Void = {}
    /// Changing it puts keyboard focus in the editor (caret kept) — for when
    /// no new editor is created to take focus itself.
    var focusRequest = 0
    /// False when the user is working in the sidebar and must keep its focus.
    var takesFocusOnAppear = true
    /// Kept up to date with the note's headings; its jumps scroll this editor.
    var outline: NoteOutline?

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownTextView.make()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .preferredFont(forTextStyle: .body)
        textView.typingAttributes = textView.styler.theme.baseAttributes
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 6) // tight top/leading padding
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

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

        context.coordinator.attach(textView, in: scrollView, outline: outline)
        // Styled as it goes in; caret at the end (or above folded lines there).
        textView.setText(text)

        // Focused, once the view is in a window.
        if takesFocusOnAppear {
            Task { @MainActor in
                textView.window?.makeFirstResponder(textView)
                textView.scrollRangeToVisible(textView.selectedRange())
            }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        context.coordinator.onEdit = onEdit
        // Only overwrite when the model genuinely diverged (e.g. import), so we
        // never clobber the user's caret/selection while they type. That
        // replacement isn't undoable, and the earlier undo entries now point
        // at ranges that may not exist (⌘Z would throw), so drop them.
        if textView.string != text {
            textView.setText(text)
            context.coordinator.undoManager.removeAllActions()
        }
        if focusRequest != context.coordinator.focusRequest {
            context.coordinator.focusRequest = focusRequest
            Task { @MainActor in textView.window?.makeFirstResponder(textView) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, onEdit: onEdit, focusRequest: focusRequest) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        var onEdit: () -> Void
        var focusRequest: Int
        /// This editor's own undo history. Without it every editor shares the
        /// panel window's undo manager, so ⌘Z could reach into the history of
        /// notes viewed earlier.
        let undoManager = UndoManager()
        private weak var textView: MarkdownTextView?
        private var outline: NoteOutline?
        private var outlineUpdateScheduled = false

        init(text: Binding<String>, onEdit: @escaping () -> Void, focusRequest: Int) {
            self.text = text
            self.onEdit = onEdit
            self.focusRequest = focusRequest
        }

        func attach(_ textView: MarkdownTextView, in scrollView: NSScrollView, outline: NoteOutline?) {
            self.textView = textView
            self.outline = outline
            textView.styler.didRestyle = { [weak self, weak textView] decorationsChanged in
                // Code blocks, quotes and rules are drawn behind the text,
                // outside the lines TextKit redraws for an edit.
                if decorationsChanged { textView?.needsDisplay = true }
                self?.scheduleOutlineUpdate()
            }
            guard let outline else { return }
            outline.revealHeading = { [weak textView] heading in textView?.reveal(heading.range) }
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(editorDidScroll),
                                                   name: NSView.boundsDidChangeNotification,
                                                   object: scrollView.contentView)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView else { return }
            text.wrappedValue = textView.string
            if !textView.isFolding { onEdit() }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            // NSTextView types with the attributes of the text before the
            // caret — a heading's, on the empty line under it. The styler
            // restyles whatever is typed anyway; this keeps the caret sized
            // for body text.
            textView.typingAttributes = textView.styler.theme.baseAttributes
            updateCurrentSection()
        }

        func undoManager(for view: NSTextView) -> UndoManager? { undoManager }

        @objc private func editorDidScroll(_ notification: Notification) {
            updateCurrentSection()
        }

        /// Once per batch of edits, after the text storage has settled
        /// (the restyle runs mid-edit, too early to ask for layout).
        private func scheduleOutlineUpdate() {
            guard outline != nil, !outlineUpdateScheduled else { return }
            outlineUpdateScheduled = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                outlineUpdateScheduled = false
                guard let textView, let outline else { return }
                outline.update(headings: MarkdownOutline.headings(in: textView.styler.lines, of: textView.styler.text))
                updateCurrentSection()
            }
        }

        /// The section around the caret — or, with the caret scrolled out of
        /// view, the one at the top of the editor.
        private func updateCurrentSection() {
            guard let textView, let outline else { return }
            guard !outline.headings.isEmpty else { outline.update(current: nil); return }
            let visible = textView.visibleCharacterRange()
            let caret = textView.selectedRange().location
            let caretIsVisible = caret >= visible.location && caret <= NSMaxRange(visible)
            let location = caretIsVisible ? caret : visible.location
            outline.update(current: MarkdownOutline.section(containing: location, in: outline.headings))
        }
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
