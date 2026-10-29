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

    @Test func hasATitleOfItsOwn() {
        #expect(WelcomeNote.title == "Welcome to Popup Notes 👋")
        #expect(!WelcomeNote.text(hotKeyDisplay: "⌃⌘N").contains("Welcome to Popup Notes"))
    }

    @Test func showsAClosedToggleToOpen() {
        let lines = MarkdownBlocks.lines(in: MarkdownText(WelcomeNote.text(hotKeyDisplay: "⌃⌘N")))
        #expect(lines.contains { $0.block == .toggle(isOpen: false) })
        #expect(lines.filter(\.isHidden).count == 1)
    }

    @Test func headingsFillTheOutline() {
        let headings = MarkdownOutline.headings(in: WelcomeNote.text(hotKeyDisplay: "⌃⌘N"))
        #expect(headings.count >= 2)
        #expect(headings.first?.title == "Basics")
    }

    @Test func seedingCreatesExactlyOneWelcomeNote() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Note.self, configurations: config)
        let repo = NotesRepository(context: ModelContext(container))
        repo.create(title: WelcomeNote.title, text: WelcomeNote.text(hotKeyDisplay: "⌃⌘N"))
        try repo.save()
        let all = repo.allSortedByModified()
        #expect(all.count == 1)
        #expect(all.first?.displayTitle == "Welcome to Popup Notes 👋")
    }
}
