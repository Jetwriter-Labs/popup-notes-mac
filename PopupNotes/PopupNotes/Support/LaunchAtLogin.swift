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

    /// Enables launch-at-login once, on first run only. Subsequent user toggles win.
    static func applyFirstRunDefaultIfNeeded() {
        let key = "didApplyFirstRunDefaults"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        isEnabled = true
    }
}
