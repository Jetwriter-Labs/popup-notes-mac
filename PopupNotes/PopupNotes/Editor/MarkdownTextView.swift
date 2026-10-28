import AppKit
import PopupNotesCore

/// The note editor's text view. The text is plain Markdown, styled live by
/// its `MarkdownStyler`; on top of that it draws the backgrounds of code
/// blocks, a bar beside quotes and a line for rules, and adds the keys that
/// make Markdown easy to write: Return continues a list, Tab and Shift-Tab
/// nest it, ⌘B and ⌘I wrap the selection, and a click on a task's box
/// checks it off. Toggles, as in Notion: `>` and a space start one; a click
/// on its arrow or ⌘↩ opens or closes it, ⌥⌘T all of them. The lines a
/// closed toggle folds away aren't laid out, and the caret never lands in
/// them.
final class MarkdownTextView: NSTextView {
    let styler = MarkdownStyler()
    /// Set while toggles open or close. That isn't an edit: no undo step,
    /// and the note doesn't count as changed.
    private(set) var isFolding = false
    /// Set while one of the Markdown keys makes its edit, which keeps what
    /// it wants folded — the lines a joined line skips over — folded.
    private var isApplying = false
    /// `styler.editCount` as of the last selection change. When it has moved
    /// on, the next selection change comes with an edit.
    private var selectionEditCount = 0
    /// What the latest edit changed, until the toggles over it are opened.
    private var unrevealedEdit: NSRange?
    private var revealIsScheduled = false

    /// A TextKit 2 text view with its styler attached — before any text is
    /// set, so all of it gets styled.
    static func make() -> MarkdownTextView {
        let textView = MarkdownTextView(usingTextLayoutManager: true)
        textView.textStorage?.delegate = textView.styler
        textView.textContentStorage?.delegate = textView.styler
        textView.styler.didEdit = { [weak textView] range in textView?.didEdit(range) }
        return textView
    }

    /// Replaces the whole text — a note opened, or changed from outside —
    /// with the caret at the end, or above the folded lines that hide it.
    /// Its closed toggles stay closed.
    func setText(_ string: String) {
        self.string = string
        unrevealedEdit = nil
        setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
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

    /// Typing `>` and a space at the start of a line makes it a toggle — as
    /// an undo step of its own, so ⌘Z brings back the `> ` for a quote.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        guard (string as? String ?? (string as? NSAttributedString)?.string) == " ",
              let edit = MarkdownEditing.toggleShortcut(in: styler.text, selection: selectedRange()) else { return }
        apply(edit)
    }

    override func deleteBackward(_ sender: Any?) {
        guard let edit = MarkdownEditing.deleteBackward(in: styler.text, selection: selectedRange()) else {
            super.deleteBackward(sender)
            return
        }
        apply(edit)
    }

    override func deleteForward(_ sender: Any?) {
        guard let edit = MarkdownEditing.deleteForward(in: styler.text, selection: selectedRange()) else {
            super.deleteForward(sender)
            return
        }
        apply(edit)
    }

    /// ⌘B and ⌘I; ⌘↩ and ⌥⌘T for toggles. Key equivalents go to every view
    /// in the window, so only while this view has focus.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, window?.firstResponder === self, isEditable else {
            return super.performKeyEquivalent(with: event)
        }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if modifiers == [.command, .option], key == "t" {
            let edits = MarkdownToggles.foldAll(in: styler.lines)
            guard !edits.isEmpty else { return super.performKeyEquivalent(with: event) }
            setFolds(edits)
            return true
        }
        guard modifiers == .command else { return super.performKeyEquivalent(with: event) }
        let marker: String
        switch key {
        case "b": marker = "**"
        case "i": marker = "*"
        case "\r", "\u{3}": return toggleAtCaret() || super.performKeyEquivalent(with: event)
        default: return super.performKeyEquivalent(with: event)
        }
        apply(MarkdownEditing.toggle(marker, in: styler.text, selection: selectedRange()))
        return true
    }

    /// ⌘↩, as in Notion: checks off the task on the caret's line, or opens
    /// or closes the toggle the caret is in. False when there's neither.
    private func toggleAtCaret() -> Bool {
        let caret = selectedRange().location
        if let edit = MarkdownEditing.toggleTask(in: styler.text, at: caret) {
            apply(edit)
            return true
        }
        guard let toggle = MarkdownToggles.toggle(around: caret, in: styler.lines) else { return false }
        flip(toggle)
        return true
    }

    /// A plain click on a task's box checks it off (or back on), and one on
    /// a toggle's arrow opens or closes it — without moving the caret.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 1, isEditable,
           event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty {
            if let box = taskBox(at: point), let edit = MarkdownEditing.toggleTask(in: styler.text, at: box.location) {
                apply(edit)
                return
            }
            if let toggle = toggleArrow(at: point) {
                flip(toggle)
                return
            }
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

    /// The toggle whose arrow — its marker and the space after it — is at
    /// `point`.
    private func toggleArrow(at point: NSPoint) -> Int? {
        let index = characterIndexForInsertion(at: point)
        guard let lineIndex = MarkdownBlocks.lineIndex(containing: index, in: styler.lines) else { return nil }
        let line = styler.lines[lineIndex]
        guard case .toggle = line.block, let marker = line.marker,
              let rect = boundingRect(for: NSRange(location: marker.location,
                                                   length: NSMaxRange(line.prefix) - marker.location)) else { return nil }
        return rect.insetBy(dx: -4, dy: 0).contains(point) ? lineIndex : nil
    }

    /// Makes an edit the way typing would — undoable, with the delegate
    /// told — but as an undo step of its own: NSTextView would otherwise
    /// fold it into the typing before it, and ⌘Z after ⌘B would take the
    /// typing away too.
    func apply(_ edit: MarkdownEdit) {
        if edit.range.length > 0 || !edit.replacement.isEmpty {
            isApplying = true
            defer { isApplying = false }
            breakUndoCoalescing() // before shouldChangeText, which registers the undo
            guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
            textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
            didChangeText()
            breakUndoCoalescing()
        }
        if let selection = edit.selection {
            // Never into folded lines: Tab can move a line under a closed toggle.
            revealFolds(covering: selection)
            setSelectedRange(selection)
            scrollRangeToVisible(selection)
        }
    }

    // MARK: - Toggles

    /// Opens toggle `index` if it's closed, or closes it.
    private func flip(_ index: Int) {
        guard case .toggle(let isOpen) = styler.lines[index].block,
              let edit = MarkdownToggles.fold(index, open: !isOpen, in: styler.lines) else { return }
        setFolds([edit])
    }

    /// Opens or closes toggles by swapping their markers. That isn't an
    /// edit: there is no undo step — the markers keep their length, so the
    /// undo history still lines up — and the note doesn't count as
    /// changed. A selection a closing toggle folds away moves up to its
    /// title.
    func setFolds(_ edits: [MarkdownEdit]) {
        guard !edits.isEmpty, let storage = textStorage else { return }
        let selection = selectedRange()
        isFolding = true
        undoManager?.disableUndoRegistration()
        defer {
            undoManager?.enableUndoRegistration()
            isFolding = false
        }
        breakUndoCoalescing()
        guard shouldChangeText(inRanges: edits.map { NSValue(range: $0.range) },
                               replacementStrings: edits.map(\.replacement)) else { return }
        storage.beginEditing()
        for edit in edits { storage.replaceCharacters(in: edit.range, with: edit.replacement) }
        storage.endEditing()
        didChangeText()
        let start = MarkdownToggles.visibleLocation(selection.location, forward: false, in: styler.lines)
        let end = MarkdownToggles.visibleLocation(NSMaxRange(selection), forward: false, in: styler.lines)
        let visible = NSRange(location: start, length: max(0, end - start))
        setSelectedRange(visible)
        if visible != selection { scrollRangeToVisible(visible) }
    }

    /// Opens the closed toggles over either end of each range.
    private func revealFolds(covering ranges: NSRange...) {
        let lines = styler.lines
        let length = textStorage?.length ?? 0
        var edits: [MarkdownEdit] = []
        for range in ranges {
            for location in [range.location, NSMaxRange(range)] where location <= length {
                guard let index = MarkdownBlocks.lineIndex(containing: location, in: lines),
                      lines[index].isHidden else { continue }
                for edit in MarkdownToggles.reveal(index, in: lines) where !edits.contains(edit) { edits.append(edit) }
            }
        }
        setFolds(edits)
    }

    /// Nothing an edit changes stays folded away — say ⌘Z brings back text
    /// inside a closed toggle, or a typed tab moves a line under one: once
    /// the edit is done, the toggles over it, and over the caret, open.
    /// (The Markdown keys' own edits see to that themselves, in `apply`.)
    private func didEdit(_ range: NSRange) {
        guard !isFolding, !isApplying else { return }
        unrevealedEdit = range
        guard !revealIsScheduled else { return }
        revealIsScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            revealIsScheduled = false
            let edit = unrevealedEdit
            unrevealedEdit = nil
            revealFolds(covering: selectedRange(), edit ?? selectedRange())
        }
    }

    // MARK: - Selection

    /// Keeps the caret out of folded lines. After an edit — typing, ⌘Z — the
    /// selection goes where the edit put it, and once the edit is done the
    /// toggles over it open (see `didEdit`). Any other move — arrow keys, a
    /// click past the end, code — steps over the folded lines instead:
    /// forward to the line below them, back to the toggle's title.
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        let afterEdit = styler.editCount != selectionEditCount
        selectionEditCount = styler.editCount
        guard !afterEdit else {
            super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
            return
        }
        let lines = styler.lines
        let old = selectedRange()
        let visible = ranges.map { value -> NSValue in
            let range = value.rangeValue
            guard range.length > 0 else {
                let forward = range.location > old.location
                return NSValue(range: NSRange(location: MarkdownToggles.visibleLocation(range.location, forward: forward,
                                                                                         in: lines), length: 0))
            }
            let start = MarkdownToggles.visibleLocation(range.location, forward: false, in: lines)
            var end = MarkdownToggles.visibleLocation(NSMaxRange(range), forward: true, in: lines)
            // Nothing shows below the folded lines: select through to the end.
            if end < NSMaxRange(range) { end = textStorage?.length ?? end }
            return NSValue(range: NSRange(location: start, length: end - start))
        }
        super.setSelectedRanges(visible, affinity: affinity, stillSelecting: stillSelecting)
    }

    // MARK: - Navigation

    /// Brings a heading to the top of the editor with the caret at the end
    /// of its line, so typing continues right there — opening the toggles
    /// it's folded away in.
    func reveal(_ heading: NSRange) {
        revealFolds(covering: NSRange(location: heading.location, length: 0))
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

            // Inside a toggle, a block starts where the toggle's lines do.
            let indent = decoration == nil ? 0 : toggleIndent(at: offset)
            let left = origin.x + indent
            let width = container.size.width - indent
            switch decoration {
            case .code:
                let line = NSRect(x: left, y: frame.minY, width: width, height: frame.height)
                codeBlock = codeBlock?.union(line) ?? line
            case .quote:
                theme.quoteBar.setFill()
                // A quote in a toggle starts right at its lines' indent: the bar goes before it.
                let barLeft = origin.x + max(0, indent - theme.quoteInset)
                let bar = NSRect(x: barLeft + container.lineFragmentPadding, y: frame.minY + 1,
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

    /// Where the toggle holding the line at `offset` starts its lines; 0
    /// outside toggles.
    private func toggleIndent(at offset: Int) -> CGFloat {
        let lines = styler.lines
        guard let index = MarkdownBlocks.lineIndex(containing: offset, in: lines),
              let toggle = MarkdownToggles.parent(of: index, in: lines) else { return 0 }
        return theme.toggleContentIndent(prefix: styler.text.string(in: lines[toggle].prefix))
    }
}
