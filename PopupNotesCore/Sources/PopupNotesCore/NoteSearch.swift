import Foundation

/// Filters notes by a user-typed query: a case- and diacritic-insensitive
/// substring match against the note's full text. A blank query matches all.
/// Pure (no SwiftData fetch) and mirrors `NoteTitle` — unit-tested in Core.
public enum NoteSearch {
    /// True when `text` contains `query` (case- + diacritic-insensitive).
    /// A blank / whitespace-only query matches everything.
    public static func matches(_ text: String, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return text.localizedStandardContains(trimmed)
    }

    /// The subset of `notes` whose `text` matches `query`, order preserved.
    /// A blank / whitespace-only query returns `notes` unchanged.
    public static func filter(_ notes: [Note], matching query: String) -> [Note] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return notes }
        return notes.filter { $0.text.localizedStandardContains(trimmed) }
    }
}
