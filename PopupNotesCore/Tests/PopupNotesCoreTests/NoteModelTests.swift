import Testing
import Foundation
@testable import PopupNotesCore

@Suite struct NoteModelTests {
    @Test func titleReflectsText() {
        let note = Note(text: "Shopping\nmilk")
        #expect(note.title == "Shopping")
    }
    @Test func exportedFromNoteCopiesValues() {
        let d = Date(timeIntervalSince1970: 1_000_000)
        let id = UUID()
        let note = Note(id: id, text: "hi", created: d, modified: d)
        let e = ExportedNote(note)
        #expect(e.id == id)
        #expect(e.text == "hi")
        #expect(e.created == d)
        #expect(e.modified == d)
    }
}
