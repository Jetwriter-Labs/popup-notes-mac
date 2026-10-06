import Foundation
import ServiceManagement
import os

/// Thin wrapper over `SMAppService.mainApp` for launch at login. Registering
/// adds the app to System Settings ▸ General ▸ Login Items. Consent (App
/// Review 2.4.5(iii)) is collected by the onboarding strip's Enable button or
/// the Settings toggle — never enabled silently.
enum LaunchAtLogin {
    /// The real login-item state, including `.requiresApproval` (the user
    /// switched it off in Login Items) and `.notFound`.
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool {
        get { status == .enabled }
        set { setEnabled(newValue) }
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("Launch at Login \(enabled ? "enable" : "disable", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
