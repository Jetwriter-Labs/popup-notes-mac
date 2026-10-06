import SwiftUI
import AppKit

extension Notification.Name {
    /// Posted (synchronously, on the main thread) right before Settings opens.
    static let popupNotesWillOpenSettings = Notification.Name("PopupNotesWillOpenSettings")
}

/// "Settings…" for every entry point: the panel's ⋯ menu, the onboarding
/// strip, the menu-bar menu and ⌘,. Unlike SettingsLink it runs code first.
/// The notes panel floats above normal windows, so it would cover Settings,
/// and it gets out of the way on the notification. This accessory app is
/// also usually inactive, so without activating, Settings opens behind the
/// frontmost app (or not on screen at all).
struct SettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            NotificationCenter.default.post(name: .popupNotesWillOpenSettings, object: nil)
            // Cooperative NSApp.activate() was observed being declined here,
            // leaving Settings off screen; the user did ask for this window.
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
            // Belt and braces if activation is still declined: put the window
            // in front anyway (a click on it then activates the app). SwiftUI's
            // Settings window identifier; a no-op if it ever changes.
            NSApp.windows.first { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }?
                .orderFrontRegardless()
        }
    }
}
