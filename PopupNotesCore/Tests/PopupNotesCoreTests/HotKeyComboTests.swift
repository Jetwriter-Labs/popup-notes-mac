import Foundation
import Testing
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
