import Testing
import SwiftData
import Foundation
@testable import PopupNotesCore

@MainActor
@Suite struct WelcomeNoteTests {
    @Test func embedsTheHotkeyDisplayString() {
        #expect(WelcomeNote.text(hotKeyDisplay: "⌃⌘N").contains("⌃⌘N"))
        #expect(WelcomeNote.text(hotKeyDisplay: "⌥⌘J").contains("⌥⌘J"))
    }

    @Test func firstLineBecomesTheWelcomeTitle() {
        let text = WelcomeNote.text(hotKeyDisplay: "⌃⌘N")
        #expect(text.hasPrefix("Welcome to Popup Notes 👋\n"))
        #expect(NoteTitle.title(from: text) == "Welcome to Popup Notes 👋")
    }

    @Test func seedingCreatesExactlyOneWelcomeNote() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Note.self, configurations: config)
        let repo = NotesRepository(context: ModelContext(container))
        repo.create(text: WelcomeNote.text(hotKeyDisplay: "⌃⌘N"))
        repo.save()
        let all = repo.allSortedByModified()
        #expect(all.count == 1)
        #expect(all.first.map { NoteTitle.title(from: $0.text) } == "Welcome to Popup Notes 👋")
    }
}
