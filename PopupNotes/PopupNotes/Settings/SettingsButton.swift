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
/// frontmost app.
struct SettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            NotificationCenter.default.post(name: .popupNotesWillOpenSettings, object: nil)
            NSApp.activate()
            openSettings()
        }
    }
}
