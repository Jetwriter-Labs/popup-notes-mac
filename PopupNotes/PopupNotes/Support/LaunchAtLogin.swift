import AppKit
import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` for the "Launch at Login" toggle.
/// Registering adds the app to System Settings ▸ General ▸ Login Items.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("PopupNotes: Launch at Login toggle failed: \(error.localizedDescription)")
            }
        }
    }

    /// Asks once, on first run, whether to launch at login — and tells the
    /// user the current hotkey while at it. App Review guideline 2.4.5(iii)
    /// forbids enabling login launch without consent, so the answer — not a
    /// silent default — decides. Subsequent user toggles win.
    static func promptForConsentIfNeeded(hotKeyDisplay: String) {
        let key = "didPromptLaunchAtLogin"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let alert = NSAlert()
        alert.messageText = "Launch Popup Notes at login?"
        alert.informativeText = """
            Press \(hotKeyDisplay) in any app to open your notes.

            Popup Notes lives in the menu bar; launching it at login keeps \
            that shortcut ready from the moment you sign in. You can change \
            both anytime in Settings (⌘,).
            """
        alert.addButton(withTitle: "Launch at Login")
        alert.addButton(withTitle: "Not Now")
        alert.buttons[1].keyEquivalent = "\u{1b}" // Esc declines

        NSApp.activate() // accessory app: bring the alert frontmost
        if alert.runModal() == .alertFirstButtonReturn {
            isEnabled = true
        } else if isEnabled {
            isEnabled = false // clear a pre-consent default left by older builds
        }
    }
}
