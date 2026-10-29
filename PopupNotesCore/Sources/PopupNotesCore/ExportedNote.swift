import Foundation

/// Plain JSON-facing representation of a note, decoupled from the @Model class
/// so the export/import codec stays pure and testable.
public struct ExportedNote: Codable, Equatable, Sendable {
    public var id: UUID
    /// Nil only in files exported before notes had titles, whose text still
    /// starts with the line that named the note: importing gives it a title
    /// the way upgrading did (see `NoteTitle.split`).
    public var title: String?
    public var text: String
    public var created: Date
    public var modified: Date

    public init(id: UUID, title: String? = nil, text: String, created: Date, modified: Date) {
        self.id = id
        self.title = title
        self.text = text
        self.created = created
        self.modified = modified
    }

    public init(_ note: Note) {
        self.init(id: note.id, title: note.title, text: note.text, created: note.created, modified: note.modified)
    }

    /// The title and text the note gets here.
    var content: (title: String, text: String) {
        if let title { return (title, text) }
        return NoteTitle.split(text) ?? ("", text)
    }
}
