import AppKit
import PopupNotesCore

/// Live Markdown styling for the note editor. The text itself stays plain
/// Markdown — that's what is saved and exported — and this only sets how it
/// looks. After every edit it re-reads the note's lines (cheap: only line
/// starts are inspected) and restyles just the lines the edit touched, plus
/// any elsewhere whose meaning changed with it, as when typing ``` turns
/// the lines below into code, or closing a toggle folds its lines away.
/// Folded lines are marked, and — as the text content storage's delegate —
/// it keeps TextKit from laying them out.
final class MarkdownStyler: NSObject {
    let theme: MarkdownTheme
    /// The note's lines as of the last edit.
    private(set) var lines: [MarkdownLine] = []
    private(set) var text = MarkdownText("")
    /// How many edits have been restyled: the text view tells a selection
    /// change that comes with an edit from one that doesn't by it.
    private(set) var editCount = 0
    /// After each restyle; `true` when a code block, quote or rule (whose
    /// backgrounds the text view draws) appeared, changed or went away, or
    /// lines were folded away or came back.
    var didRestyle: ((_ decorationsChanged: Bool) -> Void)?
    /// After each edit — typed, undone, made in code — with the range it
    /// changed. The text view's own hook; `didRestyle` is its owner's.
    var didEdit: ((_ editedRange: NSRange) -> Void)?

    init(theme: MarkdownTheme = .shared) {
        self.theme = theme
    }

    private func restyle(_ storage: NSTextStorage, editedRange: NSRange, delta: Int) {
        let text = MarkdownText(storage.mutableString)
        let lines = MarkdownBlocks.lines(in: text)
        let (changed, decorationsChanged) = changedLines(lines, editedRange: editedRange, delta: delta)
        storage.beginEditing()
        for index in changed { style(lines[index], of: text, in: storage) }
        storage.endEditing()
        self.lines = lines
        self.text = text
        editCount += 1
        didEdit?(editedRange)
        didRestyle?(decorationsChanged)
    }

    /// Every line the edit touched, and elsewhere, any line whose kind
    /// changed (a fence opened or closed above it) or that was folded away
    /// or came back. Lines are compared with the last edit's: before the
    /// edit, the text is the same; past it, the same but shifted by `delta`.
    private func changedLines(_ new: [MarkdownLine], editedRange: NSRange,
                              delta: Int) -> (indices: [Int], decorationsChanged: Bool) {
        let old = lines
        guard !old.isEmpty else { return (Array(new.indices), true) }
        let editEnd = NSMaxRange(editedRange)
        var changed: [Int] = []
        var decorationsChanged = false
        // What the edit replaced, in the old text.
        let oldEditEnd = editEnd - delta
        decorationsChanged = old.contains {
            $0.block.isDecorated && $0.range.location <= oldEditEnd && NSMaxRange($0.fullRange) >= editedRange.location
        }
        var o = 0
        for (index, line) in new.enumerated() {
            if NSMaxRange(line.fullRange) < editedRange.location {
                // Blank lines above the edit go with the line below them.
                if index < old.count, old[index].isHidden != line.isHidden {
                    changed.append(index)
                    decorationsChanged = true
                }
                continue
            }
            if line.range.location <= editEnd {
                changed.append(index)
                decorationsChanged = decorationsChanged || line.block.isDecorated
                continue
            }
            let oldStart = line.range.location - delta
            while o < old.count, old[o].range.location < oldStart { o += 1 }
            let matches = o < old.count && old[o].range.location == oldStart
            if matches, old[o].block == line.block, old[o].isHidden == line.isHidden { continue }
            changed.append(index)
            decorationsChanged = decorationsChanged || line.block.isDecorated
                || (o < old.count && old[o].block.isDecorated) || (matches && old[o].isHidden != line.isHidden)
        }
        return (changed, decorationsChanged)
    }

    private func style(_ line: MarkdownLine, of text: MarkdownText, in storage: NSTextStorage) {
        let full = line.fullRange
        guard full.length > 0 else { return } // the empty last line: typing attributes cover it

        var attributes = theme.baseAttributes
        var size = theme.bodyFont.pointSize
        var weight = NSFont.Weight.regular
        var toggleKern: CGFloat = 0
        switch line.block {
        case .blank:
            attributes[.paragraphStyle] = theme.blankParagraphStyle
        case .paragraph, .listItem:
            break
        case .toggle:
            let indent = theme.toggleTitleIndent(prefix: text.string(in: line.prefix))
            toggleKern = indent.kern
            attributes[.paragraphStyle] = indent.paragraphStyle
        case .heading(let level):
            let font = theme.headingFont(level: level)
            size = font.pointSize
            weight = level <= 2 ? .bold : .semibold
            attributes[.font] = font
            attributes[.paragraphStyle] = theme.headingParagraphStyle(level: level, isFirstLine: line.range.location == 0)
        case .quote:
            attributes[.foregroundColor] = theme.quoteColor
            attributes[.markdownDecoration] = MarkdownTheme.Decoration.quote.rawValue
        case .fence, .code:
            attributes[.font] = theme.codeFont
            attributes[.paragraphStyle] = theme.codeParagraphStyle()
            attributes[.markdownDecoration] = MarkdownTheme.Decoration.code.rawValue
            if line.block == .fence { attributes[.foregroundColor] = theme.syntaxColor }
        case .rule:
            attributes[.foregroundColor] = theme.ruleSyntaxColor
            attributes[.markdownDecoration] = MarkdownTheme.Decoration.rule.rawValue
        }
        switch line.block {
        case .listItem:
            attributes[.paragraphStyle] = theme.hangingParagraphStyle(prefix: text.string(in: line.prefix))
        case .quote:
            attributes[.paragraphStyle] = theme.hangingParagraphStyle(prefix: text.string(in: line.prefix),
                                                                      firstLineIndent: theme.quoteInset)
        default:
            break
        }
        if line.isHidden { attributes[.markdownHidden] = true }
        storage.setAttributes(attributes, range: full)

        switch line.block {
        case .heading:
            if let marker = line.marker { storage.addAttribute(.foregroundColor, value: theme.syntaxColor, range: marker) }
            if let closing = line.closingSequence {
                storage.addAttribute(.foregroundColor, value: theme.syntaxColor, range: closing)
            }
        case .listItem(let item):
            if let marker = line.marker { storage.addAttribute(.foregroundColor, value: theme.listMarkerColor, range: marker) }
            if let box = line.taskBox { storage.addAttribute(.foregroundColor, value: theme.syntaxColor, range: box) }
            if item.task == .done, line.content.length > 0 {
                storage.addAttributes([.foregroundColor: theme.doneColor,
                                       .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: line.content)
            }
        case .quote:
            if let marker = line.marker { storage.addAttribute(.foregroundColor, value: theme.syntaxColor, range: marker) }
        case .toggle:
            if let marker = line.marker {
                storage.addAttributes([.foregroundColor: theme.listMarkerColor, .font: theme.toggleMarkerFont], range: marker)
            }
            if toggleKern > 0 {
                storage.addAttribute(.kern, value: toggleKern, range: NSRange(location: NSMaxRange(line.prefix) - 1, length: 1))
            }
        default:
            break
        }
        styleInline(line.content, of: text, in: storage, size: size, weight: weight)
    }

    /// Emphasis, code, strikethrough and links within a line's content.
    private func styleInline(_ range: NSRange, of text: MarkdownText, in storage: NSTextStorage,
                             size: CGFloat, weight: NSFont.Weight) {
        let spans = MarkdownInline.spans(in: text, range: range)
        guard !spans.isEmpty else { return }

        // Strong, emphasis and code combine (***both***, **`code`**), so
        // fonts are set piece by piece between span edges.
        let fontSpans = spans.filter { $0.kind == .strong || $0.kind == .emphasis || $0.kind == .code }
        if !fontSpans.isEmpty {
            var edges: Set<Int> = []
            for span in fontSpans {
                edges.insert(span.range.location)
                edges.insert(NSMaxRange(span.range))
            }
            let points = edges.sorted()
            for (from, to) in zip(points, points.dropFirst()) {
                let covering = fontSpans.filter { $0.range.location <= from && NSMaxRange($0.range) >= to }
                guard !covering.isEmpty else { continue }
                let isCode = covering.contains { $0.kind == .code }
                let isStrong = covering.contains { $0.kind == .strong }
                let font = theme.font(size: isCode ? (size * 0.92).rounded() : size,
                                      weight: isStrong && weight.rawValue < NSFont.Weight.bold.rawValue ? .bold : weight,
                                      italic: covering.contains { $0.kind == .emphasis },
                                      monospaced: isCode)
                storage.addAttribute(.font, value: font, range: NSRange(location: from, length: to - from))
            }
        }

        for span in spans {
            switch span.kind {
            case .code:
                storage.addAttribute(.backgroundColor, value: theme.codeBackground, range: span.range)
            case .strikethrough:
                storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                       .foregroundColor: theme.doneColor], range: span.range)
            case .link:
                storage.addAttribute(.foregroundColor, value: theme.linkColor, range: span.range)
            case .url:
                storage.addAttribute(.foregroundColor, value: theme.syntaxColor, range: span.range)
            case .strong, .emphasis, .syntax:
                break
            }
        }
        // Last, so syntax inside a link or a struck-through span is quiet too.
        for span in spans where span.kind == .syntax {
            storage.addAttribute(.foregroundColor, value: theme.syntaxColor, range: span.range)
        }
    }
}

extension MarkdownStyler: NSTextStorageDelegate {
    /// Restyling happens once the edit is processed: changing attributes any
    /// earlier (in `willProcessEditing`) widens the edited range, and
    /// NSTextView then puts the caret at the end of it.
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        restyle(textStorage, editedRange: editedRange, delta: delta)
    }
}

extension MarkdownStyler: NSTextContentStorageDelegate {
    /// Lines a closed toggle folds away aren't laid out at all: TextKit
    /// skips the paragraphs turned down here and lays out the rest as if
    /// they weren't there. Restyling a line re-asks. TextKit asks about
    /// every paragraph it walks past, many times a frame while scrolling, so
    /// this reads the mark straight from the text storage — a paragraph's
    /// `attributedString` is a fresh copy each time. Nonisolated: it reads
    /// the text storage as TextKit itself does, on whatever thread it asks.
    nonisolated func textContentManager(_ textContentManager: NSTextContentManager,
                                        shouldEnumerate textElement: NSTextElement,
                                        options: NSTextContentManager.EnumerationOptions) -> Bool {
        guard let storage = (textContentManager as? NSTextContentStorage)?.textStorage,
              let start = textElement.elementRange?.location else { return true }
        let offset = textContentManager.offset(from: textContentManager.documentRange.location, to: start)
        guard offset < storage.length else { return true }
        return storage.attribute(.markdownHidden, at: offset, effectiveRange: nil) == nil
    }
}

extension MarkdownBlock {
    /// Has a background the text view draws.
    var isDecorated: Bool {
        switch self {
        case .fence, .code, .quote, .rule: true
        case .blank, .paragraph, .heading, .listItem, .toggle: false
        }
    }
}
