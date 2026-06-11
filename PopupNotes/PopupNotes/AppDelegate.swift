import AppKit
import SwiftData
import PopupNotesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container: ModelContainer
    private(set) var currentHotKey = HotKeyStore.saved
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
        let ok = hotKey.register(currentHotKey) { [weak self] in self?.panel.toggle() }
        if !ok {
            NSLog("PopupNotes: hotkey registration failed; use the menu-bar item.")
        }
        // After the hotkey so the app is usable while the prompt is up.
        LaunchAtLogin.promptForConsentIfNeeded(hotKeyDisplay: currentHotKey.displayString)
    }

    /// Re-registers the global hotkey; restores the old combo and returns
    /// false if the new one is rejected (invalid or already taken).
    func applyHotKey(_ combo: HotKeyCombo) -> Bool {
        guard combo != currentHotKey else { return true }
        hotKey.unregister()
        if hotKey.register(combo, onFire: { [weak self] in self?.panel.toggle() }) {
            currentHotKey = combo
            HotKeyStore.saved = combo
            return true
        }
        hotKey.register(currentHotKey) { [weak self] in self?.panel.toggle() }
        return false
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
