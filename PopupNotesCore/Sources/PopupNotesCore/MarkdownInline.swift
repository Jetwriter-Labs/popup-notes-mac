import Foundation

/// A styled stretch of a line. Spans can nest (`***both***` yields an
/// emphasis span around a strong one) and every span includes its own
/// syntax characters, which are also reported as `.syntax` spans.
public struct MarkdownSpan: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case strong
        case emphasis
        case strikethrough
        /// A code span, backticks included.
        case code
        /// The visible text of a link, or a URL shown as-is.
        case link
        /// A link's destination: the `url` in `[text](url)`.
        case url
        /// Markdown punctuation rather than content: `**`, `` ` ``, `[`, `\`…
        case syntax
    }

    public var kind: Kind
    public var range: NSRange

    public init(_ kind: Kind, _ range: NSRange) {
        self.kind = kind
        self.range = range
    }
}

/// Inline Markdown within one line: emphasis (`*`, `_`), strong (`**`,
/// `__`), strikethrough (`~~`), code spans, links (`[text](url)`,
/// `<https://…>` and bare `http(s)://` URLs) and backslash escapes.
/// Emphasis follows CommonMark's delimiter rules, so `snake_case_names` and
/// `5 * 3` stay plain text.
public enum MarkdownInline {
    /// Longer lines (pasted minified data, say) aren't worth styling, and
    /// skipping them keeps every keystroke cheap.
    public static let maxLength = 10_000

    public static func spans(in text: MarkdownText, range: NSRange) -> [MarkdownSpan] {
        guard range.length > 0, range.length <= maxLength else { return [] }
        var parser = InlineParser(units: text.units, start: range.location, end: NSMaxRange(range))
        return parser.parse()
    }

    /// The content of `range` as it reads: syntax characters and link
    /// destinations dropped, link text and code kept.
    public static func plainText(in text: MarkdownText, range: NSRange) -> String {
        var keep = [Bool](repeating: true, count: range.length)
        for span in spans(in: text, range: range) where span.kind == .syntax || span.kind == .url {
            for i in span.range.location..<NSMaxRange(span.range) { keep[i - range.location] = false }
        }
        var units: [UInt16] = []
        units.reserveCapacity(range.length)
        for (offset, kept) in keep.enumerated() where kept {
            units.append(text.units[range.location + offset])
        }
        return String(decoding: units, as: UTF16.self)
    }
}

private struct InlineParser {
    let u: [UInt16]
    let start: Int
    let end: Int
    private var spans: [MarkdownSpan] = []
    /// Positions already claimed by code, links or escapes, relative to
    /// `start`: never delimiters, never re-scanned.
    private var claimed: [Bool]
    private var delimiters: [Delimiter] = []

    /// A run of `*`, `_` or `~~` that may open or close emphasis. `low..<high`
    /// is the part not yet used up: openers give up characters from the end,
    /// closers from the start.
    private struct Delimiter {
        var character: UInt16
        var length: Int
        var low: Int
        var high: Int
        var canOpen: Bool
        var canClose: Bool
        var remaining: Int { high - low }
    }

    init(units: [UInt16], start: Int, end: Int) {
        u = units
        self.start = start
        self.end = end
        claimed = [Bool](repeating: false, count: end - start)
    }

    mutating func parse() -> [MarkdownSpan] {
        var i = start
        while i < end {
            if claimed[i - start] { i += 1; continue }
            switch u[i] {
            case ASCII.backslash where i + 1 < end && u[i + 1].isASCIIPunctuation:
                add(.syntax, i, i + 1)
                claim(i, i + 2)
                i += 2
            case ASCII.backtick:
                i = codeSpan(at: i)
            case ASCII.lessThan:
                if let close = autolinkEnd(at: i) {
                    add(.syntax, i, i + 1)
                    add(.link, i + 1, close)
                    add(.syntax, close, close + 1)
                    claim(i, close + 1)
                    i = close + 1
                } else {
                    i += 1
                }
            case ASCII.leftBracket:
                link(at: i)
                i += 1
            case 0x68, 0x48: // h, H
                if let urlEnd = bareURLEnd(at: i) {
                    add(.link, i, urlEnd)
                    claim(i, urlEnd)
                    i = urlEnd
                } else {
                    i += 1
                }
            case ASCII.asterisk, ASCII.underscore, ASCII.tilde:
                i = delimiterRun(at: i)
            default:
                i += 1
            }
        }
        processEmphasis()
        return spans.sorted {
            $0.range.location != $1.range.location
                ? $0.range.location < $1.range.location
                : $0.range.length > $1.range.length
        }
    }

    // MARK: - Code, links, URLs

    /// A backtick run closes at the next run of exactly its length; without
    /// one, the backticks are plain text. Returns where scanning resumes.
    private mutating func codeSpan(at i: Int) -> Int {
        let length = run(of: ASCII.backtick, at: i)
        var j = i + length
        while j < end, !claimed[j - start] {
            guard u[j] == ASCII.backtick else { j += 1; continue }
            let closing = run(of: ASCII.backtick, at: j)
            if closing == length {
                add(.code, i, j + length)
                add(.syntax, i, i + length)
                add(.syntax, j, j + length)
                claim(i, j + length)
                return j + length
            }
            j += closing
        }
        claim(i, i + length)
        return i + length
    }

    /// `[text](destination)`, or `![alt](source)`. The text stays open to
    /// emphasis; brackets and destination are claimed. Reference links
    /// (`[text][ref]`) aren't supported.
    private mutating func link(at i: Int) {
        var depth = 0
        var j = i
        while j < end {
            if claimed[j - start] { return }
            let c = u[j]
            if c == ASCII.backslash, j + 1 < end, u[j + 1].isASCIIPunctuation { j += 2; continue }
            if c == ASCII.leftBracket {
                depth += 1
            } else if c == ASCII.rightBracket {
                depth -= 1
                if depth == 0 { break }
            }
            j += 1
        }
        guard j + 1 < end, u[j + 1] == ASCII.leftParen, !claimed[j + 1 - start] else { return }
        var k = j + 2
        var parens = 0
        while k < end {
            if claimed[k - start] { return }
            let c = u[k]
            if c == ASCII.backslash, k + 1 < end, u[k + 1].isASCIIPunctuation { k += 2; continue }
            if c == ASCII.leftParen {
                parens += 1
            } else if c == ASCII.rightParen {
                if parens == 0 { break }
                parens -= 1
            }
            k += 1
        }
        guard k < end else { return }

        let opens = i > start && u[i - 1] == ASCII.exclamation && !claimed[i - 1 - start] ? i - 1 : i
        add(.syntax, opens, i + 1)
        add(.link, i + 1, j)
        add(.syntax, j, j + 2)
        add(.url, j + 2, k)
        add(.syntax, k, k + 1)
        claim(opens, i + 1)
        claim(j, k + 1)
    }

    /// `<scheme:…>`: a scheme of 2–32 characters, then no spaces or angle
    /// brackets. Returns the index of the closing `>`.
    private func autolinkEnd(at i: Int) -> Int? {
        var j = i + 1
        guard j < end, u[j].isASCIILetter else { return nil }
        while j < end, u[j].isASCIILetter || u[j].isASCIIDigit
                || u[j] == ASCII.plus || u[j] == ASCII.period || u[j] == ASCII.hyphen {
            j += 1
        }
        guard (2...32).contains(j - i - 1), j < end, u[j] == ASCII.colon else { return nil }
        while j < end {
            let c = u[j]
            if c == ASCII.greaterThan { return j }
            if c == ASCII.lessThan || c == ASCII.space || c == ASCII.tab || claimed[j - start] { return nil }
            j += 1
        }
        return nil
    }

    /// A URL typed or pasted as-is (GitHub's autolink extension): `http://`
    /// or `https://` at the start of a word, up to the next space, minus
    /// trailing punctuation and an unbalanced closing parenthesis. Claimed,
    /// so the `_` and `*` URLs often contain never turn into emphasis.
    private func bareURLEnd(at i: Int) -> Int? {
        if i > start {
            let before = u[i - 1]
            guard before.isSpaceOrTab || before == ASCII.leftParen || before == ASCII.asterisk
                    || before == ASCII.underscore || before == ASCII.tilde else { return nil }
        }
        let schemeLength: Int
        if hasPrefix("https://", at: i) {
            schemeLength = 8
        } else if hasPrefix("http://", at: i) {
            schemeLength = 7
        } else {
            return nil
        }
        var j = i + schemeLength
        while j < end, !u[j].isSpaceOrTab, u[j] != ASCII.lessThan, !claimed[j - start] { j += 1 }
        while j > i + schemeLength {
            let last = u[j - 1]
            if [ASCII.period, ASCII.colon, ASCII.asterisk, ASCII.underscore, ASCII.tilde,
                0x21, 0x22, 0x27, 0x2C, 0x3B, 0x3F].contains(last) { // ! " ' , ; ?
                j -= 1
            } else if last == ASCII.rightParen,
                      u[i..<j].count(where: { $0 == ASCII.rightParen })
                        > u[i..<j].count(where: { $0 == ASCII.leftParen }) {
                j -= 1
            } else {
                break
            }
        }
        return j > i + schemeLength ? j : nil
    }

    /// ASCII case-insensitive.
    private func hasPrefix(_ prefix: String, at i: Int) -> Bool {
        var j = i
        for expected in prefix.utf16 {
            guard j < end else { return false }
            let c = u[j]
            let lowered = c >= 0x41 && c <= 0x5A ? c + 0x20 : c
            guard lowered == expected else { return false }
            j += 1
        }
        return true
    }

    // MARK: - Emphasis

    /// Records a run of `*`, `_` or `~` as a potential delimiter, using
    /// CommonMark's flanking rules. Only `~~` (exactly two) strikes through,
    /// so `~5 min` stays as typed.
    private mutating func delimiterRun(at i: Int) -> Int {
        let character = u[i]
        var j = i
        while j < end, u[j] == character, !claimed[j - start] { j += 1 }
        let length = j - i
        if character == ASCII.tilde, length != 2 { return j }

        let before = characterClass(of: scalar(before: i))
        let after = characterClass(of: scalar(at: j))
        let leftFlanking = after != .whitespace
            && (after != .punctuation || before == .whitespace || before == .punctuation)
        let rightFlanking = before != .whitespace
            && (before != .punctuation || after == .whitespace || after == .punctuation)
        let canOpen: Bool
        let canClose: Bool
        if character == ASCII.underscore {
            // `_` can't open or close inside a word: snake_case_stays_plain.
            canOpen = leftFlanking && (!rightFlanking || before == .punctuation)
            canClose = rightFlanking && (!leftFlanking || after == .punctuation)
        } else {
            canOpen = leftFlanking
            canClose = rightFlanking
        }
        if canOpen || canClose {
            delimiters.append(Delimiter(character: character, length: length, low: i, high: j,
                                        canOpen: canOpen, canClose: canClose))
        }
        return j
    }

    /// CommonMark's "process emphasis": each closer, left to right, pairs
    /// with the nearest usable opener below it. Two characters from each
    /// side make strong emphasis, one makes emphasis; whatever they enclose
    /// can't pair across the match. `openersBottom` keeps a run of unmatched
    /// closers from making this quadratic.
    private mutating func processEmphasis() {
        var openersBottom: [Int: Int] = [:]
        var c = 0
        while c < delimiters.count {
            let closer = delimiters[c]
            guard closer.canClose, closer.remaining > 0 else { c += 1; continue }
            let key = Int(closer.character) * 8 + (closer.canOpen ? 4 : 0) + closer.length % 3
            let bottom = openersBottom[key] ?? -1
            var opener: Int?
            var o = c - 1
            while o > bottom {
                let candidate = delimiters[o]
                if candidate.character == closer.character, candidate.canOpen, candidate.remaining > 0 {
                    if closer.character == ASCII.tilde {
                        if candidate.remaining == 2, closer.remaining == 2 { opener = o; break }
                    } else {
                        // The "rule of 3": `*foo**bar*` mustn't pair the `**`.
                        let ambiguous = candidate.canClose || closer.canOpen
                        let sum = candidate.length + closer.length
                        if !(ambiguous && sum % 3 == 0 && !(candidate.length % 3 == 0 && closer.length % 3 == 0)) {
                            opener = o
                            break
                        }
                    }
                }
                o -= 1
            }

            guard let o = opener else {
                openersBottom[key] = c - 1
                if !closer.canOpen { delimiters[c].low = delimiters[c].high }
                c += 1
                continue
            }
            let use = closer.character == ASCII.tilde || (delimiters[o].remaining >= 2 && closer.remaining >= 2) ? 2 : 1
            let openFrom = delimiters[o].high - use
            let closeTo = closer.low + use
            delimiters[o].high -= use
            delimiters[c].low += use
            let kind: MarkdownSpan.Kind = closer.character == ASCII.tilde ? .strikethrough : use == 2 ? .strong : .emphasis
            add(kind, openFrom, closeTo)
            add(.syntax, openFrom, openFrom + use)
            add(.syntax, closeTo - use, closeTo)
            for between in (o + 1)..<c { delimiters[between].low = delimiters[between].high }
            if delimiters[c].remaining == 0 { c += 1 }
        }
    }

    private enum CharacterClass { case whitespace, punctuation, other }

    /// The line's edges count as whitespace.
    private func characterClass(of scalar: Unicode.Scalar?) -> CharacterClass {
        guard let scalar else { return .whitespace }
        if scalar.isASCII {
            let value = UInt16(scalar.value)
            if value.isSpaceOrTab || value.isLineTerminator { return .whitespace }
            return value.isASCIIPunctuation ? .punctuation : .other
        }
        if scalar.properties.isWhitespace { return .whitespace }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation,
             .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
            return .punctuation
        default:
            return .other
        }
    }

    private func scalar(before i: Int) -> Unicode.Scalar? {
        guard i > start else { return nil }
        let unit = u[i - 1]
        if UTF16.isTrailSurrogate(unit), i - 2 >= start, UTF16.isLeadSurrogate(u[i - 2]) {
            return Self.scalar(lead: u[i - 2], trail: unit)
        }
        return Unicode.Scalar(unit)
    }

    private func scalar(at i: Int) -> Unicode.Scalar? {
        guard i < end else { return nil }
        let unit = u[i]
        if UTF16.isLeadSurrogate(unit), i + 1 < end, UTF16.isTrailSurrogate(u[i + 1]) {
            return Self.scalar(lead: unit, trail: u[i + 1])
        }
        return Unicode.Scalar(unit)
    }

    private static func scalar(lead: UInt16, trail: UInt16) -> Unicode.Scalar? {
        Unicode.Scalar(0x10000 + ((UInt32(lead) - 0xD800) << 10) + (UInt32(trail) - 0xDC00))
    }

    // MARK: - Helpers

    private func run(of character: UInt16, at i: Int) -> Int {
        var j = i
        while j < end, u[j] == character { j += 1 }
        return j - i
    }

    private mutating func add(_ kind: MarkdownSpan.Kind, _ from: Int, _ to: Int) {
        guard to > from else { return } // `[](url)` has no text to style
        spans.append(MarkdownSpan(kind, NSRange(location: from, length: to - from)))
    }

    private mutating func claim(_ from: Int, _ to: Int) {
        for i in from..<to { claimed[i - start] = true }
    }
}
