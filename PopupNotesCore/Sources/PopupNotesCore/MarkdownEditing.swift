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
/// boxes that check off, toggles made by typing `> `. Each returns nil when
/// the key should simply do what it always does.
public enum MarkdownEditing {
    /// The text Tab adds to nest a list item one level.
    static let indentUnit = "\t"

    // MARK: - Return

    /// Return with a caret at `selection`. In a list item or a quote, the new
    /// line starts with the same marker (numbers count up; a task starts
    /// unchecked). Return on an item that's still empty ends the list
    /// instead: a nested item moves out a level, a top-level one loses its
    /// marker — so pressing Return twice gets you out.
    ///
    /// On an open toggle's title, Return starts the first line inside it; on
    /// a closed one, a new toggle after everything it folds away. Inside a
    /// toggle, the new line keeps the indentation that puts it there, and
    /// Return on a line holding nothing but that indentation steps out a
    /// level — so pressing Return twice leaves the toggle too.
    public static func newline(in text: MarkdownText, selection: NSRange) -> MarkdownEdit? {
        guard selection.length == 0 else { return nil }
        let caret = selection.location
        let lines = MarkdownBlocks.lines(in: text)
        guard let index = MarkdownBlocks.lineIndex(containing: caret, in: lines) else { return nil }
        let line = lines[index]
        guard let marker = line.marker else { return keepingIndentation(line, in: text, caret: caret) }
        // In the indentation or the marker, Return just moves the line down.
        guard caret >= NSMaxRange(line.prefix) else { return nil }
        let indentation = text.string(in: NSRange(location: line.range.location,
                                                  length: marker.location - line.range.location))

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
        case .toggle(let isOpen) where line.content.length > 0:
            if !isOpen { return toggle(after: index, in: lines, text: text, caret: caret) }
            let insertion = "\n" + indentation + indentUnit
            return MarkdownEdit(range: NSRange(location: caret, length: 0), replacement: insertion,
                                selection: NSRange(location: caret + insertion.utf16.count, length: 0))
        case .toggle:
            continuation = ""
        default:
            return keepingIndentation(line, in: text, caret: caret)
        }

        if line.content.length == 0 { return end(index, in: lines, text: text, caret: caret) }
        let insertion = "\n" + indentation + continuation
        return MarkdownEdit(range: NSRange(location: caret, length: 0), replacement: insertion,
                            selection: NSRange(location: caret + insertion.utf16.count, length: 0))
    }

    /// Return on an empty list item, quote or toggle. A nested item or
    /// toggle moves out a level, a top-level one loses its marker. Inside a
    /// toggle, its top level is the toggle's: the line loses its marker but
    /// stays in the toggle, as plain text.
    private static func end(_ index: Int, in lines: [MarkdownLine], text: MarkdownText, caret: Int) -> MarkdownEdit {
        let line = lines[index]
        if line.isListItem || line.isToggle, let outdented = outdent(line, in: text, caret: caret) {
            let parent = MarkdownToggles.parent(of: index, in: lines)
            let left = columns(of: line, in: text, after: outdented.range.length)
            if parent.map({ left > columns(of: lines[$0], in: text) }) ?? true { return outdented }
        }
        if line.toggleDepth > 0, let marker = line.marker {
            return MarkdownEdit(range: NSRange(location: marker.location, length: NSMaxRange(line.range) - marker.location),
                                replacement: "", selection: NSRange(location: marker.location, length: 0))
        }
        return MarkdownEdit(range: line.range, replacement: "",
                            selection: NSRange(location: line.range.location, length: 0))
    }

    /// Return on a closed toggle's title: a new toggle after the lines it
    /// folds away. Title text after the caret moves to the new toggle.
    private static func toggle(after index: Int, in lines: [MarkdownLine], text: MarkdownText,
                               caret: Int) -> MarkdownEdit {
        let line = lines[index]
        let marker = line.marker ?? line.prefix
        let body = MarkdownToggles.body(of: index, in: lines)
        let titleEnd = NSMaxRange(line.range)
        let blockEnd = body.isEmpty ? titleEnd : NSMaxRange(lines[body.upperBound - 1].range)
        let opening = "\n" + text.string(in: NSRange(location: line.range.location,
                                                     length: marker.location - line.range.location))
            + ToggleMarker.string(open: true) + " "
        if caret == titleEnd {
            return MarkdownEdit(range: NSRange(location: blockEnd, length: 0), replacement: opening,
                                selection: NSRange(location: blockEnd + opening.utf16.count, length: 0))
        }
        let folded = text.string(in: NSRange(location: titleEnd, length: blockEnd - titleEnd))
        let tail = text.string(in: NSRange(location: caret, length: titleEnd - caret))
        return MarkdownEdit(range: NSRange(location: caret, length: blockEnd - caret),
                            replacement: folded + opening + tail,
                            selection: NSRange(location: caret + (folded + opening).utf16.count, length: 0))
    }

    /// Inside a toggle, a line without a marker of its own: the new line
    /// keeps its indentation. On a line that is nothing but indentation,
    /// Return steps out a level instead. Nil outside toggles.
    private static func keepingIndentation(_ line: MarkdownLine, in text: MarkdownText, caret: Int) -> MarkdownEdit? {
        guard line.toggleDepth > 0 else { return nil }
        if line.block == .blank {
            guard caret == NSMaxRange(line.range) else { return nil }
            return outdent(line, in: text, caret: caret)
        }
        let first = MarkdownBlocks.indentation(text.units, line.range).first
        guard caret >= first else { return nil }
        let insertion = "\n" + text.string(in: NSRange(location: line.range.location, length: first - line.range.location))
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

    /// How wide `line`'s indentation is, without its first `dropping` units.
    private static func columns(of line: MarkdownLine, in text: MarkdownText, after dropping: Int = 0) -> Int {
        MarkdownBlocks.indentation(text.units, NSRange(location: line.range.location + dropping,
                                                      length: line.range.length - dropping)).columns
    }

    // MARK: - Tab

    /// Tab — or Shift-Tab, `outdent` — moves lines in (out) one level: with a
    /// caret, a list item, a toggle or a line inside a toggle, wherever the
    /// caret is in it; with a selection over several lines, all of them. A
    /// toggle takes the lines it holds along. Nil, a plain tab, for a caret
    /// on any other line. An edit that changes nothing means Shift-Tab had
    /// nowhere to go.
    public static func indentation(in text: MarkdownText, selection: NSRange, outdent: Bool) -> MarkdownEdit? {
        let lines = MarkdownBlocks.lines(in: text)
        guard let first = MarkdownBlocks.lineIndex(containing: selection.location, in: lines),
              var last = MarkdownBlocks.lineIndex(containing: NSMaxRange(selection), in: lines) else { return nil }
        // Whole lines selected by dragging end at the start of the next line;
        // that line isn't part of the selection.
        if last > first, NSMaxRange(selection) == lines[last].range.location { last -= 1 }
        let severalLines = last > first
        guard severalLines || lines[first].nests else { return nil }
        for index in first...last where lines[index].isToggle {
            last = max(last, MarkdownToggles.body(of: index, in: lines).upperBound - 1)
        }

        // Each change happens at a line's start: `inserted` units added,
        // `removed` units taken away.
        var changes: [(start: Int, inserted: Int, removed: Int)] = []
        var replacement: [UInt16] = []
        // A toggle that can't move out keeps its lines where they are.
        var staysThrough = -1
        for index in first...last {
            let line = lines[index]
            var body = text.units[line.range.location..<NSMaxRange(line.fullRange)]
            // Blank lines among several get no indentation of their own.
            let isBlank = MarkdownBlocks.indentation(text.units, line.range).first == NSMaxRange(line.range)
            if index > staysThrough, !(severalLines && isBlank) {
                if outdent {
                    let removed = outdentLength(of: line, in: text)
                    if removed == 0, line.isToggle {
                        staysThrough = MarkdownToggles.body(of: index, in: lines).upperBound - 1
                    }
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

    // MARK: - Toggles

    /// `>` and a space at the start of a line make it a toggle, as in Notion:
    /// the editor asks right after a space is typed. Undoing the change
    /// leaves the `> ` as typed — a quote.
    public static func toggleShortcut(in text: MarkdownText, selection: NSRange) -> MarkdownEdit? {
        let caret = selection.location
        guard selection.length == 0, caret >= 2,
              text.units[caret - 1] == ASCII.space, text.units[caret - 2] == ASCII.greaterThan else { return nil }
        let lines = MarkdownBlocks.lines(in: text)
        guard let index = MarkdownBlocks.lineIndex(containing: caret, in: lines), lines[index].block != .code,
              text.units[lines[index].range.location..<(caret - 2)].allSatisfy(\.isSpaceOrTab) else { return nil }
        return MarkdownEdit(range: NSRange(location: caret - 2, length: 2),
                            replacement: ToggleMarker.string(open: true) + " ", selection: nil)
    }

    /// Backspace at the start of a toggle's title turns the toggle back into
    /// plain text. At the start of the line below a closed toggle, it joins
    /// that line to the toggle's title — the line it shows under — and the
    /// lines folded away in between stay as they are.
    public static func deleteBackward(in text: MarkdownText, selection: NSRange) -> MarkdownEdit? {
        guard selection.length == 0 else { return nil }
        let caret = selection.location
        // Most backspaces are neither right after a marker nor at a line's
        // start: those needn't read the whole note's lines.
        var markerEnd = caret
        while markerEnd > 0, text.units[markerEnd - 1].isSpaceOrTab { markerEnd -= 1 }
        let afterMarker = markerEnd > 0
            && (text.units[markerEnd - 1] == ToggleMarker.open || text.units[markerEnd - 1] == ToggleMarker.closed)
        guard afterMarker || (caret > 0 && text.units[caret - 1].isLineTerminator) else { return nil }
        let lines = MarkdownBlocks.lines(in: text)
        guard let index = MarkdownBlocks.lineIndex(containing: caret, in: lines) else { return nil }
        let line = lines[index]
        if line.isToggle, let marker = line.marker, caret == NSMaxRange(line.prefix) {
            return MarkdownEdit(range: NSRange(location: marker.location, length: caret - marker.location),
                                replacement: "", selection: NSRange(location: marker.location, length: 0))
        }
        guard caret == line.range.location, index > 0, lines[index - 1].isHidden, !line.isHidden else { return nil }
        return join(index, in: lines, text: text)
    }

    /// Forward Delete at the end of a closed toggle's title joins the line
    /// shown below it, keeping what's folded away in between. With nothing
    /// below, it does nothing rather than reach into the folded lines.
    public static func deleteForward(in text: MarkdownText, selection: NSRange) -> MarkdownEdit? {
        let caret = selection.location
        guard selection.length == 0, caret < text.length, text.units[caret].isLineTerminator else { return nil }
        let lines = MarkdownBlocks.lines(in: text)
        guard let index = MarkdownBlocks.lineIndex(containing: caret, in: lines), !lines[index].isHidden,
              caret == NSMaxRange(lines[index].range), index + 1 < lines.count, lines[index + 1].isHidden else { return nil }
        var below = index + 1
        while below < lines.count, lines[below].isHidden { below += 1 }
        guard below < lines.count else {
            return MarkdownEdit(range: NSRange(location: caret, length: 0), replacement: "", selection: nil)
        }
        return join(below, in: lines, text: text)
    }

    /// Moves line `index`, which shows right below some folded lines, onto
    /// the end of the line above them, with the folded lines after it.
    private static func join(_ index: Int, in lines: [MarkdownLine], text: MarkdownText) -> MarkdownEdit {
        var above = index - 1
        while above > 0, lines[above].isHidden { above -= 1 }
        let titleEnd = NSMaxRange(lines[above].range)
        let foldEnd = NSMaxRange(lines[index - 1].range)
        let line = lines[index]
        return MarkdownEdit(range: NSRange(location: titleEnd, length: NSMaxRange(line.range) - titleEnd),
                            replacement: text.string(in: line.range)
                                + text.string(in: NSRange(location: titleEnd, length: foldEnd - titleEnd)),
                            selection: NSRange(location: titleEnd, length: 0))
    }
}

extension MarkdownLine {
    var isListItem: Bool {
        if case .listItem = block { return true }
        return false
    }

    var isToggle: Bool {
        if case .toggle = block { return true }
        return false
    }

    /// Tab nests it even with just a caret on it.
    var nests: Bool { isListItem || isToggle || toggleDepth > 0 }
}
