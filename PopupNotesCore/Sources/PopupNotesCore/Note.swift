import Foundation
import SwiftData

@Model
public final class Note {
    public var id: UUID
    public var text: String
    public var created: Date
    public var modified: Date

    public init(id: UUID = UUID(), text: String = "", created: Date = .now, modified: Date = .now) {
        self.id = id
        self.text = text
        self.created = created
        self.modified = modified
    }

    /// Display title — first non-empty line of `text` (not persisted).
    public var title: String { NoteTitle.title(from: text) }

    /// Sidebar preview — the first non-empty line after the title (not persisted).
    public var preview: String { NoteTitle.preview(from: text) }

    /// Nothing but whitespace (or nothing at all): such a note holds no data,
    /// so it can be discarded without asking. Stops at the first real character.
    public var isBlank: Bool { text.allSatisfy(\.isWhitespace) }

    /// Still in the store. `isDeleted` alone isn't enough: once a deletion is
    /// saved, the model reports `isDeleted == false` with no context.
    public var isAlive: Bool { modelContext != nil && !isDeleted }
}
