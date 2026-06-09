import Testing
import Foundation
@testable import PopupNotesCore

@Suite struct NoteFileTests {
    /// A unique temp file URL inside a fresh directory we control.
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("popupnotes-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("scratchpad.md", isDirectory: false)
    }

    @Test func writeThenReadRoundTrips() throws {
        let file = NoteFile(url: tempFileURL())
        try file.write("hello 🌍\nsecond line")
        #expect(try file.read() == "hello 🌍\nsecond line")
        try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent())
    }

    @Test func writeCreatesIntermediateDirectories() throws {
        let file = NoteFile(url: tempFileURL())
        #expect(!file.exists)
        try file.write("x")
        #expect(file.exists)
        try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent())
    }

    @Test func readMissingFileThrows() {
        let file = NoteFile(url: tempFileURL())
        #expect(throws: (any Error).self) { try file.read() }
    }

    @Test func writeOverwritesExistingContent() throws {
        let file = NoteFile(url: tempFileURL())
        try file.write("first")
        try file.write("second")
        #expect(try file.read() == "second")
        try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent())
    }

    @Test func defaultFileIsUnderApplicationSupport() throws {
        let file = try NoteFile.defaultFile()
        #expect(file.url.lastPathComponent == "scratchpad.md")
        #expect(file.url.deletingLastPathComponent().lastPathComponent == "PopupNotes")
        #expect(file.url.path.contains("Application Support"))
    }
}
