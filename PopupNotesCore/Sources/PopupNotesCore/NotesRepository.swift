import Foundation
import SwiftData

/// CRUD over the SwiftData store. Small-N notes app: fetches are unfiltered and
/// filtered in memory (avoids predicate edge cases; revisit if datasets grow).
@MainActor
public final class NotesRepository {
    private let context: ModelContext
    public init(context: ModelContext) { self.context = context }

    /// Every note, newest first. Throws instead of pretending the store is
    /// empty: a partially corrupt store opens fine and fails only here, and
    /// treating that as "no notes" would make import duplicate every note
    /// and export overwrite a good backup with an empty file.
    public func allNotes() throws -> [Note] {
        try context.fetch(FetchDescriptor<Note>(sortBy: [SortDescriptor(\.modified, order: .reverse)]))
    }

    public func allSortedByModified() -> [Note] {
        (try? allNotes()) ?? []
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

    /// Merges an export file into the store with one fetch (not one per note).
    ///
    /// A note whose id is new is added. For an id that exists here, the file's
    /// copy replaces the local one only when it is at least as new, so
    /// importing an old backup can't roll back edits made since. Export
    /// writes whole-second dates, so both sides are compared at one-second
    /// precision; a tie goes to the file (a hand-edited file still applies).
    /// Identical text is left untouched. If an id appears twice in the file,
    /// its last entry is used. Does not save.
    public func importNotes(_ incoming: [ExportedNote]) throws -> ImportSummary {
        // Note.id isn't unique in the schema: keep the newest if it repeats.
        let local = Dictionary(try allNotes().map { ($0.id, $0) }, uniquingKeysWith: { newest, _ in newest })
        var latest: [UUID: ExportedNote] = [:]
        var order: [UUID] = []
        for note in incoming {
            if latest.updateValue(note, forKey: note.id) == nil { order.append(note.id) }
        }

        var summary = ImportSummary()
        for id in order {
            guard let file = latest[id] else { continue }
            guard let existing = local[id] else {
                let note = Note(id: file.id, text: file.text, created: file.created, modified: file.modified)
                context.insert(note)
                summary.added += 1
                continue
            }
            if existing.text == file.text {
                summary.unchanged += 1
            } else if Self.wholeSeconds(file.modified) >= Self.wholeSeconds(existing.modified) {
                existing.text = file.text
                existing.created = file.created
                existing.modified = file.modified
                summary.updated += 1
            } else {
                summary.keptNewer += 1
            }
        }
        return summary
    }

    private static func wholeSeconds(_ date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.rounded(.down)
    }

    public func save() throws { try context.save() }
}

/// What `NotesRepository.importNotes(_:)` did, counted per distinct note id.
public struct ImportSummary: Equatable, Sendable {
    public var added = 0
    public var updated = 0
    public var unchanged = 0
    /// Notes left as they are because the copy on this Mac is newer.
    public var keptNewer = 0

    public init(added: Int = 0, updated: Int = 0, unchanged: Int = 0, keptNewer: Int = 0) {
        self.added = added
        self.updated = updated
        self.unchanged = unchanged
        self.keptNewer = keptNewer
    }
}
