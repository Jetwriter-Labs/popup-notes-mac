import Testing
import Foundation
@testable import PopupNotesCore

@Suite struct MarkdownBlocksTests {
    private func lines(_ string: String) -> [MarkdownLine] {
        MarkdownBlocks.lines(in: MarkdownText(string))
    }

    private func blocks(_ string: String) -> [MarkdownBlock] {
        lines(string).map(\.block)
    }

    private func block(_ string: String) -> MarkdownBlock {
        blocks(string)[0]
    }

    /// The text a range covers, for readable expectations.
    private func text(_ range: NSRange?, in string: String) -> String? {
        range.map { MarkdownText(string).string(in: $0) }
    }

    // MARK: Line splitting

    @Test func emptyTextIsOneEmptyLine() {
        let all = lines("")
        #expect(all.count == 1)
        #expect(all[0].range == NSRange(location: 0, length: 0))
        #expect(all[0].block == .blank)
    }

    @Test func trailingLineBreakLeavesAFinalEmptyLine() {
        let all = lines("a\n")
        #expect(all.map(\.range) == [NSRange(location: 0, length: 1), NSRange(location: 2, length: 0)])
        #expect(all.map(\.terminatorLength) == [1, 0])
    }

    @Test func crlfIsOneLineBreak() {
        let all = lines("a\r\nb")
        #expect(all.map(\.range) == [NSRange(location: 0, length: 1), NSRange(location: 3, length: 1)])
        #expect(all[0].terminatorLength == 2)
        #expect(all[0].fullRange == NSRange(location: 0, length: 3))
    }

    @Test(arguments: ["a\rb", "a\u{2028}b", "a\u{2029}b", "a\u{85}b"])
    func otherLineBreaksSplitLines(_ string: String) {
        #expect(lines(string).count == 2)
    }

    @Test func rangesCountUTF16() {
        // 😀 is two UTF-16 units.
        let all = lines("😀\n# A")
        #expect(all[1].range == NSRange(location: 3, length: 3))
    }

    @Test func lineIndexFindsTheLineHoldingACaret() {
        let all = lines("ab\ncd\n")
        #expect(MarkdownBlocks.lineIndex(containing: 0, in: all) == 0)
        #expect(MarkdownBlocks.lineIndex(containing: 2, in: all) == 0) // end of "ab"
        #expect(MarkdownBlocks.lineIndex(containing: 3, in: all) == 1)
        #expect(MarkdownBlocks.lineIndex(containing: 6, in: all) == 2) // the final empty line
    }

    // MARK: Headings

    @Test(arguments: [("# One", 1), ("## Two", 2), ("###### Six", 6), ("   ### Indented", 3), ("#\tTab", 1)])
    func atxHeadings(_ string: String, level: Int) {
        #expect(block(string) == .heading(level: level))
    }

    @Test(arguments: ["#hashtag", "####### Seven", "    # four spaces in", "#5 things"])
    func notHeadings(_ string: String) {
        #expect(block(string) == .paragraph)
    }

    @Test func headingParts() throws {
        let string = "## Plan for **today**"
        let line = lines(string)[0]
        #expect(text(line.marker, in: string) == "##")
        #expect(text(line.prefix, in: string) == "## ")
        #expect(text(line.content, in: string) == "Plan for **today**")
        #expect(line.closingSequence == nil)
    }

    @Test func headingClosingSequence() {
        let string = "## Title ##  "
        let line = lines(string)[0]
        #expect(text(line.content, in: string) == "Title")
        #expect(text(line.closingSequence, in: string) == " ##  ")
    }

    @Test func hashesGluedToTheTitleAreContent() {
        let string = "# C#"
        #expect(text(lines(string)[0].content, in: string) == "C#")
    }

    @Test func bareHashIsAnEmptyHeading() {
        let line = lines("#")[0]
        #expect(line.block == .heading(level: 1))
        #expect(line.content.length == 0)
    }

    // MARK: Lists

    @Test(arguments: [("- item", "-"), ("* item", "*"), ("+ item", "+")])
    func bulletItems(_ string: String, bullet: Character) {
        #expect(block(string) == .listItem(MarkdownListMarker(kind: .bullet(bullet))))
    }

    @Test func orderedItems() {
        #expect(block("1. one") == .listItem(MarkdownListMarker(kind: .ordered(number: 1, delimiter: "."))))
        #expect(block("42) answer") == .listItem(MarkdownListMarker(kind: .ordered(number: 42, delimiter: ")"))))
    }

    @Test(arguments: ["-item", "-", "1.", "1.x", "1234567890. ten digits", "--", "**bold**"])
    func notListItems(_ string: String) {
        #expect(block(string) == .paragraph)
    }

    @Test func markerWithNothingAfterItIsAnEmptyItem() {
        let line = lines("- ")[0]
        #expect(line.block == .listItem(MarkdownListMarker(kind: .bullet("-"))))
        #expect(line.content.length == 0)
    }

    @Test func nestedItemsKeepTheirIndentationInThePrefix() {
        let string = "\t  - nested"
        let line = lines(string)[0]
        #expect(text(line.marker, in: string) == "-")
        #expect(text(line.prefix, in: string) == "\t  - ")
        #expect(text(line.content, in: string) == "nested")
    }

    @Test func taskItems() {
        let open = "- [ ] buy milk"
        let line = lines(open)[0]
        #expect(line.block == .listItem(MarkdownListMarker(kind: .bullet("-"), task: .open)))
        #expect(text(line.taskBox, in: open) == "[ ]")
        #expect(text(line.content, in: open) == "buy milk")
        #expect(block("* [x] done") == .listItem(MarkdownListMarker(kind: .bullet("*"), task: .done)))
        #expect(block("1. [X] Done") == .listItem(MarkdownListMarker(kind: .ordered(number: 1, delimiter: "."), task: .done)))
        #expect(block("- [ ]") == .listItem(MarkdownListMarker(kind: .bullet("-"), task: .open)))
    }

    @Test func boxNotFollowedBySpaceIsContent() {
        let string = "- [x]done"
        let line = lines(string)[0]
        #expect(line.block == .listItem(MarkdownListMarker(kind: .bullet("-"))))
        #expect(text(line.content, in: string) == "[x]done")
    }

    // MARK: Quotes and rules

    @Test func quotes() {
        let string = "> quoted"
        let line = lines(string)[0]
        #expect(line.block == .quote)
        #expect(text(line.marker, in: string) == ">")
        #expect(text(line.content, in: string) == "quoted")
        #expect(text(lines(">tight")[0].content, in: ">tight") == "tight")
    }

    @Test(arguments: ["---", "***", "___", "- - -", " * * *", "-----", "_ _ _ "])
    func rules(_ string: String) {
        #expect(block(string) == .rule)
    }

    @Test(arguments: ["--", "-- x", "---a", "*-*"])
    func notRules(_ string: String) {
        #expect(block(string) != .rule)
    }

    // MARK: Fenced code

    @Test func fencedCodeBlock() {
        #expect(blocks("```\n# not a heading\n- not a list\n```\nafter")
                == [.fence, .code, .code, .fence, .paragraph])
    }

    @Test func fenceWithInfoString() {
        #expect(blocks("```swift\nlet x = 1\n```") == [.fence, .code, .fence])
    }

    @Test func tildeFenceIgnoresBackticks() {
        #expect(blocks("~~~\n```\n~~~\nafter") == [.fence, .code, .fence, .paragraph])
    }

    @Test func shorterFenceDoesNotClose() {
        #expect(blocks("````\n```\n````") == [.fence, .code, .fence])
    }

    @Test func closingFenceMayHaveTrailingSpaces() {
        #expect(blocks("```\nx\n```  \ny") == [.fence, .code, .fence, .paragraph])
    }

    @Test func closingFenceWithTextAfterIsCode() {
        #expect(blocks("```\n``` nope\n```") == [.fence, .code, .fence])
    }

    @Test func unclosedFenceRunsToTheEnd() {
        #expect(blocks("```\na\n\nb") == [.fence, .code, .code, .code])
    }

    @Test func indentedFenceInsideAListStillOpens() {
        #expect(blocks("- step\n    ```\n    code\n    ```") == [
            .listItem(MarkdownListMarker(kind: .bullet("-"))), .fence, .code, .fence,
        ])
    }

    @Test func backticksOnOneLineAreInlineCode() {
        #expect(block("```code```") == .paragraph)
    }

    @Test func blankLines() {
        #expect(blocks("a\n\n   \nb") == [.paragraph, .blank, .blank, .paragraph])
    }
}
