import SwiftUI

@main
struct PopupNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Popup Notes", systemImage: "note.text") {
            MenuBarMenu(appDelegate: appDelegate)
        }

        Settings {
            SettingsView(container: appDelegate.container, appDelegate: appDelegate)
        }
        .commands {
            // ⌘, too must go through SettingsButton (see there for why).
            CommandGroup(replacing: .appSettings) {
                SettingsButton().keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

/// The menu-bar menu — a View of its own so it observes the live hotkey
/// state: "Show Notes" shows the shortcut that works right now (updated the
/// moment Settings records a new one), and none if registration failed.
private struct MenuBarMenu: View {
    let appDelegate: AppDelegate
    private var hotKey: HotKeyStatus { .shared }

    var body: some View {
        Button("Show Notes") { appDelegate.showNotes() }
            .keyboardShortcut(hotKey.isRegistered ? hotKey.combo.swiftUIShortcut : nil)
        Divider()
        SettingsButton()
        Divider()
        Button("Quit Popup Notes") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
