import Testing
@testable import PopupNotesCore

@Suite struct NoteSelectionTests {
    @Test func selectsTheNoteThatSlidesIntoTheRow() {
        #expect(NoteSelection.neighbor(ofRemoving: "b", in: ["a", "b", "c"]) == "c")
        #expect(NoteSelection.neighbor(ofRemoving: "a", in: ["a", "b", "c"]) == "b")
    }

    @Test func fallsBackToTheNoteAboveAtTheBottom() {
        #expect(NoteSelection.neighbor(ofRemoving: "c", in: ["a", "b", "c"]) == "b")
    }

    @Test func nothingIsLeftAfterTheLastNote() {
        #expect(NoteSelection.neighbor(ofRemoving: "a", in: ["a"]) == nil)
    }

    @Test func anUnknownIDHasNoNeighbor() {
        #expect(NoteSelection.neighbor(ofRemoving: "x", in: ["a", "b"]) == nil)
    }
}
