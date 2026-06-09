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
}
