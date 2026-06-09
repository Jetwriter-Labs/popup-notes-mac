import Testing
import Foundation
@testable import PopupNotesCore

@Suite struct NoteSearchTests {
    // MARK: matches(_:query:)
    @Test func emptyQueryMatchesAll() { #expect(NoteSearch.matches("anything", query: "")) }
    @Test func whitespaceQueryMatchesAll() { #expect(NoteSearch.matches("anything", query: "  \n ")) }
    @Test func caseInsensitive() { #expect(NoteSearch.matches("a Note here", query: "NOTE")) }
    @Test func diacriticInsensitive() { #expect(NoteSearch.matches("le café", query: "cafe")) }
    @Test func substringMatches() { #expect(NoteSearch.matches("groceries", query: "cer")) }
    @Test func noMatch() { #expect(!NoteSearch.matches("hello world", query: "zzz")) }

    // MARK: filter(_:matching:)
    @Test func filterEmptyReturnsAll() {
        let notes = [Note(text: "one"), Note(text: "two")]
        #expect(NoteSearch.filter(notes, matching: "  ").count == 2)
    }
    @Test func filterMatchesBodyNotJustTitle() {
        let a = Note(text: "Groceries\nmilk and eggs")
        let b = Note(text: "Ideas\nbuild an app")
        let result = NoteSearch.filter([a, b], matching: "eggs")
        #expect(result.count == 1)
        #expect(result.first?.id == a.id)
    }
    @Test func filterPreservesOrder() {
        let a = Note(text: "alpha note")
        let b = Note(text: "beta note")
        let result = NoteSearch.filter([a, b], matching: "note")
        #expect(result.map(\.id) == [a.id, b.id])
    }
    @Test func filterNoMatchIsEmpty() {
        let notes = [Note(text: "one"), Note(text: "two")]
        #expect(NoteSearch.filter(notes, matching: "zzz").isEmpty)
    }
}
