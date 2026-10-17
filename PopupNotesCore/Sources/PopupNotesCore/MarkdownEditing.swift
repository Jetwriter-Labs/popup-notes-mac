import Foundation

/// A change for the editor to make: replace `range` (UTF-16) with
/// `replacement`, then select `selection` — or keep the selection, if nil.
public struct MarkdownEdit: Equatable, Sendable {
    public var range: NSRange
    public var replacement: String
    public var selection: NSRange?

    public init(range: NSRange, replacement: String, selection: NSRange?) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }
}

/// The conveniences that make Markdown comfortable to type: lists that
/// continue on Return, Tab to nest them, ⌘B / ⌘I to wrap a selection, task
/// boxes that check off. Each returns nil when the key should simply do
/// what it always does.
public enum MarkdownEditing {
    /// The text Tab adds to nest a list item one level.
    static let indentUnit = "\t"

    // MARK: - Return

    /// Return with a caret at `selection`. In a list item or a quote, the new
    /// line starts with the same marker (numbers count up; a task starts
    /// unchecked). Return on an item that's still empty ends the list
    /// instead: a nested item moves out a level, a top-level one loses its
    /// marker — so pressing Return twice gets you out.
    public static func newline(in text: MarkdownText, selection: NSRange) -> MarkdownEdit? {
        guard selection.length == 0 else { return nil }
        let caret = selection.location
        let lines = MarkdownBlocks.lines(in: text)
        guard let index = MarkdownBlocks.lineIndex(containing: caret, in: lines) else { return nil }
        let line = lines[index]
        // In the indentation or the marker, Return just moves the line down.
        guard caret >= NSMaxRange(line.prefix), let marker = line.marker else { return nil }

        var continuation: String
        switch line.block {
        case .listItem(let item):
            switch item.kind {
            case .bullet(let bullet): continuation = "\(bullet) "
            case .ordered(let number, let delimiter): continuation = "\(number + 1)\(delimiter) "
            }
            if item.task != nil { continuation += "[ ] " }
        case .quote:
            continuation = "> "
        default:
            return nil
        }

        if line.content.length == 0 {
            if case .listItem = line.block, let outdented = outdent(line, in: text, caret: caret) {
                return outdented
            }
            return MarkdownEdit(range: line.range, replacement: "",
                                selection: NSRange(location: line.range.location, length: 0))
        }
        let indentation = text.string(in: NSRange(location: line.range.location,
                                                  length: marker.location - line.range.location))
        let insertion = "\n" + indentation + continuation
        return MarkdownEdit(range: NSRange(location: caret, length: 0), replacement: insertion,
                            selection: NSRange(location: caret + insertion.utf16.count, length: 0))
    }

    /// One level out for an empty nested item, or nil if it isn't nested.
    private static func outdent(_ line: MarkdownLine, in text: MarkdownText, caret: Int) -> MarkdownEdit? {
        let removed = outdentLength(of: line, in: text)
        guard removed > 0 else { return nil }
        return MarkdownEdit(range: NSRange(location: line.range.location, length: removed), replacement: "",
                            selection: NSRange(location: caret - removed, length: 0))
    }

    // MARK: - Tab

    /// Tab — or Shift-Tab, `outdent` — on list items: every list item the
    /// selection touches moves in (out) one level, wherever the caret is in
    /// it. Nil, a plain tab, when the selection touches no list item. An
    /// edit that changes nothing means Shift-Tab had nowhere to go.
    public static func indentation(in text: MarkdownText, selection: NSRange, outdent: Bool) -> MarkdownEdit? {
        let lines = MarkdownBlocks.lines(in: text)
        guard let first = MarkdownBlocks.lineIndex(containing: selection.location, in: lines),
              var last = MarkdownBlocks.lineIndex(containing: NSMaxRange(selection), in: lines) else { return nil }
        // Whole lines selected by dragging end at the start of the next line;
        // that line isn't part of the selection.
        if last > first, NSMaxRange(selection) == lines[last].range.location { last -= 1 }
        let affected = lines[first...last]
        guard affected.contains(where: \.isListItem) else { return nil }

        // Each change happens at a line's start: `inserted` units added,
        // `removed` units taken away.
        var changes: [(start: Int, inserted: Int, removed: Int)] = []
        var replacement: [UInt16] = []
        for line in affected {
            var body = text.units[line.range.location..<NSMaxRange(line.fullRange)]
            if line.isListItem {
                if outdent {
                    let removed = outdentLength(of: line, in: text)
                    body = body.dropFirst(removed)
                    changes.append((line.range.location, 0, removed))
                } else {
                    replacement.append(contentsOf: indentUnit.utf16)
                    changes.append((line.range.location, indentUnit.utf16.count, 0))
                }
            }
            replacement.append(contentsOf: body)
        }
        // The last line's break stays outside the replaced range.
        replacement.removeLast(lines[last].terminatorLength)

        // Text moves with its line. A selection starting right at a line's
        // start stays there, so selected lines stay selected, new tab and all.
        func moved(_ position: Int, staysAtLineStart: Bool) -> Int {
            var shift = 0
            for change in changes where change.start <= position {
                if staysAtLineStart, change.start == position { continue }
                shift += change.inserted - min(change.removed, position - change.start)
            }
            return position + shift
        }
        let start = moved(selection.location, staysAtLineStart: selection.length > 0)
        let end = moved(NSMaxRange(selection), staysAtLineStart: false)
        let range = NSRange(location: lines[first].range.location,
                            length: NSMaxRange(lines[last].range) - lines[first].range.location)
        return MarkdownEdit(range: range, replacement: String(decoding: replacement, as: UTF16.self),
                            selection: NSRange(location: start, length: end - start))
    }

    /// One level of indentation: a tab, or up to four spaces.
    private static func outdentLength(of line: MarkdownLine, in text: MarkdownText) -> Int {
        let start = line.range.location
        let end = NSMaxRange(line.range)
        guard start < end else { return 0 }
        if text.units[start] == ASCII.tab { return 1 }
        var spaces = 0
        while start + spaces < end, spaces < 4, text.units[start + spaces] == ASCII.space { spaces += 1 }
        return spaces
    }

    // MARK: - ⌘B / ⌘I

    /// Wraps the selection in `marker` (`**` for bold, `*` for italic), or
    /// unwraps it if it is already wrapped — counting the asterisks around
    /// it, so italic inside bold (`***word***`) toggles cleanly. Spaces at the
    /// selection's edges stay outside: `** word**` wouldn't be bold. With
    /// just a caret, a pair is inserted with the caret between them, and an
    /// empty pair around the caret is removed.
    public static func toggle(_ marker: String, in text: MarkdownText, selection: NSRange) -> MarkdownEdit {
        let u = text.units
        let width = marker.utf16.count
        var start = selection.location
        var end = NSMaxRange(selection)
        while start < end, u[start].isSpaceOrTab { start += 1 }
        while end > start, u[end - 1].isSpaceOrTab { end -= 1 }
        if start == end { start = selection.location; end = start } // only whitespace selected

        func isWrapped(byLeft left: Int, right: Int) -> Bool {
            // Bold needs two asterisks a side; italic an odd number (1, or 3 = bold italic).
            width == 2 ? min(left, right) >= 2 : left % 2 == 1 && right % 2 == 1
        }
        var outsideLeft = 0
        while start - outsideLeft > 0, u[start - outsideLeft - 1] == ASCII.asterisk { outsideLeft += 1 }
        var outsideRight = 0
        while end + outsideRight < u.count, u[end + outsideRight] == ASCII.asterisk { outsideRight += 1 }

        if isWrapped(byLeft: outsideLeft, right: outsideRight) {
            let inner = text.string(in: NSRange(location: start, length: end - start))
            return MarkdownEdit(range: NSRange(location: start - width, length: end - start + 2 * width),
                                replacement: inner,
                                selection: NSRange(location: start - width, length: end - start))
        }
        if end > start {
            var insideLeft = 0
            while start + insideLeft < end, u[start + insideLeft] == ASCII.asterisk { insideLeft += 1 }
            var insideRight = 0
            while end - insideRight > start + insideLeft, u[end - insideRight - 1] == ASCII.asterisk { insideRight += 1 }
            if isWrapped(byLeft: insideLeft, right: insideRight) {
                let inner = text.string(in: NSRange(location: start + width, length: end - start - 2 * width))
                return MarkdownEdit(range: NSRange(location: start, length: end - start), replacement: inner,
                                    selection: NSRange(location: start, length: inner.utf16.count))
            }
        }
        let selected = text.string(in: NSRange(location: start, length: end - start))
        return MarkdownEdit(range: NSRange(location: start, length: end - start),
                            replacement: marker + selected + marker,
                            selection: NSRange(location: start + width, length: end - start))
    }

    // MARK: - Tasks

    /// Checks or unchecks the task item on the line holding `location`.
    public static func toggleTask(in text: MarkdownText, at location: Int) -> MarkdownEdit? {
        let lines = MarkdownBlocks.lines(in: text)
        guard let index = MarkdownBlocks.lineIndex(containing: location, in: lines),
              case .listItem(let item) = lines[index].block, let task = item.task,
              let box = lines[index].taskBox else { return nil }
        return MarkdownEdit(range: NSRange(location: box.location + 1, length: 1),
                            replacement: task == .open ? "x" : " ", selection: nil)
    }
}

extension MarkdownLine {
    var isListItem: Bool {
        if case .listItem = block { return true }
        return false
    }
}
