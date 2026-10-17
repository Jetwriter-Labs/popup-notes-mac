import Foundation

/// A heading as the outline lists it.
public struct MarkdownHeading: Equatable, Sendable {
    /// 1 for `#` … 6 for `######`.
    public var level: Int
    /// How far the outline indents it: the number of headings it sits
    /// under. A `###` directly below a `#` is one step in, not two.
    public var depth: Int
    /// The heading as it reads, without Markdown syntax.
    public var title: String
    /// The heading's line (without its line break), in UTF-16 offsets.
    public var range: NSRange

    public init(level: Int, depth: Int, title: String, range: NSRange) {
        self.level = level
        self.depth = depth
        self.title = title
        self.range = range
    }
}

/// A note's table of contents: its headings, in order.
public enum MarkdownOutline {
    /// Titles past this are never visible in the outline's one-line rows.
    static let maxTitleLength = 200

    public static func headings(in text: String) -> [MarkdownHeading] {
        let text = MarkdownText(text)
        return headings(in: MarkdownBlocks.lines(in: text), of: text)
    }

    /// Headings with no title (a bare `#`) are left out: there's nothing to
    /// show or click.
    public static func headings(in lines: [MarkdownLine], of text: MarkdownText) -> [MarkdownHeading] {
        var headings: [MarkdownHeading] = []
        var openLevels: [Int] = []
        for line in lines {
            guard case .heading(let level) = line.block else { continue }
            let title = MarkdownInline.plainText(in: text, range: line.content)
                .trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            while let last = openLevels.last, last >= level { openLevels.removeLast() }
            headings.append(MarkdownHeading(level: level, depth: openLevels.count,
                                            title: String(title.prefix(maxTitleLength)),
                                            range: line.range))
            openLevels.append(level)
        }
        return headings
    }

    /// The heading whose section holds `location`: the last one that starts
    /// at or before it, or nil above the first heading.
    public static func section(containing location: Int, in headings: [MarkdownHeading]) -> Int? {
        var low = 0
        var high = headings.count
        while low < high {
            let mid = (low + high) / 2
            if headings[mid].range.location <= location { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? nil : low - 1
    }
}
