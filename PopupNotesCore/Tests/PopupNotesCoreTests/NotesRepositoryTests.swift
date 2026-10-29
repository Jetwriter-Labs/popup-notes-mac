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

    /// `title: nil` makes a note from a file exported before notes had titles.
    private func exported(_ id: UUID, _ text: String, title: String? = "", modified: TimeInterval) -> ExportedNote {
        ExportedNote(id: id, title: title, text: text, created: Date(timeIntervalSince1970: 1),
                     modified: Date(timeIntervalSince1970: modified))
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
        r.upsert(ExportedNote(id: id, title: "", text: "first", created: d, modified: d))
        r.upsert(ExportedNote(id: id, title: "", text: "second", created: d, modified: d))
        let all = r.allSortedByModified()
        #expect(all.count == 1)
        #expect(all.first?.text == "second")
    }

    // MARK: Titles

    @Test func importKeepsTitlesFromAFileThatHasThem() throws {
        let r = try repo()
        let id = UUID()
        let file = ExportedNote(id: id, title: "", text: "# Plan\nbody", created: .now, modified: .now)
        #expect(try r.importNotes([file]) == ImportSummary(added: 1))
        let note = try #require(try r.allNotes().first)
        #expect(note.title == "") // an empty title is a choice, not a file from before titles
        #expect(note.text == "# Plan\nbody")
    }

    @Test func importGivesNotesFromBeforeTitlesTheirFirstLine() throws {
        let r = try repo()
        #expect(try r.importNotes([exported(UUID(), "# Plan\n\nbody", title: nil, modified: 10),
                                   exported(UUID(), "- milk\n- eggs", title: nil, modified: 20)]) == ImportSummary(added: 2))
        let notes = try r.allNotes()
        #expect(notes.map(\.title) == ["", "Plan"])
        #expect(notes.map(\.text) == ["- milk\n- eggs", "body"])
    }

    /// An old backup imported after upgrading matches the notes as upgrading left them.
    @Test func reimportingABackupFromBeforeTitlesChangesNothing() throws {
        let r = try repo()
        let id = UUID()
        r.create(text: "Groceries\nmilk").id = id
        let backup = exported(id, "Groceries\nmilk", title: nil, modified: 100)
        #expect(try r.moveFirstLinesIntoTitles() == 1)
        #expect(try r.importNotes([backup]) == ImportSummary(unchanged: 1))
    }

    @Test func importAppliesANewerTitle() throws {
        let r = try repo()
        let id = UUID()
        _ = try r.importNotes([ExportedNote(id: id, title: "Old", text: "same", created: .distantPast,
                                            modified: Date(timeIntervalSince1970: 100))])
        let summary = try r.importNotes([ExportedNote(id: id, title: "New", text: "same", created: .distantPast,
                                                      modified: Date(timeIntervalSince1970: 200))])
        #expect(summary == ImportSummary(updated: 1))
        #expect(try r.allNotes().first?.title == "New")
    }

    @Test func movingFirstLinesIntoTitlesLeavesTitledNotesAndDatesAlone() throws {
        let r = try repo()
        let untitled = r.create(text: "# Plan\nbody")
        untitled.modified = Date(timeIntervalSince1970: 50)
        let titled = r.create(title: "Mine", text: "# Heading stays\nbody")
        let list = r.create(text: "- milk")
        #expect(try r.moveFirstLinesIntoTitles() == 1)
        #expect((untitled.title, untitled.text) == ("Plan", "body"))
        #expect(untitled.modified == Date(timeIntervalSince1970: 50))
        #expect((titled.title, titled.text) == ("Mine", "# Heading stays\nbody"))
        #expect((list.title, list.text) == ("", "- milk"))
        #expect(try r.moveFirstLinesIntoTitles() == 0) // nothing left to move
    }

    /// A store from before titles opens with the new model: SwiftData adds
    /// the column, every note untitled, nothing else touched.
    @Test func aStoreFromBeforeTitlesOpensWithEveryNoteIntact() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PopupNotesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Notes.store")
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try {
            let old = try ModelContainer(for: Schema(versionedSchema: NoteSchemaV1.self),
                                         configurations: ModelConfiguration(url: url))
            let context = ModelContext(old)
            context.insert(NoteSchemaV1.Note(id: id, text: "# Plan\nbody", created: date, modified: date))
            try context.save()
        }()
        let container = try ModelContainer(for: Note.self, configurations: ModelConfiguration(url: url))
        let notes = try ModelContext(container).fetch(FetchDescriptor<Note>())
        #expect(notes.count == 1)
        #expect(notes.first?.id == id)
        #expect(notes.first?.title == "")
        #expect(notes.first?.text == "# Plan\nbody")
        #expect(notes.first?.modified == date)
    }
}

/// The model as shipped before notes had titles, to make a store from then.
enum NoteSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Note.self] }

    @Model
    final class Note {
        var id: UUID
        var text: String
        var created: Date
        var modified: Date

        init(id: UUID, text: String, created: Date, modified: Date) {
            self.id = id
            self.text = text
            self.created = created
            self.modified = modified
        }
    }
}
