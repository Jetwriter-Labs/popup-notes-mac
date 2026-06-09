import SwiftUI

@main
struct PopupNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Popup Notes", systemImage: "note.text") {
            Button("Show Scratchpad") { appDelegate.showScratchpad() }
                .keyboardShortcut("n", modifiers: [.control, .command])
            Button("Open Notes File") { appDelegate.openNotesFile() }
            Divider()
            Toggle("Launch at Login", isOn: Binding(
                get: { LaunchAtLogin.isEnabled },
                set: { LaunchAtLogin.isEnabled = $0 }
            ))
            Divider()
            Button("Quit Popup Notes") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
