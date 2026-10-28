import Foundation

/// A note's text as UTF-16 code units — the unit `NSString` and
/// `NSTextStorage` ranges count in — so every range the Markdown parser
/// reports can go straight to AppKit. Markdown's syntax characters are all
/// ASCII, and the toggle markers single units outside the surrogate range,
/// so scanning code units never mistakes half of a surrogate pair for
/// syntax.
public struct MarkdownText: Sendable {
    public let units: [UInt16]

    public init(_ string: String) {
        units = Array(string.utf16)
    }

    /// One bulk copy — far cheaper than reading a long `NSString` (such as
    /// a text storage's) a character at a time.
    public init(_ string: NSString) {
        var units = [UInt16](repeating: 0, count: string.length)
        units.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            string.getCharacters(base, range: NSRange(location: 0, length: buffer.count))
        }
        self.units = units
    }

    public var length: Int { units.count }

    public func string(in range: NSRange) -> String {
        String(decoding: units[range.location..<NSMaxRange(range)], as: UTF16.self)
    }
}

/// The ASCII code units Markdown's syntax is made of.
enum ASCII {
    static let tab: UInt16 = 0x09
    static let lineFeed: UInt16 = 0x0A
    static let carriageReturn: UInt16 = 0x0D
    static let space: UInt16 = 0x20
    static let exclamation: UInt16 = 0x21   // !
    static let hash: UInt16 = 0x23          // #
    static let leftParen: UInt16 = 0x28     // (
    static let rightParen: UInt16 = 0x29    // )
    static let asterisk: UInt16 = 0x2A      // *
    static let plus: UInt16 = 0x2B          // +
    static let hyphen: UInt16 = 0x2D        // -
    static let period: UInt16 = 0x2E        // .
    static let colon: UInt16 = 0x3A         // :
    static let lessThan: UInt16 = 0x3C      // <
    static let greaterThan: UInt16 = 0x3E   // >
    static let upperX: UInt16 = 0x58        // X
    static let leftBracket: UInt16 = 0x5B   // [
    static let backslash: UInt16 = 0x5C     // \
    static let rightBracket: UInt16 = 0x5D  // ]
    static let underscore: UInt16 = 0x5F    // _
    static let backtick: UInt16 = 0x60      // `
    static let lowerX: UInt16 = 0x78        // x
    static let tilde: UInt16 = 0x7E         // ~
}

/// A toggle's marker, which says whether it's open. Not CommonMark — it
/// has no toggles — and not ASCII, so no Markdown text uses it by chance.
enum ToggleMarker {
    static let open: UInt16 = 0x25BE        // ▾
    static let closed: UInt16 = 0x25B8      // ▸

    static func string(open: Bool) -> String { open ? "\u{25BE}" : "\u{25B8}" }
}

extension UInt16 {
    var isSpaceOrTab: Bool { self == ASCII.space || self == ASCII.tab }

    var isASCIIDigit: Bool { self >= 0x30 && self <= 0x39 }

    var isASCIILetter: Bool { (self >= 0x41 && self <= 0x5A) || (self >= 0x61 && self <= 0x7A) }

    /// Every code unit `Character.isNewline` treats as a line break (CRLF is
    /// handled by the line splitter), so lines here match `NoteTitle`'s.
    var isLineTerminator: Bool {
        switch self {
        case 0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029: true
        default: false
        }
    }

    /// The characters a backslash can escape (CommonMark).
    var isASCIIPunctuation: Bool {
        (0x21...0x2F).contains(self) || (0x3A...0x40).contains(self)
            || (0x5B...0x60).contains(self) || (0x7B...0x7E).contains(self)
    }
}
