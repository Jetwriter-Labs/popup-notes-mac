import AppKit
import PopupNotesCore

/// The note editor's text view. The text is plain Markdown, styled live by
/// its `MarkdownStyler`; on top of that it draws the backgrounds of code
/// blocks, a bar beside quotes and a line for rules, and adds the keys that
/// make Markdown easy to write: Return continues a list, Tab and Shift-Tab
/// nest it, ⌘B and ⌘I wrap the selection, and a click on a task's box
/// checks it off.
final class MarkdownTextView: NSTextView {
    let styler = MarkdownStyler()

    /// A TextKit 2 text view with its styler attached — before any text is
    /// set, so all of it gets styled.
    static func make() -> MarkdownTextView {
        let textView = MarkdownTextView(usingTextLayoutManager: true)
        textView.textStorage?.delegate = textView.styler
        return textView
    }

    private var theme: MarkdownTheme { styler.theme }

    // MARK: - Keys

    override func insertNewline(_ sender: Any?) {
        guard let edit = MarkdownEditing.newline(in: styler.text, selection: selectedRange()) else {
            super.insertNewline(sender)
            return
        }
        apply(edit)
    }

    override func insertTab(_ sender: Any?) {
        guard let edit = MarkdownEditing.indentation(in: styler.text, selection: selectedRange(), outdent: false) else {
            super.insertTab(sender)
            return
        }
        apply(edit)
    }

    override func insertBacktab(_ sender: Any?) {
        guard let edit = MarkdownEditing.indentation(in: styler.text, selection: selectedRange(), outdent: true) else {
            super.insertBacktab(sender)
            return
        }
        apply(edit)
    }

    /// ⌘B and ⌘I. Key equivalents go to every view in the window, so only
    /// while this view has focus.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, window?.firstResponder === self, isEditable,
              event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        let marker: String
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "b": marker = "**"
        case "i": marker = "*"
        default: return super.performKeyEquivalent(with: event)
        }
        apply(MarkdownEditing.toggle(marker, in: styler.text, selection: selectedRange()))
        return true
    }

    /// A plain click on a task's box checks it off (or back on) without
    /// moving the caret.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 1, isEditable,
           event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
           let box = taskBox(at: point),
           let edit = MarkdownEditing.toggleTask(in: styler.text, at: box.location) {
            apply(edit)
            return
        }
        super.mouseDown(with: event)
    }

    private func taskBox(at point: NSPoint) -> NSRange? {
        let index = characterIndexForInsertion(at: point)
        guard let lineIndex = MarkdownBlocks.lineIndex(containing: index, in: styler.lines),
              let box = styler.lines[lineIndex].taskBox,
              let rect = boundingRect(for: box) else { return nil }
        return rect.insetBy(dx: -2, dy: -2).contains(point) ? box : nil
    }

    /// Makes an edit the way typing would — undoable, with the delegate
    /// told — but as an undo step of its own: NSTextView would otherwise
    /// fold it into the typing before it, and ⌘Z after ⌘B would take the
    /// typing away too.
    func apply(_ edit: MarkdownEdit) {
        if edit.range.length > 0 || !edit.replacement.isEmpty {
            breakUndoCoalescing() // before shouldChangeText, which registers the undo
            guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
            textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
            didChangeText()
            breakUndoCoalescing()
        }
        if let selection = edit.selection {
            setSelectedRange(selection)
            scrollRangeToVisible(selection)
        }
    }

    // MARK: - Navigation

    /// Brings a heading to the top of the editor with the caret at the end
    /// of its line, so typing continues right there.
    func reveal(_ heading: NSRange) {
        window?.makeFirstResponder(self)
        let caret = NSRange(location: NSMaxRange(heading), length: 0)
        setSelectedRange(caret)
        guard let scrollView = enclosingScrollView, let lineRect = boundingRect(for: heading, exact: true) else {
            scrollRangeToVisible(caret)
            return
        }
        let clipView = scrollView.contentView
        let top = NSPoint(x: clipView.bounds.minX, y: lineRect.minY - textContainerOrigin.y)
        let target = clipView.constrainBoundsRect(NSRect(origin: top, size: clipView.bounds.size)).origin
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            clipView.scroll(to: target)
            scrollView.reflectScrolledClipView(clipView)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                clipView.animator().setBoundsOrigin(target)
            }
        }
    }

    /// The lines on screen, as a character range. Whole lines: one that is
    /// only partly visible counts.
    func visibleCharacterRange() -> NSRange {
        guard let layoutManager = textLayoutManager, let content = layoutManager.textContentManager else {
            return NSRange(location: 0, length: 0)
        }
        let length = textStorage?.length ?? 0
        func fragment(atY y: CGFloat) -> NSRange? {
            // Clamped: a point in the inset above the first line still means the first line.
            let point = CGPoint(x: 0, y: max(0, y - textContainerOrigin.y))
            guard let fragment = layoutManager.textLayoutFragment(for: point) else { return nil }
            let start = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
            let end = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.endLocation)
            return NSRange(location: start, length: end - start)
        }
        let visible = visibleRect
        let top = fragment(atY: visible.minY)?.location ?? 0
        let bottom = fragment(atY: visible.maxY).map(NSMaxRange) ?? length
        return NSRange(location: top, length: max(0, bottom - top))
    }

    /// The rect of `range` in this view's coordinates. `exact` lays out
    /// everything above it first: TextKit 2 estimates the height of text it
    /// hasn't laid out yet, which is fine for drawing but would make a jump
    /// land in the wrong place.
    func boundingRect(for range: NSRange, exact: Bool = false) -> NSRect? {
        guard let layoutManager = textLayoutManager, let content = layoutManager.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: range.location),
              let end = content.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end) else { return nil }
        if exact, let above = NSTextRange(location: content.documentRange.location, end: end) {
            layoutManager.ensureLayout(for: above)
        }
        var union: NSRect?
        layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            union = union?.union(frame) ?? frame
            return true
        }
        return union?.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    // MARK: - Block backgrounds

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawDecorations(in: rect)
    }

    /// Code blocks get a rounded background, quotes a bar at their left and
    /// rules a hairline — painted behind the text, line by line, for the
    /// lines on screen. The styler marks which lines they are.
    private func drawDecorations(in rect: NSRect) {
        guard let layoutManager = textLayoutManager, let content = layoutManager.textContentManager,
              let storage = textStorage, storage.length > 0, let container = textContainer else { return }
        let origin = textContainerOrigin
        let firstVisible = layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: max(0, rect.minY - origin.y)))
        var codeBlock: NSRect?
        func finishCodeBlock() {
            guard let block = codeBlock else { return }
            theme.codeBackground.setFill()
            NSBezierPath(roundedRect: block, xRadius: 6, yRadius: 6).fill()
            codeBlock = nil
        }

        layoutManager.enumerateTextLayoutFragments(from: firstVisible?.rangeInElement.location
                                                   ?? layoutManager.documentRange.location,
                                                   options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame.offsetBy(dx: origin.x, dy: origin.y)
            guard frame.minY <= rect.maxY else { return false }
            let offset = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
            let raw = offset < storage.length
                ? storage.attribute(.markdownDecoration, at: offset, effectiveRange: nil) as? Int : nil
            let decoration = raw.flatMap(MarkdownTheme.Decoration.init(rawValue:))
            if decoration != .code { finishCodeBlock() }

            let left = origin.x
            let width = container.size.width
            switch decoration {
            case .code:
                let line = NSRect(x: left, y: frame.minY, width: width, height: frame.height)
                codeBlock = codeBlock?.union(line) ?? line
            case .quote:
                theme.quoteBar.setFill()
                let bar = NSRect(x: left + container.lineFragmentPadding, y: frame.minY + 1,
                                 width: 3, height: frame.height - 2)
                NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
            case .rule:
                theme.ruleColor.setFill()
                let pad = container.lineFragmentPadding
                NSRect(x: left + pad, y: frame.midY.rounded(.down), width: width - 2 * pad, height: 1).fill()
            case nil:
                break
            }
            return true
        }
        finishCodeBlock()
    }
}
