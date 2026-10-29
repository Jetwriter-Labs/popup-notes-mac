import Testing
import Foundation
@testable import PopupNotesCore

@Suite struct NotesJSONTests {
    @Test func roundTrips() throws {
        let d = Date(timeIntervalSince1970: 1_700_000_000)
        let notes = [ExportedNote(id: UUID(), title: "T", text: "a\nb", created: d, modified: d)]
        let data = try NotesJSON.encode(notes)
        #expect(try NotesJSON.decode(data) == notes)
    }
    @Test func malformedThrows() {
        #expect(throws: (any Error).self) {
            _ = try NotesJSON.decode(Data("not json".utf8))
        }
    }
    /// Pins the export file format (spec §6) so old backups keep importing.
    @Test func decodesAPinnedExportFile() throws {
        let file = #"""
        [
          {
            "created" : "2026-06-09T10:00:00Z",
            "id" : "6F1C2B9E-6C4E-4C0F-9B1E-2A6D5C3F7A10",
            "modified" : "2026-06-10T11:30:00Z",
            "text" : "Groceries\nmilk"
          }
        ]
        """#
        let notes = try NotesJSON.decode(Data(file.utf8))
        #expect(notes.count == 1)
        #expect(notes[0].id == UUID(uuidString: "6F1C2B9E-6C4E-4C0F-9B1E-2A6D5C3F7A10"))
        #expect(notes[0].title == nil) // from before titles
        #expect(notes[0].text == "Groceries\nmilk")
        #expect(notes[0].created == Date(timeIntervalSince1970: 1_780_999_200))
        #expect(notes[0].modified == Date(timeIntervalSince1970: 1_781_091_000))
    }

    /// Pins the format with titles: every note exported has one, empty or not.
    @Test func decodesAPinnedExportFileWithTitles() throws {
        let file = #"""
        [
          {
            "created" : "2026-10-30T10:00:00Z",
            "id" : "0B3D6E2A-9F4C-4A1E-8C2D-5E7F9A1B3C4D",
            "modified" : "2026-10-30T11:00:00Z",
            "text" : "milk",
            "title" : "Groceries"
          }
        ]
        """#
        let notes = try NotesJSON.decode(Data(file.utf8))
        #expect(notes.map(\.title) == ["Groceries"])
        #expect(notes.map(\.text) == ["milk"])
    }

    @Test func encodesExactlyTheDocumentedKeys() throws {
        let note = Note(title: "", text: "x")
        let data = try NotesJSON.encode([ExportedNote(note)])
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(object.first.map { Set($0.keys) } == ["created", "id", "modified", "text", "title"])
    }

    /// Export dates are whole seconds: anything comparing imported dates
    /// against live ones (which carry fractions) must allow for that.
    @Test func exportTruncatesSubSecondDates() throws {
        let precise = Date(timeIntervalSince1970: 1_700_000_000.789)
        let data = try NotesJSON.encode([ExportedNote(id: UUID(), text: "x", created: precise, modified: precise)])
        let decoded = try NotesJSON.decode(data)
        #expect(decoded[0].modified == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func usesISO8601Dates() throws {
        let d = Date(timeIntervalSince1970: 0)
        let data = try NotesJSON.encode([ExportedNote(id: UUID(), text: "x", created: d, modified: d)])
        #expect(String(decoding: data, as: UTF8.self).contains("1970-01-01T00:00:00Z"))
    }
}
