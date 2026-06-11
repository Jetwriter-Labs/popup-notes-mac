import Foundation
import SwiftUI
import PopupNotesCore

/// Persists the user's custom global shortcut in `UserDefaults` as JSON.
/// Absent or unreadable data falls back to `HotKeyCombo.default` (⌃⌘N).
enum HotKeyStore {
    private static let key = "hotKeyCombo"

    static var saved: HotKeyCombo {
        get {
            UserDefaults.standard.data(forKey: key)
                .flatMap { try? JSONDecoder().decode(HotKeyCombo.self, from: $0) }
                ?? .default
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }
}

extension HotKeyCombo {
    /// SwiftUI equivalent for menu items, when the key maps to a character.
    var swiftUIShortcut: KeyboardShortcut? {
        guard let char = keyEquivalentCharacter else { return nil }
        var eventModifiers: EventModifiers = []
        if modifiers.contains(.command) { eventModifiers.insert(.command) }
        if modifiers.contains(.control) { eventModifiers.insert(.control) }
        if modifiers.contains(.option)  { eventModifiers.insert(.option) }
        if modifiers.contains(.shift)   { eventModifiers.insert(.shift) }
        return KeyboardShortcut(KeyEquivalent(char), modifiers: eventModifiers)
    }
}
