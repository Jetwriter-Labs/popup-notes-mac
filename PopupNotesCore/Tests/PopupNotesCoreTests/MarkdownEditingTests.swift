import Testing
import Foundation
@testable import PopupNotesCore

/// Texts are written with `|` for the caret or `{…}` around a selection, and
/// results come back the same way — nil when the key should do its usual thing.
@Suite struct MarkdownEditingTests {
    private func run(_ marked: String, _ edit: (MarkdownText, NSRange) -> MarkdownEdit?) -> String? {
        let (string, selection) = unmark(marked)
        guard let change = edit(MarkdownText(string), selection) else { return nil }
        let result = (string as NSString).replacingCharacters(in: change.range, with: change.replacement)
        return mark(result, change.selection ?? selection)
    }

    private func unmark(_ marked: String) -> (String, NSRange) {
        let units = Array(marked.utf16)
        if let open = units.firstIndex(of: 0x7B), let close = units.firstIndex(of: 0x7D) { // { }
            let string = marked.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
            return (string, NSRange(location: open, length: close - open - 1))
        }
        let caret = units.firstIndex(of: 0x7C)! // |
        return (marked.replacingOccurrences(of: "|", with: ""), NSRange(location: caret, length: 0))
    }

    private func mark(_ string: String, _ selection: NSRange) -> String {
        let result = NSMutableString(string: string)
        if selection.length == 0 {
            result.insert("|", at: selection.location)
        } else {
            result.insert("}", at: NSMaxRange(selection))
            result.insert("{", at: selection.location)
        }
        return result as String
    }

    private func newline(_ marked: String) -> String? {
        run(marked) { MarkdownEditing.newline(in: $0, selection: $1) }
    }

    private func tab(_ marked: String) -> String? {
        run(marked) { MarkdownEditing.indentation(in: $0, selection: $1, outdent: false) }
    }

    private func shiftTab(_ marked: String) -> String? {
        run(marked) { MarkdownEditing.indentation(in: $0, selection: $1, outdent: true) }
    }

    private func bold(_ marked: String) -> String? {
        run(marked) { MarkdownEditing.toggle("**", in: $0, selection: $1) }
    }

    private func italic(_ marked: String) -> String? {
        run(marked) { MarkdownEditing.toggle("*", in: $0, selection: $1) }
    }

    private func shortcut(_ marked: String) -> String? {
        run(marked) { MarkdownEditing.toggleShortcut(in: $0, selection: $1) }
    }

    private func backspace(_ marked: String) -> String? {
        run(marked) { MarkdownEditing.deleteBackward(in: $0, selection: $1) }
    }

    private func forwardDelete(_ marked: String) -> String? {
        run(marked) { MarkdownEditing.deleteForward(in: $0, selection: $1) }
    }

    private func toggleTask(_ string: String, at location: Int) -> String? {
        guard let change = MarkdownEditing.toggleTask(in: MarkdownText(string), at: location) else { return nil }
        return (string as NSString).replacingCharacters(in: change.range, with: change.replacement)
    }

    // MARK: Return

    @Test(arguments: [
        ("- item|", "- item\n- |"),
        ("* item|", "* item\n* |"),
        ("+ item|", "+ item\n+ |"),
        ("1. one|", "1. one\n2. |"),
        ("9) nine|", "9) nine\n10) |"),
        ("- [x] done|", "- [x] done\n- [ ] |"),
        ("\t- nested|", "\t- nested\n\t- |"),
        ("> quote|", "> quote\n> |"),
        ("- ab|cd", "- ab\n- |cd"),
        ("- a\n- b|\nafter", "- a\n- b\n- |\nafter"),
    ])
    func returnContinuesTheList(_ before: String, after: String) {
        #expect(newline(before) == after)
    }

    @Test(arguments: [
        ("- |", "|"),
        ("1. |", "|"),
        ("- [ ] |", "|"),
        ("> |", "|"),
        ("a\n- |\nb", "a\n|\nb"),
        ("\t- |", "- |"),
        ("  - |", "- |"),
        ("      - |", "  - |"),
    ])
    func returnOnAnEmptyItemEndsTheList(_ before: String, after: String) {
        #expect(newline(before) == after)
    }

    @Test(arguments: ["plain|", "-| item", "|- item", "```\n- code|", "# heading|", "{- item}"])
    func returnElsewhereIsAPlainLineBreak(_ before: String) {
        #expect(newline(before) == nil)
    }

    // MARK: Tab

    @Test(arguments: [
        ("- item|", "\t- item|"),
        ("- it|em", "\t- it|em"),
        ("|- item", "\t|- item"),
        ("1. one|", "\t1. one|"),
        ("{- a\n- b}", "{\t- a\n\t- b}"),
        ("{- a\nplain}", "{\t- a\n\tplain}"),
        ("{- a\n}- b", "{\t- a\n}- b"),
    ])
    func tabNestsListItems(_ before: String, after: String) {
        #expect(tab(before) == after)
    }

    @Test(arguments: [
        ("\t- item|", "- item|"),
        ("\t\t- item|", "\t- item|"),
        ("    - item|", "- item|"),
        ("  - item|", "- item|"),
        ("\t|- item", "|- item"),
        ("{\t- a\n\t- b}", "{- a\n- b}"),
        ("- top|", "- top|"),
    ])
    func shiftTabUnnestsListItems(_ before: String, after: String) {
        #expect(shiftTab(before) == after)
    }

    @Test func tabOutsideListsIsATab() {
        #expect(tab("plain|") == nil)
        #expect(shiftTab("plain|") == nil)
        #expect(tab("{pla}in") == nil)
    }

    @Test func tabMovesEverySelectedLine() {
        #expect(tab("{one\ntwo}") == "{\tone\n\ttwo}")
        #expect(tab("{a\n\nb}") == "{\ta\n\n\tb}") // blank lines stay empty
        #expect(shiftTab("{\tone\n\ttwo}") == "{one\ntwo}")
    }

    // MARK: ⌘B / ⌘I

    @Test(arguments: [
        ("{word}", "**{word}**"),
        ("**{word}**", "{word}"),
        ("{**word**}", "{word}"),
        ("*{word}*", "***{word}***"),
        ("***{word}***", "*{word}*"),
        ("say {hi} now", "say **{hi}** now"),
        ("{ word }", " **{word}** "),
        ("a|b", "a**|**b"),
        ("a**|**b", "a|b"),
    ])
    func boldToggles(_ before: String, after: String) {
        #expect(bold(before) == after)
    }

    @Test(arguments: [
        ("{word}", "*{word}*"),
        ("*{word}*", "{word}"),
        ("{*word*}", "{word}"),
        ("**{word}**", "***{word}***"),
        ("***{word}***", "**{word}**"),
        ("a|b", "a*|*b"),
        ("a*|*b", "a|b"),
    ])
    func italicToggles(_ before: String, after: String) {
        #expect(italic(before) == after)
    }

    // MARK: Tasks

    @Test func taskBoxesToggle() {
        #expect(toggleTask("- [ ] milk", at: 0) == "- [x] milk")
        #expect(toggleTask("- [x] milk", at: 3) == "- [ ] milk")
        #expect(toggleTask("- [X] milk", at: 9) == "- [ ] milk")
        #expect(toggleTask("a\n1. [ ] b", at: 4) == "a\n1. [x] b")
    }

    @Test func onlyTasksToggle() {
        #expect(toggleTask("- milk", at: 0) == nil)
        #expect(toggleTask("[ ] not a list", at: 0) == nil)
    }

    // MARK: Toggles

    @Test(arguments: [
        ("> |", "▾ |"),
        ("\t> |", "\t▾ |"),
        ("> |hello", "▾ |hello"),
        ("a\n> |", "a\n▾ |"),
    ])
    func greaterThanAndSpaceMakeAToggle(_ before: String, after: String) {
        #expect(shortcut(before) == after)
    }

    @Test(arguments: ["a > |", "> > |", ">|", "```\n> |", "{> }"])
    func greaterThanElsewhereStaysText(_ before: String) {
        #expect(shortcut(before) == nil)
    }

    @Test(arguments: [
        ("▾ Title|", "▾ Title\n\t|"),
        ("\t▾ T|", "\t▾ T\n\t\t|"),
        ("▾ Ti|tle", "▾ Ti\n\t|tle"),
        ("▸ T|\n\tbody\nafter", "▸ T\n\tbody\n▾ |\nafter"),
        ("▸ Ti|tle\n\tbody", "▸ Ti\n\tbody\n▾ |tle"),
        ("▸ T|", "▸ T\n▾ |"),
    ])
    func returnOnAToggle(_ before: String, after: String) {
        #expect(newline(before) == after)
    }

    @Test(arguments: [
        ("▾ T\n\tsome text|", "▾ T\n\tsome text\n\t|"),
        ("▾ T\n\t# Heading|", "▾ T\n\t# Heading\n\t|"),
        ("▾ T\n\t- a|", "▾ T\n\t- a\n\t- |"),
        ("▾ T\n\t\t|", "▾ T\n\t|"),
        ("▾ T\n\t|", "▾ T\n|"),
    ])
    func returnInsideAToggleStaysInside(_ before: String, after: String) {
        #expect(newline(before) == after)
    }

    @Test(arguments: [
        ("▾ |", "|"),
        ("\t▾ |", "▾ |"),
        ("▾ A\n\t▾ |", "▾ A\n\t|"),
        ("▾ T\n\t- |", "▾ T\n\t|"),
        ("▾ T\n\t\t- |", "▾ T\n\t- |"),
    ])
    func returnOnAnEmptyToggleOrItemEndsIt(_ before: String, after: String) {
        #expect(newline(before) == after)
    }

    @Test(arguments: ["\tindented|", "▾ T\n|\tchild"])
    func returnOutsideTogglesIsUnchanged(_ before: String) {
        #expect(newline(before) == nil)
    }

    @Test(arguments: [
        ("▾ T|\n\ta\nafter", "\t▾ T|\n\t\ta\nafter"),
        ("▾ T\n\ta|", "▾ T\n\t\ta|"),
        ("▾ T\n\t|", "▾ T\n\t\t|"),
    ])
    func tabMovesATogglesLinesWithIt(_ before: String, after: String) {
        #expect(tab(before) == after)
    }

    @Test(arguments: [
        ("\t▾ T|\n\t\ta", "▾ T|\n\ta"),
        ("▾ T\n\ta|", "▾ T\na|"),
        ("▾ T|\n\ta", "▾ T|\n\ta"),
    ])
    func shiftTabMovesAToggleOut(_ before: String, after: String) {
        #expect(shiftTab(before) == after)
    }

    @Test(arguments: [
        ("▾ |Title", "|Title"),
        ("\t▸ |T\n\t\tbody", "\t|T\n\t\tbody"),
        ("▸ T\n\tbody\n|after", "▸ T|after\n\tbody"),
        ("▸ T\n\tbody\n|\nafter", "▸ T|\n\tbody\nafter"),
    ])
    func backspaceAroundToggles(_ before: String, after: String) {
        #expect(backspace(before) == after)
    }

    @Test(arguments: ["▾ T\n\tbody\n|after", "▾ T|", "{▾ }T", "a|b"])
    func backspaceElsewhereIsUnchanged(_ before: String) {
        #expect(backspace(before) == nil)
    }

    @Test func forwardDeleteAtAClosedTitleSkipsTheFold() {
        #expect(forwardDelete("▸ T|\n\tbody\nafter") == "▸ T|after\n\tbody")
        #expect(forwardDelete("▸ T|\n\tbody") == "▸ T|\n\tbody")
        #expect(forwardDelete("▾ T|\n\tbody") == nil)
    }
}
