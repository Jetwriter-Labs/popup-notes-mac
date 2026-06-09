/// Derives a note's display title from its body: the first non-empty,
/// whitespace-trimmed line, or "New Note" when the body is blank.
public enum NoteTitle {
    public static func title(from text: String) -> String {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return "New Note"
    }
}
