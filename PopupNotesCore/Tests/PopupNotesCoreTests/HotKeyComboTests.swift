import Foundation
import Testing
#if canImport(Carbon)
import Carbon.HIToolbox
#endif
@testable import PopupNotesCore

@Suite struct HotKeyComboTests {
    @Test func defaultIsControlCommandN() {
        let combo = HotKeyCombo.default
        #expect(combo.keyCode == 45)                 // kVK_ANSI_N
        #expect(combo.modifiers == [.control, .command])
        #expect(combo.isValidGlobalHotKey)
    }

    @Test func carbonModifierFlagsAreBitwiseOr() {
        let combo = HotKeyCombo(keyCode: 45, modifiers: [.control, .command])
        #expect(combo.carbonModifierFlags == 0x1000 | 0x0100) // controlKey | cmdKey
    }

    // MARK: Which combos can be hotkeys

    /// The user's call, even when another app or macOS uses the combo too.
    @Test func commandAloneIsValid() {
        #expect(HotKeyCombo(keyCode: 49, modifiers: [.command]).isValidGlobalHotKey) // ⌘Space
        #expect(HotKeyCombo(keyCode: 9, modifiers: [.command]).isValidGlobalHotKey)  // ⌘V
    }

    @Test func controlAloneIsValid() {
        #expect(HotKeyCombo(keyCode: 49, modifiers: [.control]).isValidGlobalHotKey) // ⌃Space
        #expect(HotKeyCombo(keyCode: 35, modifiers: [.control]).isValidGlobalHotKey) // ⌃P
    }

    /// Refused by macOS 15.0, registered again on 15.2 and later.
    @Test func optionCombosAreValid() {
        #expect(HotKeyCombo(keyCode: 45, modifiers: [.option]).isValidGlobalHotKey)         // ⌥N
        #expect(HotKeyCombo(keyCode: 45, modifiers: [.option, .shift]).isValidGlobalHotKey) // ⌥⇧N
        #expect(HotKeyCombo(keyCode: 49, modifiers: [.option]).isValidGlobalHotKey)         // ⌥Space
    }

    @Test func commandShiftIsValid() {
        #expect(HotKeyCombo(keyCode: 45, modifiers: [.command, .shift]).isValidGlobalHotKey)
    }

    @Test func controlOptionIsValid() {
        #expect(HotKeyCombo(keyCode: 45, modifiers: [.control, .option]).isValidGlobalHotKey)
    }

    @Test func functionKeysWorkAlone() {
        #expect(HotKeyCombo(keyCode: 96, modifiers: []).isValidGlobalHotKey)       // F5
        #expect(HotKeyCombo(keyCode: 105, modifiers: []).isValidGlobalHotKey)      // F13
        #expect(HotKeyCombo(keyCode: 90, modifiers: []).isValidGlobalHotKey)       // F20
        #expect(HotKeyCombo(keyCode: 96, modifiers: [.shift]).isValidGlobalHotKey) // ⇧F5
    }

    /// macOS refuses these for a sandboxed app: they're how text is typed.
    @Test func plainOrShiftTypingKeysAreInvalid() {
        #expect(!HotKeyCombo(keyCode: 45, modifiers: []).isValidGlobalHotKey)       // N
        #expect(!HotKeyCombo(keyCode: 45, modifiers: [.shift]).isValidGlobalHotKey) // ⇧N
        #expect(!HotKeyCombo(keyCode: 18, modifiers: [.shift]).isValidGlobalHotKey) // ⇧1
    }

    /// macOS would take these, leaving the key dead in every app.
    @Test func plainOrShiftEditingKeysAreInvalid() {
        #expect(!HotKeyCombo(keyCode: 49, modifiers: []).isValidGlobalHotKey)        // Space
        #expect(!HotKeyCombo(keyCode: 48, modifiers: []).isValidGlobalHotKey)        // Tab
        #expect(!HotKeyCombo(keyCode: 36, modifiers: []).isValidGlobalHotKey)        // Return
        #expect(!HotKeyCombo(keyCode: 51, modifiers: []).isValidGlobalHotKey)        // ⌫
        #expect(!HotKeyCombo(keyCode: 123, modifiers: []).isValidGlobalHotKey)       // ←
        #expect(!HotKeyCombo(keyCode: 49, modifiers: [.shift]).isValidGlobalHotKey)  // ⇧Space
        #expect(!HotKeyCombo(keyCode: 126, modifiers: [.shift]).isValidGlobalHotKey) // ⇧↑
    }

    #if canImport(Carbon)
    // MARK: Carbon parity

    /// `carbonModifierFlags` passes the raw values straight to RegisterEventHotKey.
    @Test func modifierMasksMatchCarbon() {
        #expect(KeyModifiers.command.rawValue == UInt32(cmdKey))
        #expect(KeyModifiers.shift.rawValue == UInt32(shiftKey))
        #expect(KeyModifiers.option.rawValue == UInt32(optionKey))
        #expect(KeyModifiers.control.rawValue == UInt32(controlKey))
    }

    @Test func keyCodesMatchCarbon() {
        #expect(HotKeyCombo.default.keyCode == UInt32(kVK_ANSI_N))
        #expect(HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: [.command]).displayString == "⌘Space")
        #expect(HotKeyCombo(keyCode: UInt32(kVK_F5), modifiers: [.command]).displayString == "⌘F5")
        #expect(HotKeyCombo(keyCode: UInt32(kVK_UpArrow), modifiers: [.command]).displayString == "⌘↑")
    }

    @Test func functionKeyCodesMatchCarbon() {
        let fKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                     kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        for (index, code) in fKeys.enumerated() {
            let combo = HotKeyCombo(keyCode: UInt32(code), modifiers: [])
            #expect(combo.isFunctionKey)
            #expect(combo.displayString == "F\(index + 1)")
        }
        #expect(!HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: []).isFunctionKey)
        #expect(!HotKeyCombo(keyCode: UInt32(kVK_ANSI_N), modifiers: []).isFunctionKey)
    }
    #endif

    // MARK: Display

    @Test func defaultDisplaysAsControlCommandN() {
        #expect(HotKeyCombo.default.displayString == "⌃⌘N")
    }

    @Test func modifierSymbolsFollowAppleOrder() {
        // Control, Option, Shift, Command — the order macOS renders everywhere.
        let combo = HotKeyCombo(keyCode: 0, modifiers: [.command, .shift, .option, .control])
        #expect(combo.displayString == "⌃⌥⇧⌘A")
    }

    @Test func specialKeysHaveSymbols() {
        #expect(HotKeyCombo(keyCode: 49, modifiers: [.command]).displayString == "⌘Space")
        #expect(HotKeyCombo(keyCode: 126, modifiers: [.command]).displayString == "⌘↑")
        #expect(HotKeyCombo(keyCode: 96, modifiers: [.command]).displayString == "⌘F5")
    }

    @Test func unknownKeyCodeFallsBackToNumber() {
        let combo = HotKeyCombo(keyCode: 200, modifiers: [.command])
        #expect(combo.displayString.contains("200"))
    }

    // MARK: Persistence

    /// Pins the on-disk format of the `hotKeyCombo` default: users' saved
    /// shortcuts must keep decoding after any refactor.
    @Test func decodesTheSavedDefaultsFormat() throws {
        let saved = try JSONDecoder().decode(HotKeyCombo.self, from: Data(#"{"keyCode":45,"modifiers":4352}"#.utf8))
        #expect(saved == .default)
        let controlP = try JSONDecoder().decode(HotKeyCombo.self, from: Data(#"{"modifiers":4096,"keyCode":35}"#.utf8))
        #expect(controlP == HotKeyCombo(keyCode: 35, modifiers: [.control]))
    }

    @Test func codableRoundTripPreservesCombo() throws {
        let original = HotKeyCombo(keyCode: 35, modifiers: [.command, .shift])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotKeyCombo.self, from: data)
        #expect(decoded == original)
    }

    // MARK: SwiftUI key equivalents

    @Test func characterKeysHaveKeyEquivalents() {
        #expect(HotKeyCombo.default.keyEquivalentCharacter == "n")
        #expect(HotKeyCombo(keyCode: 49, modifiers: [.command]).keyEquivalentCharacter == " ")
    }

    @Test func functionKeysHaveNoKeyEquivalent() {
        #expect(HotKeyCombo(keyCode: 96, modifiers: [.command]).keyEquivalentCharacter == nil)
    }
}
