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
    @Test func usesISO8601Dates() throws {
        let d = Date(timeIntervalSince1970: 0)
        let data = try NotesJSON.encode([ExportedNote(id: UUID(), text: "x", created: d, modified: d)])
        #expect(String(decoding: data, as: UTF8.self).contains("1970-01-01T00:00:00Z"))
    }
}
