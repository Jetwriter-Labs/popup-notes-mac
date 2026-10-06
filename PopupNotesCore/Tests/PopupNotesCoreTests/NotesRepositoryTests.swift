import Testing
import SwiftData
import Foundation
@testable import PopupNotesCore

@MainActor
@Suite struct NotesRepositoryTests {
    private func repo() throws -> NotesRepository {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Note.self, configurations: config)
        return NotesRepository(context: ModelContext(container))
    }

    @Test func createAddsNote() throws {
        let r = try repo()
        r.create(text: "hi")
        #expect(r.allSortedByModified().count == 1)
    }
    @Test func sortsByModifiedDescending() throws {
        let r = try repo()
        let older = r.create(text: "old"); older.modified = Date(timeIntervalSince1970: 1)
        let newer = r.create(text: "new"); newer.modified = Date(timeIntervalSince1970: 2)
        #expect(r.allSortedByModified().first?.text == "new")
    }
    @Test func deleteRemoves() throws {
        let r = try repo()
        let n = r.create(text: "x")
        r.delete(n)
        #expect(r.allSortedByModified().isEmpty)
    }
    // MARK: Import

    private func exported(_ id: UUID, _ text: String, modified: TimeInterval) -> ExportedNote {
        ExportedNote(id: id, text: text, created: Date(timeIntervalSince1970: 1), modified: Date(timeIntervalSince1970: modified))
    }

    @Test func importAddsNewNotes() throws {
        let r = try repo()
        let summary = try r.importNotes([exported(UUID(), "a", modified: 10), exported(UUID(), "b", modified: 20)])
        #expect(summary == ImportSummary(added: 2))
        #expect(try r.allNotes().map(\.text) == ["b", "a"])
    }

    @Test func importKeepsANewerLocalEdit() throws {
        let r = try repo()
        let id = UUID()
        _ = try r.importNotes([exported(id, "backup text", modified: 100)])
        let local = try #require(try r.allNotes().first)
        local.text = "edited since the backup"
        local.modified = Date(timeIntervalSince1970: 200)

        let summary = try r.importNotes([exported(id, "backup text", modified: 100)])
        #expect(summary == ImportSummary(keptNewer: 1))
        #expect(local.text == "edited since the backup")
        #expect(local.modified == Date(timeIntervalSince1970: 200))
    }

    @Test func importAppliesANewerFileCopy() throws {
        let r = try repo()
        let id = UUID()
        _ = try r.importNotes([exported(id, "old", modified: 100)])
        let summary = try r.importNotes([exported(id, "new", modified: 300)])
        #expect(summary == ImportSummary(updated: 1))
        let note = try #require(try r.allNotes().first)
        #expect(note.text == "new")
        #expect(note.modified == Date(timeIntervalSince1970: 300))
    }

    /// Export drops fractional seconds, so a local edit made within the same
    /// second as the file's timestamp is a tie — and ties go to the file.
    @Test func importTreatsTheSameSecondAsATieTheFileWins() throws {
        let r = try repo()
        let id = UUID()
        _ = try r.importNotes([exported(id, "local", modified: 100)])
        let local = try #require(try r.allNotes().first)
        local.modified = Date(timeIntervalSince1970: 100.9)
        let summary = try r.importNotes([exported(id, "file", modified: 100)])
        #expect(summary == ImportSummary(updated: 1))
        #expect(local.text == "file")
    }

    @Test func importLeavesIdenticalTextAndItsDatesAlone() throws {
        let r = try repo()
        let id = UUID()
        _ = try r.importNotes([exported(id, "same", modified: 100)])
        let summary = try r.importNotes([exported(id, "same", modified: 999)])
        #expect(summary == ImportSummary(unchanged: 1))
        #expect(try r.allNotes().first?.modified == Date(timeIntervalSince1970: 100))
    }

    @Test func reimportingYourOwnExportChangesNothing() throws {
        let r = try repo()
        r.create(text: "one"); r.create(text: "two")
        let file = try NotesJSON.decode(NotesJSON.encode(r.allNotes().map(ExportedNote.init)))
        let summary = try r.importNotes(file)
        #expect(summary == ImportSummary(unchanged: 2))
        #expect(try r.allNotes().count == 2)
    }

    @Test func aDuplicateIDInOneFileYieldsOneNoteWithTheLastEntry() throws {
        let r = try repo()
        let id = UUID()
        let summary = try r.importNotes([exported(id, "first", modified: 10), exported(id, "second", modified: 5)])
        #expect(summary == ImportSummary(added: 1))
        let all = try r.allNotes()
        #expect(all.count == 1)
        #expect(all.first?.text == "second")
    }

    // MARK: Blank notes

    @Test func aliveUntilDeletedEvenAfterTheDeleteIsSaved() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Note.self, configurations: config)
        let context = ModelContext(container)
        let r = NotesRepository(context: context)
        let note = r.create(text: "x")
        #expect(note.isAlive)
        r.delete(note)
        #expect(!note.isAlive)
        try r.save()
        #expect(!note.isAlive)
    }

    @Test func blankMeansOnlyWhitespace() {
        #expect(Note(text: "").isBlank)
        #expect(Note(text: " \n\t\r\n\u{00A0}").isBlank)
        #expect(!Note(text: "  x ").isBlank)
    }

    @Test func upsertInsertsThenUpdatesSameID() throws {
        let r = try repo()
        let id = UUID(); let d = Date(timeIntervalSince1970: 5)
        r.upsert(ExportedNote(id: id, text: "first", created: d, modified: d))
        r.upsert(ExportedNote(id: id, text: "second", created: d, modified: d))
        let all = r.allSortedByModified()
        #expect(all.count == 1)
        #expect(all.first?.text == "second")
    }
}
