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
}
