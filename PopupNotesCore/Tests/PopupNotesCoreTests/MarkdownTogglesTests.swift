import Testing
import Foundation
@testable import PopupNotesCore

@Suite struct MarkdownTogglesTests {
    private func lines(_ string: String) -> [MarkdownLine] {
        MarkdownBlocks.lines(in: MarkdownText(string))
    }

    private func text(_ range: NSRange?, in string: String) -> String? {
        range.map { MarkdownText(string).string(in: $0) }
    }

    /// The text after applying `edits`, which all keep the length.
    private func applying(_ edits: [MarkdownEdit], to string: String) -> String {
        let result = NSMutableString(string: string)
        for edit in edits { result.replaceCharacters(in: edit.range, with: edit.replacement) }
        return result as String
    }

    // MARK: Parsing

    @Test func toggleLines() {
        let string = "▾ Open **title**"
        let line = lines(string)[0]
        #expect(line.block == .toggle(isOpen: true))
        #expect(text(line.marker, in: string) == "▾")
        #expect(text(line.prefix, in: string) == "▾ ")
        #expect(text(line.content, in: string) == "Open **title**")
        #expect(lines("▸ Closed")[0].block == .toggle(isOpen: false))
        #expect(lines("\t▸ nested")[0].block == .toggle(isOpen: false))
    }

    @Test func markerAloneIsAnEmptyToggle() {
        #expect(lines("▾")[0].block == .toggle(isOpen: true))
        #expect(lines("▸ ")[0].content.length == 0)
    }

    @Test(arguments: ["▾title", "a ▾ b", "> ▾ quote", "- ▸ item"])
    func notToggles(_ string: String) {
        #expect(!lines(string)[0].isToggle)
    }

    @Test func markersInsideCodeAreCode() {
        #expect(lines("```\n▸ x\n```").map(\.block) == [.fence, .code, .fence])
    }

    @Test func indentedLinesBelongToTheToggleAbove() {
        let all = lines("▾ T\n\ta\n\t\tdeeper\nafter")
        #expect(all.map(\.toggleDepth) == [0, 1, 1, 0])
        #expect(all.allSatisfy { !$0.isHidden })
    }

    @Test func aClosedToggleHidesItsLines() {
        let all = lines("▸ T\n\ta\n  b\nafter")
        #expect(all.map(\.isHidden) == [false, true, true, false])
    }

    @Test func blankLinesBetweenItsLinesAreTheToggles() {
        let all = lines("▸ T\n\ta\n\n\tb\n\nafter")
        #expect(all.map(\.isHidden) == [false, true, true, true, false, false])
        #expect(all.map(\.toggleDepth) == [0, 1, 1, 1, 0, 0])
    }

    @Test func blankLinesAtTheEndAreNot() {
        #expect(lines("▸ T\n\ta\n\n").map(\.isHidden) == [false, true, false, false])
    }

    @Test func theEmptyLastLineFoldsAwayWithTheLineAboveIt() {
        // TextKit shows it as part of that line.
        let string = "▸ T\n\tbody\n"
        let all = lines(string)
        #expect(all.map(\.isHidden) == [false, true, true])
        #expect(applying(MarkdownToggles.reveal(2, in: all), to: string) == "▾ T\n\tbody\n")
        #expect(MarkdownToggles.visibleLocation(10, forward: true, in: all) == 3)
    }

    @Test func anIndentedBlankLineIsInside() {
        // Return on a toggle's title leaves "\t" on the new line: inside.
        let all = lines("▾ T\n\t\nafter")
        #expect(all.map(\.toggleDepth) == [0, 1, 0])
        #expect(lines("▸ T\n\t").map(\.isHidden) == [false, true])
    }

    @Test func togglesNest() {
        let all = lines("▾ A\n\t▸ B\n\t\tb\n\ta\nafter")
        #expect(all.map(\.toggleDepth) == [0, 1, 2, 1, 0])
        #expect(all.map(\.isHidden) == [false, false, true, false, false])
        #expect(lines("▸ A\n\t▾ B\n\t\tb").map(\.isHidden) == [false, true, true])
    }

    @Test func aLineNoFurtherIndentedEndsTheToggle() {
        #expect(lines("\t▸ T\n\t\tb\n\ta\n\t\tc").map(\.isHidden) == [false, true, false, false])
    }

    @Test func blocksIndentedUnderAToggleStillCount() {
        let all = lines("▾ T\n\t# Heading\n\t> quote\n\t---\n\t\t# deeper is text")
        #expect(all.map(\.block) == [.toggle(isOpen: true), .heading(level: 1), .quote, .rule, .paragraph])
        #expect(lines("\t# Heading")[0].block == .paragraph) // outside a toggle, as before
    }

    @Test func codeInsideAToggleFoldsAway() {
        #expect(lines("▸ T\n\t```\n\tcode\n\t```\nafter").map(\.isHidden) == [false, true, true, true, false])
    }

    // MARK: Structure

    @Test func bodyAndParent() {
        let all = lines("▾ A\n\t▾ B\n\t\tb\n\n\t\tb2\n\ta\nafter")
        #expect(MarkdownToggles.body(of: 0, in: all) == 1..<6)
        #expect(MarkdownToggles.body(of: 1, in: all) == 2..<5)
        #expect(MarkdownToggles.body(of: 6, in: all).isEmpty)
        #expect(MarkdownToggles.parent(of: 2, in: all) == 1)
        #expect(MarkdownToggles.parent(of: 5, in: all) == 0)
        #expect(MarkdownToggles.parent(of: 0, in: all) == nil)
    }

    @Test func theToggleAroundTheCaret() {
        let string = "▾ A\n\tinside\nafter"
        let all = lines(string)
        #expect(MarkdownToggles.toggle(around: 1, in: all) == 0)
        #expect(MarkdownToggles.toggle(around: 6, in: all) == 0)
        #expect(MarkdownToggles.toggle(around: 14, in: all) == nil)
    }

    // MARK: Folding

    @Test func foldSwapsTheMarker() {
        let string = "\t▾ A"
        let all = lines(string)
        #expect(MarkdownToggles.fold(0, open: false, in: all).map { applying([$0], to: string) } == "\t▸ A")
        #expect(MarkdownToggles.fold(0, open: true, in: all) == nil)
    }

    @Test func revealOpensEveryClosedToggleAbove() {
        let string = "▸ A\n\t▾ B\n\t\t▸ C\n\t\t\tc"
        let all = lines(string)
        #expect(applying(MarkdownToggles.reveal(3, in: all), to: string) == "▾ A\n\t▾ B\n\t\t▾ C\n\t\t\tc")
        #expect(MarkdownToggles.reveal(0, in: all).isEmpty)
    }

    @Test func foldAllOpensWhenAnyIsClosedElseCloses() {
        let mixed = "▾ A\n\ta\n▸ B\n\tb"
        #expect(applying(MarkdownToggles.foldAll(in: lines(mixed)), to: mixed) == "▾ A\n\ta\n▾ B\n\tb")
        let open = "▾ A\n\ta\n▾ B\n\tb"
        #expect(applying(MarkdownToggles.foldAll(in: lines(open)), to: open) == "▸ A\n\ta\n▸ B\n\tb")
    }

    // MARK: Caret

    @Test func caretsStepOverFoldedLines() {
        // "▸ T" 0..3, "\ta" 4..6, "\tb" 7..9, "after" 10..15
        let all = lines("▸ T\n\ta\n\tb\nafter")
        #expect(MarkdownToggles.visibleLocation(5, forward: true, in: all) == 10)
        #expect(MarkdownToggles.visibleLocation(8, forward: false, in: all) == 3)
        #expect(MarkdownToggles.visibleLocation(10, forward: false, in: all) == 10)
        #expect(MarkdownToggles.visibleLocation(2, forward: true, in: all) == 2)
    }

    @Test func withNothingBelowACaretStaysOnTheTitle() {
        let all = lines("x\n▸ T\n\ta")
        #expect(MarkdownToggles.visibleLocation(8, forward: true, in: all) == 5)
    }

    // MARK: Titles

    @Test func noteTitlesReadWithoutTheMarker() {
        #expect(NoteTitle.title(from: "▸ Secret plans\n\tdetails") == "Secret plans")
        #expect(NoteTitle.preview(from: "Title\n▾ **Toggle**") == "Toggle")
    }

    @Test func headingsInsideTogglesAreInTheOutline() {
        let headings = MarkdownOutline.headings(in: "# Top\n▸ More\n\t## Inside")
        #expect(headings.map(\.title) == ["Top", "Inside"])
    }
}
