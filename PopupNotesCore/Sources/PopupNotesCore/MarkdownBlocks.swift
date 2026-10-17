import Foundation

/// What a line is, Markdown-wise. Notes are styled line by line, so this is
/// a deliberately small, line-based reading of CommonMark: ATX headings
/// (`#`), bullet / numbered / task lists, block quotes, fenced code blocks
/// and thematic breaks. Setext headings (a title underlined with `===`) and
/// indented code blocks are not recognized: in a notes editor, underlining
/// with `---` and indenting text by four spaces are far more often meant
/// literally than as Markdown.
public enum MarkdownBlock: Equatable, Sendable {
    case blank
    case paragraph
    case heading(level: Int)
    case listItem(MarkdownListMarker)
    case quote
    /// The opening or closing line of a fenced code block (```` ``` ```` or `~~~`).
    case fence
    /// A line inside a fenced code block.
    case code
    /// A thematic break: `---`, `***` or `___`.
    case rule
}

public struct MarkdownListMarker: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// `-`, `*` or `+`.
        case bullet(Character)
        /// `1.` or `1)`.
        case ordered(number: Int, delimiter: Character)
    }

    public enum TaskState: Equatable, Sendable {
        case open
        case done
    }

    public var kind: Kind
    /// Set for task items: `- [ ]` is open, `- [x]` is done.
    public var task: TaskState?

    public init(kind: Kind, task: TaskState? = nil) {
        self.kind = kind
        self.task = task
    }
}

/// One line of a note and the parts of it that Markdown gives meaning to.
/// All ranges are UTF-16 offsets into the whole text.
public struct MarkdownLine: Equatable, Sendable {
    /// The line without its line break.
    public var range: NSRange
    /// 0 for the last line, 2 for CRLF, otherwise 1.
    public var terminatorLength: Int
    public var block: MarkdownBlock
    /// The syntax that opens the line, up to where its content starts:
    /// indentation plus `## `, `- ` (and a task box), `1. ` or `> `.
    public var prefix: NSRange
    /// The part that can hold inline Markdown (emphasis, code, links).
    /// Empty for blank lines, fences, code and rules.
    public var content: NSRange
    /// The marker itself, within `prefix`: `##`, `-`, `1.` or `>`.
    public var marker: NSRange?
    /// A task item's `[ ]` / `[x]` box, within `prefix`.
    public var taskBox: NSRange?
    /// A heading's optional closing `#`s and the space before them.
    public var closingSequence: NSRange?

    /// The line including its line break.
    public var fullRange: NSRange {
        NSRange(location: range.location, length: range.length + terminatorLength)
    }
}

public enum MarkdownBlocks {
    /// Every line of `text`, classified. A text that ends in a line break
    /// has a final empty line (where the caret sits after Return), so the
    /// lines always cover every caret position.
    public static func lines(in text: MarkdownText) -> [MarkdownLine] {
        let units = text.units
        var lines: [MarkdownLine] = []
        var fence: Fence?
        var start = 0
        while true {
            var end = start
            while end < units.count, !units[end].isLineTerminator { end += 1 }
            var terminator = 0
            if end < units.count {
                let isCRLF = units[end] == ASCII.carriageReturn
                    && end + 1 < units.count && units[end + 1] == ASCII.lineFeed
                terminator = isCRLF ? 2 : 1
            }
            lines.append(classify(units, NSRange(location: start, length: end - start),
                                  terminatorLength: terminator, fence: &fence))
            if terminator == 0 { return lines }
            start = end + terminator
        }
    }

    /// The index of the line holding `location` (a caret position).
    public static func lineIndex(containing location: Int, in lines: [MarkdownLine]) -> Int? {
        var low = 0
        var high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].range.location <= location { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? nil : low - 1
    }

    /// An open fenced code block: the fence character and how many opened it.
    struct Fence: Equatable {
        var character: UInt16
        var length: Int
    }

    /// Classifies one line, given whether a fenced code block is open before
    /// it, and updates that state for the next line.
    static func classify(_ u: [UInt16], _ range: NSRange, terminatorLength: Int,
                         fence: inout Fence?) -> MarkdownLine {
        let start = range.location
        let end = NSMaxRange(range)
        var line = MarkdownLine(range: range, terminatorLength: terminatorLength, block: .paragraph,
                                prefix: NSRange(location: start, length: 0), content: range)
        let empty = NSRange(location: start, length: 0)

        var first = start
        var columns = 0
        while first < end, u[first].isSpaceOrTab {
            columns += u[first] == ASCII.tab ? 4 - columns % 4 : 1
            first += 1
        }

        if let open = fence {
            if isClosingFence(u, from: first, to: end, closing: open) {
                fence = nil
                line.block = .fence
            } else {
                line.block = .code
            }
            line.content = empty
            return line
        }
        guard first < end else {
            line.block = .blank
            line.content = empty
            return line
        }

        let c = u[first]
        // Fences may be indented any amount (there are no indented code
        // blocks to confuse them with), so one nested in a list still counts.
        if c == ASCII.backtick || c == ASCII.tilde, let opened = openingFence(u, from: first, to: end) {
            fence = opened
            line.block = .fence
            line.content = empty
            return line
        }

        // Headings, rules and quotes allow at most three spaces of
        // indentation, as in CommonMark.
        if columns < 4 {
            if c == ASCII.hash, classifyHeading(u, first: first, end: end, into: &line) { return line }
            if c == ASCII.hyphen || c == ASCII.asterisk || c == ASCII.underscore,
               isRule(u, from: first, to: end) {
                line.block = .rule
                line.content = empty
                return line
            }
            if c == ASCII.greaterThan {
                var contentStart = first + 1
                if contentStart < end, u[contentStart].isSpaceOrTab { contentStart += 1 }
                line.block = .quote
                line.marker = NSRange(location: first, length: 1)
                line.prefix = NSRange(location: start, length: contentStart - start)
                line.content = NSRange(location: contentStart, length: end - contentStart)
                return line
            }
        }

        // List items nest by indentation, so any amount is allowed.
        if classifyListItem(u, first: first, end: end, into: &line) { return line }

        line.prefix = NSRange(location: start, length: first - start)
        line.content = NSRange(location: first, length: end - first)
        return line
    }

    /// `#` to `######`, then a space or the end of the line. `#tag` stays text.
    private static func classifyHeading(_ u: [UInt16], first: Int, end: Int,
                                        into line: inout MarkdownLine) -> Bool {
        var j = first
        while j < end, u[j] == ASCII.hash, j - first < 7 { j += 1 }
        let level = j - first
        guard level <= 6, j == end || u[j].isSpaceOrTab else { return false }

        var contentStart = j
        while contentStart < end, u[contentStart].isSpaceOrTab { contentStart += 1 }
        var contentEnd = end
        // An optional closing sequence: `## Title ##`.
        var k = end
        while k > contentStart, u[k - 1].isSpaceOrTab { k -= 1 }
        var hashes = k
        while hashes > contentStart, u[hashes - 1] == ASCII.hash { hashes -= 1 }
        if hashes < k, hashes == contentStart || u[hashes - 1].isSpaceOrTab {
            var closing = hashes
            while closing > contentStart, u[closing - 1].isSpaceOrTab { closing -= 1 }
            line.closingSequence = NSRange(location: closing, length: end - closing)
            contentEnd = closing
        }

        line.block = .heading(level: level)
        line.marker = NSRange(location: first, length: level)
        line.prefix = NSRange(location: line.range.location, length: contentStart - line.range.location)
        line.content = NSRange(location: contentStart, length: contentEnd - contentStart)
        return true
    }

    /// `-`, `*`, `+`, `1.` or `1)` followed by a space — the space matters:
    /// a lone `-` being typed shouldn't turn into a bullet until it's
    /// followed by one. Then an optional task box: `[ ]`, `[x]` or `[X]`.
    private static func classifyListItem(_ u: [UInt16], first: Int, end: Int,
                                         into line: inout MarkdownLine) -> Bool {
        let c = u[first]
        var kind: MarkdownListMarker.Kind
        var markerEnd: Int
        if c == ASCII.hyphen || c == ASCII.asterisk || c == ASCII.plus {
            guard first + 1 < end, u[first + 1].isSpaceOrTab else { return false }
            kind = .bullet(Character(Unicode.Scalar(UInt8(c))))
            markerEnd = first + 1
        } else if c.isASCIIDigit {
            var j = first
            while j < end, u[j].isASCIIDigit, j - first < 9 { j += 1 }
            guard j < end, u[j] == ASCII.period || u[j] == ASCII.rightParen,
                  j + 1 < end, u[j + 1].isSpaceOrTab else { return false }
            let digits = String(decoding: u[first..<j], as: UTF16.self)
            kind = .ordered(number: Int(digits) ?? 1, delimiter: Character(Unicode.Scalar(UInt8(u[j]))))
            markerEnd = j + 1
        } else {
            return false
        }

        var contentStart = markerEnd
        while contentStart < end, u[contentStart].isSpaceOrTab { contentStart += 1 }
        var task: MarkdownListMarker.TaskState?
        if contentStart + 3 <= end, u[contentStart] == ASCII.leftBracket,
           u[contentStart + 2] == ASCII.rightBracket,
           contentStart + 3 == end || u[contentStart + 3].isSpaceOrTab {
            switch u[contentStart + 1] {
            case ASCII.space: task = .open
            case ASCII.lowerX, ASCII.upperX: task = .done
            default: break
            }
            if task != nil {
                line.taskBox = NSRange(location: contentStart, length: 3)
                contentStart += 3
                while contentStart < end, u[contentStart].isSpaceOrTab { contentStart += 1 }
            }
        }

        line.block = .listItem(MarkdownListMarker(kind: kind, task: task))
        line.marker = NSRange(location: first, length: markerEnd - first)
        line.prefix = NSRange(location: line.range.location, length: contentStart - line.range.location)
        line.content = NSRange(location: contentStart, length: end - contentStart)
        return true
    }

    /// Three or more of the same `-`, `*` or `_`, with only spaces between.
    private static func isRule(_ u: [UInt16], from first: Int, to end: Int) -> Bool {
        let character = u[first]
        var count = 0
        for i in first..<end {
            if u[i] == character {
                count += 1
            } else if !u[i].isSpaceOrTab {
                return false
            }
        }
        return count >= 3
    }

    /// Three or more backticks or tildes. A backtick fence's info string
    /// can't contain a backtick, so ```` ```code``` ```` stays inline code.
    private static func openingFence(_ u: [UInt16], from first: Int, to end: Int) -> Fence? {
        let character = u[first]
        var j = first
        while j < end, u[j] == character { j += 1 }
        guard j - first >= 3 else { return nil }
        if character == ASCII.backtick, u[j..<end].contains(ASCII.backtick) { return nil }
        return Fence(character: character, length: j - first)
    }

    /// At least as many of the opening fence's character, and nothing else.
    private static func isClosingFence(_ u: [UInt16], from first: Int, to end: Int,
                                       closing fence: Fence) -> Bool {
        var j = first
        while j < end, u[j] == fence.character { j += 1 }
        guard j - first >= fence.length else { return false }
        return u[j..<end].allSatisfy(\.isSpaceOrTab)
    }
}
