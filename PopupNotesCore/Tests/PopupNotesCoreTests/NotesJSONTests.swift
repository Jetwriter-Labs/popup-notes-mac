import Testing
import Foundation
@testable import PopupNotesCore

@Suite struct NotesJSONTests {
    @Test func roundTrips() throws {
        let d = Date(timeIntervalSince1970: 1_700_000_000)
        let notes = [ExportedNote(id: UUID(), text: "a\nb", created: d, modified: d)]
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
        #expect(notes[0].text == "Groceries\nmilk")
        #expect(notes[0].created == Date(timeIntervalSince1970: 1_780_999_200))
        #expect(notes[0].modified == Date(timeIntervalSince1970: 1_781_091_000))
    }

    @Test func encodesExactlyTheDocumentedKeys() throws {
        let data = try NotesJSON.encode([ExportedNote(id: UUID(), text: "x", created: .now, modified: .now)])
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(object.first.map { Set($0.keys) } == ["created", "id", "modified", "text"])
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
