import AppKit
import SwiftData
import PopupNotesCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container: ModelContainer
    /// Set when the notes database can't be opened. The app then explains and
    /// quits at launch; `container` is an in-memory stand-in that nothing may
    /// show or edit (anything typed into it would be lost).
    private let storeError: (any Error)?
    private let storeURL: URL
    private let hotKey = HotKeyManager()
    private let panel: PanelController
    private var hotKeyStatus: HotKeyStatus { .shared }

    override init() {
        let url = URL.applicationSupportDirectory.appending(path: "PopupNotes/Notes.store")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        storeURL = url
        do {
            container = try ModelContainer(for: Note.self, configurations: ModelConfiguration(url: url))
            storeError = nil
        } catch {
            // Not fatalError: that crash-loops at every login with no word to
            // the user. Leave the file untouched; applicationDidFinishLaunching
            // says what happened and quits.
            Log.store.fault("Can't open the notes store at \(url.path, privacy: .public): \(String(reflecting: error), privacy: .public)")
            storeError = error
            container = try! ModelContainer(for: Note.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        panel = PanelController(container: container)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // First: `currentAppleEvent` is only readable while AppKit dispatches
        // the launch event, and the setup below outlives that window.
        let launchKind = AppLaunchKind.current
        // Before anything that writes state (migration and onboarding flags,
        // the login item) or could show the panel over the stand-in store.
        guard storeError == nil else { presentStoreFailureAndQuit(); return }
        NSApp.setActivationPolicy(.accessory) // no Dock icon
        migrateLegacyIfNeeded()
        let combo = HotKeyStore.saved
        hotKeyStatus.combo = combo
        hotKeyStatus.isRegistered = hotKey.register(combo) { [weak self] in self?.handleHotKeyFire() }
        if !hotKeyStatus.isRegistered {
            Log.app.error("Hotkey \(combo.displayString, privacy: .public) couldn't be registered; use the menu-bar item.")
        }
        runFirstLaunchOnboardingIfNeeded()
        // Opening the app from Spotlight, Raycast or Finder is a request to
        // see the notes; with no Dock icon and no main window, staying silent
        // reads as a failure to launch. A login or Services launch must not
        // put anything on screen — instead it builds the panel in the
        // background, so the first hotkey press of the session is instant.
        if launchKind.shouldShowPanelOnLaunch {
            panel.activate()
        } else {
            Task { [panel] in
                try? await Task.sleep(for: .seconds(1))
                panel.prewarm()
            }
        }
    }

    /// Re-registers the global hotkey; restores the old combo and returns
    /// false if the new one is rejected (invalid or already taken). A combo
    /// equal to the current one is a no-op only while the current
    /// registration is healthy — after a failure it re-attempts, so
    /// re-recording the same shortcut can recover once a conflict clears.
    func applyHotKey(_ combo: HotKeyCombo) -> Bool {
        guard combo != hotKeyStatus.combo || !hotKeyStatus.isRegistered else { return true }
        hotKey.unregister()
        if hotKey.register(combo, onFire: { [weak self] in self?.handleHotKeyFire() }) {
            hotKeyStatus.combo = combo
            hotKeyStatus.isRegistered = true
            HotKeyStore.saved = combo
            return true
        }
        let restored = hotKey.register(hotKeyStatus.combo) { [weak self] in self?.handleHotKeyFire() }
        hotKeyStatus.isRegistered = restored
        if !restored {
            Log.app.error("Couldn't restore the previous hotkey; use the menu-bar item.")
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
    /// — after legacy migration, so importers keep their own content. The
    /// panel itself opens from applicationDidFinishLaunching, and only for a
    /// user launch: a first launch at login (an upgrade installed while the
    /// old version ran) stays silent like any other login.
    private func runFirstLaunchOnboardingIfNeeded() {
        guard !OnboardingDefaults.didRunFirstLaunchOnboarding else { return }
        OnboardingDefaults.didRunFirstLaunchOnboarding = true
        // Undo the pre-consent-era silent default (builds before cc4294f
        // enabled launch-at-login unasked): if that era's flag is present and
        // no consent prompt was ever answered, disable it — the onboarding
        // strip's row asks properly from here on.
        if UserDefaults.standard.bool(forKey: OnboardingDefaults.legacyFirstRunDefaultsKey),
           !UserDefaults.standard.bool(forKey: OnboardingDefaults.didPromptLaunchAtLoginKey),
           LaunchAtLogin.isEnabled {
            LaunchAtLogin.isEnabled = false
        }
        // Only a store known to be empty gets the Welcome note — not one whose
        // fetch failed.
        let repo = NotesRepository(context: container.mainContext)
        if let notes = try? repo.allNotes(), notes.isEmpty {
            repo.create(text: WelcomeNote.text(hotKeyDisplay: hotKeyStatus.combo.displayString))
            container.mainContext.saveLoggingErrors("seeding the Welcome note")
        }
    }

    /// Opening an app that is already running sends a reopen event rather
    /// than starting a second copy — this is what Spotlight, Raycast, Finder
    /// and `open -a` hit for all but the first launch. Left unhandled it did
    /// nothing at all, since there is no Dock icon or window for AppKit's
    /// default behavior to restore. Returns false: the panel *is* the
    /// response, so AppKit should not add one of its own.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if storeError == nil { panel.activate() }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        container.mainContext.saveLoggingErrors("quitting")
        hotKey.unregister()
    }

    /// Called by the menu-bar "Show Notes" item.
    func showNotes() {
        guard storeError == nil else { return }
        panel.activate()
    }

    /// One-time import of the pre-SwiftData scratchpad into a note.
    private func migrateLegacyIfNeeded() {
        let key = "didMigrateLegacyScratchpad"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard let url = LegacyScratchpad.defaultURL(), let text = LegacyScratchpad.read(at: url) else { return }
        NotesRepository(context: container.mainContext).create(text: text)
        container.mainContext.saveLoggingErrors("migrating the legacy scratchpad")
    }

    /// The database exists but won't open (corrupt, unreadable, disk
    /// trouble). Say so — instead of crashing at every launch — and quit
    /// without touching the file.
    private func presentStoreFailureAndQuit() {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Popup Notes can’t open your notes"
        alert.informativeText = """
            The notes database couldn’t be opened, so Popup Notes will quit. \
            The file hasn’t been changed. To keep a copy, back up Notes.store \
            together with its -wal and -shm files from:

            \(storeURL.deletingLastPathComponent().path)
            """
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }
}
