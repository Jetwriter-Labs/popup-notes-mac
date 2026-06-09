import Testing
import Foundation
@testable import PopupNotesCore

@Suite @MainActor struct NoteStoreTests {
    private func freshFile() -> NoteFile {
        NoteFile(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("popupnotes-store-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("scratchpad.md", isDirectory: false))
    }

    @Test func loadsEmptyWhenFileMissing() {
        let store = NoteStore(file: freshFile(), autosave: ManualDebouncer())
        #expect(store.text == "")
    }

    @Test func loadsExistingFileContents() throws {
        let file = freshFile()
        try file.write("existing note")
        let store = NoteStore(file: file, autosave: ManualDebouncer())
        #expect(store.text == "existing note")
    }

    @Test func updateTextSchedulesDebouncedSave() throws {
        let file = freshFile()
        let debouncer = ManualDebouncer()
        let store = NoteStore(file: file, autosave: debouncer)
        store.updateText("typed")
        #expect(!file.exists)        // not written until the debounce fires
        debouncer.fireNow()
        #expect(try file.read() == "typed")
    }

    @Test func rapidUpdatesCoalesceToLatestValue() throws {
        let file = freshFile()
        let debouncer = ManualDebouncer()
        let store = NoteStore(file: file, autosave: debouncer)
        store.updateText("a")
        store.updateText("ab")
        store.updateText("abc")
        debouncer.fireNow()
        #expect(try file.read() == "abc")
    }

    @Test func flushSavesImmediately() throws {
        let file = freshFile()
        let store = NoteStore(file: file, autosave: ManualDebouncer())
        store.updateText("note")
        store.flush()
        #expect(try file.read() == "note")
    }

    @Test func doesNotOverwriteUnreadableFileUntilEdited() throws {
        // Simulate an unreadable existing file by putting a *directory* at the
        // note's path, so read() throws.
        let file = freshFile()
        try FileManager.default.createDirectory(at: file.url, withIntermediateDirectories: true)
        let store = NoteStore(file: file, autosave: ManualDebouncer())
        #expect(store.text == "")            // started empty, load failed
        store.flush()                        // must NOT attempt to overwrite
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: file.url.path, isDirectory: &isDir))
        #expect(isDir.boolValue)             // still the original directory, untouched
        try? FileManager.default.removeItem(at: file.url)
    }
}
