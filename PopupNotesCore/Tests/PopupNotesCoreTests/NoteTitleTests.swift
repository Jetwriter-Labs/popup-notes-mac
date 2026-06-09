import Testing
@testable import PopupNotesCore

@Suite struct NoteTitleTests {
    @Test func emptyIsNewNote() { #expect(NoteTitle.title(from: "") == "New Note") }
    @Test func whitespaceOnlyIsNewNote() { #expect(NoteTitle.title(from: "   \n\n ") == "New Note") }
    @Test func firstNonEmptyLine() { #expect(NoteTitle.title(from: "Hello\nworld") == "Hello") }
    @Test func skipsLeadingBlankLines() { #expect(NoteTitle.title(from: "\n\n  Groceries \nmilk") == "Groceries") }
}
