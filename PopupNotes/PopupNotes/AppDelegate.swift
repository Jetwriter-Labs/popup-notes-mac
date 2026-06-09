import AppKit
import SwiftData
import PopupNotesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container: ModelContainer
    private let hotKey = HotKeyManager()
    private let panel: PanelController

    override init() {
        let base = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base?.appendingPathComponent("PopupNotes", isDirectory: true)
        if let dir { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        let config = dir.map { ModelConfiguration(url: $0.appendingPathComponent("Notes.store")) }
            ?? ModelConfiguration()
        do {
            self.container = try ModelContainer(for: Note.self, configurations: config)
        } catch {
            fatalError("PopupNotes: failed to create the SwiftData container: \(error)")
        }
        self.panel = PanelController(container: container)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon
        migrateLegacyIfNeeded()
        LaunchAtLogin.applyFirstRunDefaultIfNeeded()
        let ok = hotKey.register(.default) { [weak self] in self?.panel.toggle() }
        if !ok {
            NSLog("PopupNotes: hotkey registration failed; use the menu-bar item.")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        try? container.mainContext.save()
        hotKey.unregister()
    }

    /// Called by the menu-bar "Show Notes" item.
    func showNotes() { panel.show() }

    /// One-time import of the pre-SwiftData scratchpad into a note.
    private func migrateLegacyIfNeeded() {
        let key = "didMigrateLegacyScratchpad"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard let url = LegacyScratchpad.defaultURL(), let text = LegacyScratchpad.read(at: url) else { return }
        let repo = NotesRepository(context: container.mainContext)
        repo.create(text: text)
        repo.save()
    }
}
