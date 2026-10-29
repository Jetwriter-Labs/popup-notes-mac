import Foundation
import SwiftData

@Model
public final class Note {
    public var id: UUID
    /// Typed in its own field above the text: plain text, one line. Empty
    /// when the note has none — the sidebar then goes by the text's first
    /// line. The default lets stores from before titles open as they are.
    public var title: String = ""
    public var text: String
    public var created: Date
    public var modified: Date

    public init(id: UUID = UUID(), title: String = "", text: String = "", created: Date = .now,
                modified: Date = .now) {
        self.id = id
        self.title = title
        self.text = text
        self.created = created
        self.modified = modified
    }

    /// What the sidebar calls the note: its title, or its text's first line
    /// while it has none (not persisted).
    public var displayTitle: String { NoteTitle.title(title, text: text) }

    /// Sidebar preview — the first line of text that doesn't name the note (not persisted).
    public var preview: String { NoteTitle.preview(title: title, text: text) }

    /// Nothing but whitespace (or nothing at all), title included: such a
    /// note holds no data, so it can be discarded without asking. Stops at
    /// the first real character.
    public var isBlank: Bool { title.allSatisfy(\.isWhitespace) && text.allSatisfy(\.isWhitespace) }

    /// Still in the store. `isDeleted` alone isn't enough: once a deletion is
    /// saved, the model reports `isDeleted == false` with no context.
    public var isAlive: Bool { modelContext != nil && !isDeleted }
}
