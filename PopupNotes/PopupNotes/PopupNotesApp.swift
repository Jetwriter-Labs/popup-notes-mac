import SwiftUI

@main
struct PopupNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Popup Notes", systemImage: "note.text") {
            Button("Show Notes") { appDelegate.showNotes() }
                .keyboardShortcut("n", modifiers: [.control, .command])
            Divider()
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit Popup Notes") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }

        Settings {
            SettingsView(container: appDelegate.container)
        }
    }
}
