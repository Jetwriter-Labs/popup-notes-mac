import Testing
import Foundation
@testable import PopupNotesCore

@Suite struct MarkdownOutlineTests {
    @Test func listsHeadingsInOrderWithTheirDepth() {
        let headings = MarkdownOutline.headings(in: """
            # Trip
            notes
            ## Flights
            ### Return
            ## Hotel
            # Budget
            """)
        #expect(headings.map(\.title) == ["Trip", "Flights", "Return", "Hotel", "Budget"])
        #expect(headings.map(\.level) == [1, 2, 3, 2, 1])
        #expect(headings.map(\.depth) == [0, 1, 2, 1, 0])
    }

    @Test func skippedLevelsIndentOneStep() {
        let headings = MarkdownOutline.headings(in: "# Top\n### Detail\n## Middle")
        #expect(headings.map(\.depth) == [0, 1, 1])
    }

    @Test func outlineStartingAtLevelTwoIsNotIndented() {
        #expect(MarkdownOutline.headings(in: "## A\n### B\n## C").map(\.depth) == [0, 1, 0])
    }

    @Test func headingsInCodeBlocksDoNotCount() {
        let headings = MarkdownOutline.headings(in: "# Real\n```\n# comment\n```\n## Also real")
        #expect(headings.map(\.title) == ["Real", "Also real"])
    }

    @Test func emptyHeadingsAreLeftOut() {
        #expect(MarkdownOutline.headings(in: "#\n## \n# Kept").map(\.title) == ["Kept"])
    }

    @Test func titlesReadWithoutSyntax() {
        let headings = MarkdownOutline.headings(in: "## **Bold** `code` [link](https://x.com) ##")
        #expect(headings.map(\.title) == ["Bold code link"])
    }

    @Test func rangesPointAtTheHeadingLine() {
        let text = "😀 intro\n## Next"
        let heading = MarkdownOutline.headings(in: text)[0]
        #expect(heading.range == NSRange(location: 9, length: 7))
        #expect((text as NSString).substring(with: heading.range) == "## Next")
    }

    @Test func veryLongTitlesAreCapped() {
        let headings = MarkdownOutline.headings(in: "# " + String(repeating: "x", count: 1_000))
        #expect(headings[0].title.count == MarkdownOutline.maxTitleLength)
    }

    @Test func sectionContainingALocation() {
        let text = "intro\n# A\naaa\n# B\nbbb"
        let headings = MarkdownOutline.headings(in: text)
        #expect(MarkdownOutline.section(containing: 0, in: headings) == nil) // above the first heading
        #expect(MarkdownOutline.section(containing: 6, in: headings) == 0)   // on "# A"
        #expect(MarkdownOutline.section(containing: 12, in: headings) == 0)  // in A's body
        #expect(MarkdownOutline.section(containing: 14, in: headings) == 1)  // on "# B"
        #expect(MarkdownOutline.section(containing: text.utf16.count, in: headings) == 1)
        #expect(MarkdownOutline.section(containing: 3, in: []) == nil)
    }
}
