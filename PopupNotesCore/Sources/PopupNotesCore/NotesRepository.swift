import Foundation
import SwiftData

/// CRUD over the SwiftData store. Small-N notes app: fetches are unfiltered and
/// filtered in memory (avoids predicate edge cases; revisit if datasets grow).
@MainActor
public final class NotesRepository {
    private let context: ModelContext
    public init(context: ModelContext) { self.context = context }

    public func allSortedByModified() -> [Note] {
        let descriptor = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.modified, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    public func create(text: String = "") -> Note {
        let note = Note(text: text)
        context.insert(note)
        return note
    }

    public func delete(_ note: Note) { context.delete(note) }

    public func note(id: UUID) -> Note? {
        allSortedByModified().first { $0.id == id }
    }

    @discardableResult
    public func upsert(_ exported: ExportedNote) -> Note {
        if let existing = note(id: exported.id) {
            existing.text = exported.text
            existing.created = exported.created
            existing.modified = exported.modified
            return existing
        }
        let note = Note(id: exported.id, text: exported.text,
                        created: exported.created, modified: exported.modified)
        context.insert(note)
        return note
    }

    public func save() { try? context.save() }
}
