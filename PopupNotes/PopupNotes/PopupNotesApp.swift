import SwiftUI

@main
struct PopupNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Popup Notes", systemImage: "note.text") {
            // Mirrors the user's custom global hotkey (nil for non-character keys).
            Button("Show Notes") { appDelegate.showNotes() }
                .keyboardShortcut(appDelegate.currentHotKey.swiftUIShortcut)
            Divider()
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit Popup Notes") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }

        Settings {
            SettingsView(container: appDelegate.container, appDelegate: appDelegate)
        }
    }
}
