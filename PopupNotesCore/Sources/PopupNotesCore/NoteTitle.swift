import Foundation

/// Derives a note's sidebar text from its body: the title is the first
/// non-blank line, whitespace-trimmed, or "New Note" when the body is blank;
/// the preview is the next non-blank line after it. Both read as the editor
/// shows them, without Markdown syntax: `# Plan` is titled "Plan".
///
/// Both run for the edited row on every keystroke, so they scan only as far
/// as they must — the cost never grows with the note's length. Any newline
/// kind ends a line: in Swift "\r\n" is a single Character, so splitting on
/// "\n" alone would treat CRLF text (imports, pasted Windows text) as one
/// giant line.
public enum NoteTitle {
    /// Longest title or preview returned. The sidebar shows one truncated
    /// line, so anything longer is never visible and only costs layout.
    public static let maxLength = 120
    /// How far into a note `preview(from:)` looks for the line after the title.
    static let previewScanLimit = 2_000

    public static func title(from text: String) -> String {
        let start = text.drop(while: \.isWhitespace) // skips blank lines + indentation
        return start.isEmpty ? "New Note" : withoutMarkdown(line(startingAt: start))
    }

    public static func preview(from text: String) -> String {
        let window = text.prefix(previewScanLimit)
        let title = window.drop(while: \.isWhitespace)
        guard let titleEnd = title.firstIndex(where: \.isNewline) else { return "" }
        let next = window[titleEnd...].drop(while: \.isWhitespace)
        return next.isEmpty ? "" : withoutMarkdown(line(startingAt: next))
    }

    /// The line as it reads: no heading `#`s, list or quote markers,
    /// emphasis or code backticks; a link shows its text. A line that is
    /// nothing but syntax (a bare `#`, a `---` rule, a code fence) is kept
    /// as typed rather than turned into nothing.
    static func withoutMarkdown(_ line: String) -> String {
        let text = MarkdownText(line)
        guard let parsed = MarkdownBlocks.lines(in: text).first else { return line }
        switch parsed.block {
        case .heading, .listItem, .quote, .paragraph:
            let plain = MarkdownInline.plainText(in: text, range: parsed.content)
                .trimmingCharacters(in: .whitespaces)
            return plain.isEmpty ? line : plain
        case .blank, .fence, .code, .rule:
            return line
        }
    }

    /// The line that `start` begins (its first Character is not whitespace),
    /// capped at `maxLength` Characters, without trailing whitespace.
    private static func line(startingAt start: Substring) -> String {
        let line = start.prefix(maxLength).prefix { !$0.isNewline }
        var end = line.endIndex
        while end > line.startIndex, line[line.index(before: end)].isWhitespace {
            end = line.index(before: end)
        }
        return String(line[..<end])
    }
}
