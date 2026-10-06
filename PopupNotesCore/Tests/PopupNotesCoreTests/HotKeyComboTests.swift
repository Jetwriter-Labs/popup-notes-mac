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

    @Test func optionOnlyIsInvalid() {
        #expect(!HotKeyCombo(keyCode: 45, modifiers: [.option]).isValidGlobalHotKey)
    }

    @Test func optionShiftIsInvalid() {
        #expect(!HotKeyCombo(keyCode: 45, modifiers: [.option, .shift]).isValidGlobalHotKey)
    }

    @Test func noModifiersIsInvalid() {
        #expect(!HotKeyCombo(keyCode: 45, modifiers: []).isValidGlobalHotKey)
    }

    @Test func commandShiftIsValid() {
        #expect(HotKeyCombo(keyCode: 45, modifiers: [.command, .shift]).isValidGlobalHotKey)
    }

    @Test func controlOptionIsValid() {
        #expect(HotKeyCombo(keyCode: 45, modifiers: [.control, .option]).isValidGlobalHotKey)
    }

    // MARK: Recorder guard

    @Test func commandAloneIsFlagged() {
        #expect(HotKeyCombo(keyCode: 9, modifiers: [.command]).usesCommandAlone)   // ⌘V
        #expect(HotKeyCombo(keyCode: 13, modifiers: [.command]).usesCommandAlone)  // ⌘W
    }

    @Test func combosWithMoreThanCommandAreNotFlagged() {
        #expect(!HotKeyCombo.default.usesCommandAlone)                                   // ⌃⌘N
        #expect(!HotKeyCombo(keyCode: 45, modifiers: [.command, .shift]).usesCommandAlone) // ⇧⌘N
        #expect(!HotKeyCombo(keyCode: 35, modifiers: [.control]).usesCommandAlone)        // ⌃P
        #expect(!HotKeyCombo(keyCode: 40, modifiers: [.command, .option]).usesCommandAlone) // ⌥⌘K
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
