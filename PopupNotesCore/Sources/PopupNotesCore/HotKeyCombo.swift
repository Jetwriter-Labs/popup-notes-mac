/// A keyboard-shortcut definition, independent of Carbon.
///
/// `KeyModifiers` raw values intentionally mirror Carbon's HIToolbox modifier
/// masks (`cmdKey`, `shiftKey`, `optionKey`, `controlKey` from
/// <Carbon/HIToolbox/Events.h>) so `carbonModifierFlags` is a no-op cast.
/// ⚠️ VERIFY these equal the real Carbon constants — Task 7 adds an app-side
/// assertion (`assert(KeyModifiers.command.rawValue == UInt32(cmdKey))`, etc.).
public struct KeyModifiers: OptionSet, Sendable, Equatable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let command = KeyModifiers(rawValue: 0x0100) // cmdKey
    public static let shift   = KeyModifiers(rawValue: 0x0200) // shiftKey
    public static let option  = KeyModifiers(rawValue: 0x0800) // optionKey
    public static let control = KeyModifiers(rawValue: 0x1000) // controlKey
}

public struct HotKeyCombo: Sendable, Equatable {
    /// Virtual key code (Carbon `kVK_*`); 45 == `kVK_ANSI_N`.
    public var keyCode: UInt32
    public var modifiers: KeyModifiers

    public init(keyCode: UInt32, modifiers: KeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// The default shortcut: ⌃⌘N.
    public static let `default` = HotKeyCombo(keyCode: 45, modifiers: [.control, .command])

    /// Carbon modifier bitmask for `RegisterEventHotKey`.
    public var carbonModifierFlags: UInt32 { modifiers.rawValue }

    /// A safe global hotkey must include Command and/or Control. This rejects
    /// the empty, Shift-only, Option-only, and Option+Shift combos — the last
    /// two are documented broken with `RegisterEventHotKey` on macOS 15+.
    public var isValidGlobalHotKey: Bool {
        !modifiers.isDisjoint(with: [.command, .control])
    }
}

// MARK: - Persistence

extension KeyModifiers: Codable {
    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(UInt32.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension HotKeyCombo: Codable {}

// MARK: - Display

extension HotKeyCombo {
    /// Human-readable form, e.g. `⌃⌘N`. Modifier symbols follow the order
    /// macOS renders everywhere: Control, Option, Shift, Command.
    public var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option)  { result += "⌥" }
        if modifiers.contains(.shift)   { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result + (Self.keyNames[keyCode] ?? "Key \(keyCode)")
    }

    /// The plain character for SwiftUI's `KeyEquivalent`, when one exists.
    /// Function keys, arrows, and other non-character keys return nil.
    public var keyEquivalentCharacter: Character? {
        if keyCode == 49 { return " " } // Space
        guard let name = Self.keyNames[keyCode], name.count == 1,
              let char = name.lowercased().first, char.isASCII else { return nil }
        return char
    }

    /// Carbon `kVK_*` virtual key codes → display names (US ANSI layout).
    private static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 50: "`",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}
