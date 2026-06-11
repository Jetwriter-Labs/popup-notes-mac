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
        let ok = hotKey.register(currentHotKey) { [weak self] in self?.handleHotKeyFire() }
        OnboardingDefaults.hotKeyRegistered = ok
        if !ok {
            NSLog("PopupNotes: hotkey registration failed; use the menu-bar item.")
        }
        runFirstLaunchOnboardingIfNeeded()
    }

    /// Re-registers the global hotkey; restores the old combo and returns
    /// false if the new one is rejected (invalid or already taken). A combo
    /// equal to the current one is a no-op only while the current
    /// registration is healthy — after a failure it re-attempts, so
    /// re-recording the same shortcut can recover once a conflict clears.
    func applyHotKey(_ combo: HotKeyCombo) -> Bool {
        guard combo != currentHotKey || !OnboardingDefaults.hotKeyRegistered else { return true }
        hotKey.unregister()
        if hotKey.register(combo, onFire: { [weak self] in self?.handleHotKeyFire() }) {
            currentHotKey = combo
            HotKeyStore.saved = combo
            OnboardingDefaults.hotKeyRegistered = true
            return true
        }
        let restored = hotKey.register(currentHotKey) { [weak self] in self?.handleHotKeyFire() }
        OnboardingDefaults.hotKeyRegistered = restored
        if !restored {
            NSLog("PopupNotes: failed to restore the previous hotkey; use the menu-bar item.")
        }
        return false
    }

    /// Records the first real hotkey use (retires the strip's hint row),
    /// then toggles the panel. The guarded write keeps the hot path lean.
    private func handleHotKeyFire() {
        if !OnboardingDefaults.didUseHotkeyOnce {
            OnboardingDefaults.didUseHotkeyOnce = true
        }
        panel.toggle()
    }

    /// First launch only (also fires once for users upgrading from builds
    /// without this flag): seed the Welcome note when the database is empty
    /// — after legacy migration, so importers keep their own content — and
    /// show the panel so the user experiences the popup immediately.
    private func runFirstLaunchOnboardingIfNeeded() {
        guard !OnboardingDefaults.didRunFirstLaunchOnboarding else { return }
        OnboardingDefaults.didRunFirstLaunchOnboarding = true
        // Undo the pre-consent-era silent default (builds before cc4294f
        // enabled launch-at-login unasked): if that era's flag is present and
        // no consent prompt was ever answered, disable it — the onboarding
        // strip's row asks properly from here on.
        if UserDefaults.standard.bool(forKey: "didApplyFirstRunDefaults"),
           !UserDefaults.standard.bool(forKey: OnboardingDefaults.didPromptLaunchAtLoginKey),
           LaunchAtLogin.isEnabled {
            LaunchAtLogin.isEnabled = false
        }
        let repo = NotesRepository(context: container.mainContext)
        if repo.allSortedByModified().isEmpty {
            repo.create(text: WelcomeNote.text(hotKeyDisplay: currentHotKey.displayString))
            repo.save()
        }
        panel.show()
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
