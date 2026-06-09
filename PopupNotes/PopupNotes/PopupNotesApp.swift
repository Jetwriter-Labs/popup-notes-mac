import SwiftUI

@main
struct PopupNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Popup Notes", systemImage: "note.text") {
            Button("Show Scratchpad") { appDelegate.showScratchpad() }
                .keyboardShortcut("n", modifiers: [.control, .command])
            Divider()
            Button("Quit Popup Notes") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
