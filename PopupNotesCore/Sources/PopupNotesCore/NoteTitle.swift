import Foundation

/// Derives a note's sidebar text. A note's title is its own field; while it
/// has none, the first non-blank line of its text names it instead —
/// whitespace-trimmed, or "New Note" when the text is blank too. The
/// preview is the first line after whatever named the note. Lines from the
/// text read as the editor shows them, without Markdown syntax: `# Plan` is
/// "Plan". A title is plain text and shows as typed.
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

    /// The sidebar's name for a note: its title, or its text's first line.
    public static func title(_ title: String, text: String) -> String {
        let start = title.drop(while: \.isWhitespace)
        return start.isEmpty ? self.title(from: text) : line(startingAt: start)
    }

    /// The sidebar's second line: under a title, the text's first line;
    /// without one, the line after the first, which names the note.
    public static func preview(title: String, text: String) -> String {
        if title.allSatisfy(\.isWhitespace) { return preview(from: text) }
        return firstLine(of: text.prefix(previewScanLimit))
    }

    /// The first non-blank line of an untitled note's text.
    public static func title(from text: String) -> String {
        let start = text.drop(while: \.isWhitespace) // skips blank lines + indentation
        return start.isEmpty ? "New Note" : withoutMarkdown(line(startingAt: start))
    }

    /// The line after an untitled note's first line.
    public static func preview(from text: String) -> String {
        let window = text.prefix(previewScanLimit)
        let title = window.drop(while: \.isWhitespace)
        guard let titleEnd = title.firstIndex(where: \.isNewline) else { return "" }
        return firstLine(of: window[titleEnd...])
    }

    /// A title as the field keeps it: on one line, line breaks (typed with
    /// ⌥↩ or pasted) turned into spaces.
    public static func singleLine(_ typed: String) -> String {
        guard typed.contains(where: \.isNewline) else { return typed }
        return String(typed.map { $0.isNewline ? " " : $0 })
    }

    /// How notes from before titles had fields of their own get one: their
    /// first non-blank line — the one that named them — moves out of the
    /// text into the title, `#`s and all, along with the blank lines around
    /// it. Only a heading or a plain line, though: a list item, quote,
    /// toggle, code or rule is part of the note rather than its name. And
    /// only when the plain-text title loses nothing: a line with emphasis,
    /// code or a link in it stays (`**` would vanish, a link's address
    /// too), as does one longer than `maxLength`, more paragraph than
    /// title. Nil when the line stays; the sidebar then shows it as before.
    public static func split(_ text: String) -> (title: String, text: String)? {
        let start = text.drop(while: \.isWhitespace)
        let lineEnd = start.firstIndex(where: \.isNewline) ?? start.endIndex
        let line = MarkdownText(String(start[..<lineEnd]))
        guard let parsed = MarkdownBlocks.lines(in: line).first else { return nil }
        switch parsed.block {
        case .heading, .paragraph: break
        case .blank, .listItem, .quote, .toggle, .fence, .code, .rule: return nil
        }
        let title = line.string(in: parsed.content).trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, title.count <= maxLength,
              MarkdownInline.plainText(in: line, range: parsed.content).trimmingCharacters(in: .whitespaces) == title
        else { return nil }
        // The title's line break and the blank lines after it — not the
        // indentation of the line that comes next.
        var rest = start[lineEnd...]
        while let newline = rest.firstIndex(where: \.isNewline), rest[..<newline].allSatisfy(\.isWhitespace) {
            rest = rest[rest.index(after: newline)...]
        }
        return (title, rest.allSatisfy(\.isWhitespace) ? "" : String(rest))
    }

    /// The line as it reads: no heading `#`s, list, quote or toggle markers,
    /// emphasis or code backticks; a link shows its text. A line that is
    /// nothing but syntax (a bare `#`, a `---` rule, a code fence) is kept
    /// as typed rather than turned into nothing.
    static func withoutMarkdown(_ line: String) -> String {
        let text = MarkdownText(line)
        guard let parsed = MarkdownBlocks.lines(in: text).first else { return line }
        switch parsed.block {
        case .heading, .listItem, .quote, .toggle, .paragraph:
            let plain = MarkdownInline.plainText(in: text, range: parsed.content)
                .trimmingCharacters(in: .whitespaces)
            return plain.isEmpty ? line : plain
        case .blank, .fence, .code, .rule:
            return line
        }
    }

    /// The first non-blank line of `text`, as it reads; empty if there is none.
    private static func firstLine(of text: Substring) -> String {
        let start = text.drop(while: \.isWhitespace)
        return start.isEmpty ? "" : withoutMarkdown(line(startingAt: start))
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
