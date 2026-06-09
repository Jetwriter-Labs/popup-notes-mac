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
