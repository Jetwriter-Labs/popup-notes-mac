import AppKit
import PopupNotesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: NoteStore
    private let hotKey = HotKeyManager()
    private let panel: PanelController

    override init() {
        let file = (try? NoteFile.defaultFile()) ?? NoteFile(
            url: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("PopupNotes-scratchpad.md"))
        self.store = NoteStore(file: file, autosave: Debouncer(interval: .milliseconds(600)))
        self.panel = PanelController(store: store)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon
        let ok = hotKey.register(.default) { [weak self] in self?.panel.toggle() }
        if !ok {
            NSLog("PopupNotes: hotkey registration failed; use the menu-bar item.")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flush()
        hotKey.unregister()
    }

    /// Called by the menu-bar "Show Scratchpad" item.
    func showScratchpad() { panel.show() }
}
