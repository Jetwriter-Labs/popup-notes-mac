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
