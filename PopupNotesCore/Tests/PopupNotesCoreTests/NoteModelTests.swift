import Testing
import Foundation
@testable import PopupNotesCore

@Suite struct NoteModelTests {
    @Test func untitledItGoesByItsFirstLine() {
        let note = Note(text: "Shopping\nmilk")
        #expect(note.title == "")
        #expect(note.displayTitle == "Shopping")
        #expect(note.preview == "milk")
    }
    @Test func itsTitleNamesIt() {
        let note = Note(title: "Errands", text: "Shopping\nmilk")
        #expect(note.displayTitle == "Errands")
        #expect(note.preview == "Shopping")
    }
    @Test func blankMeansTitleAndTextAreBlank() {
        #expect(Note(title: " ", text: "\n").isBlank)
        #expect(!Note(title: "Idea", text: "").isBlank)
        #expect(!Note(title: "", text: "x").isBlank)
    }
    @Test func exportedFromNoteCopiesValues() {
        let d = Date(timeIntervalSince1970: 1_000_000)
        let id = UUID()
        let note = Note(id: id, title: "T", text: "hi", created: d, modified: d)
        let e = ExportedNote(note)
        #expect(e.id == id)
        #expect(e.title == "T")
        #expect(e.text == "hi")
        #expect(e.created == d)
        #expect(e.modified == d)
    }
}
