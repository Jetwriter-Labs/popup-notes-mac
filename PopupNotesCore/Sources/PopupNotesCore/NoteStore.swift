import Foundation
import Observation

/// The single source of truth for the scratchpad text. Loads at init, persists
/// via a debounced autosave plus an immediate `flush()` on hide/quit. In-memory
/// `text` is authoritative; failed saves are retried on the next change/flush.
@MainActor
@Observable
public final class NoteStore {
    public private(set) var text: String = ""

    @ObservationIgnored private let file: NoteFile
    @ObservationIgnored private let autosave: any Debouncing
    /// False only when an existing file failed to read — we then refuse to
    /// overwrite it until the user actually edits (takes ownership).
    @ObservationIgnored private var safeToWrite = true

    public init(file: NoteFile, autosave: any Debouncing) {
        self.file = file
        self.autosave = autosave
        load()
    }

    private func load() {
        guard file.exists else { text = ""; safeToWrite = true; return }
        do {
            text = try file.read()
            safeToWrite = true
        } catch {
            text = ""
            safeToWrite = false   // do not clobber an unreadable file
        }
    }

    /// Called from the SwiftUI editor binding on every keystroke.
    public func updateText(_ newValue: String) {
        text = newValue
        safeToWrite = true        // user edit = they own the content now
        autosave.schedule { [weak self] in self?.flush() }
    }

    /// Persist immediately (on hide and on quit). Keeps in-memory text on failure.
    public func flush() {
        guard safeToWrite else { return }
        do { try file.write(text) }
        catch { /* retried on next change/flush; in-memory text is the source of truth */ }
    }
}
