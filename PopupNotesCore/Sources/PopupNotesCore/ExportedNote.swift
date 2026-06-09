import Foundation

/// Plain JSON-facing representation of a note, decoupled from the @Model class
/// so the export/import codec stays pure and testable.
public struct ExportedNote: Codable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var created: Date
    public var modified: Date

    public init(id: UUID, text: String, created: Date, modified: Date) {
        self.id = id
        self.text = text
        self.created = created
        self.modified = modified
    }

    public init(_ note: Note) {
        self.init(id: note.id, text: note.text, created: note.created, modified: note.modified)
    }
}
