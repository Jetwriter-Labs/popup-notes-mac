import Foundation

/// The menu-bar icon's setting, shared by the `MenuBarExtra` (as its
/// `isInserted` binding) and Settings ▸ General's "Show in Menu Bar".
///
/// The binding is what lets the app outlive its icon. macOS takes the icon
/// away when the user switches Popup Notes off under System Settings ▸ Menu
/// Bar (macOS 26) or ⌘-drags it off the menu bar, and a `MenuBarExtra`
/// without `isInserted` answers that by quitting the app — taking the global
/// shortcut with it, and while the switch stays off, often within a second
/// of launch. With the binding, the removal only turns this setting off.
enum MenuBarIcon {
    static let isShownKey = "showsMenuBarIcon"

    /// System Settings ▸ Menu Bar. Its "Allow in the Menu Bar" list (macOS 26
    /// and later) can keep the icon hidden even while this setting is on.
    static let systemSettingsURL = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!
}
