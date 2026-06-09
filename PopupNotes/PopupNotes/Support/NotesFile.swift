import AppKit
import PopupNotesCore

/// Reveals the scratchpad file in Finder, creating it first if it doesn't exist
/// yet. Shared by the menu-bar item and the in-popup options menu.
@MainActor
enum NotesFile {
    static func revealInFinder(_ store: NoteStore) {
        let url = store.fileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            store.flush() // create the file so Finder has something to select
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
