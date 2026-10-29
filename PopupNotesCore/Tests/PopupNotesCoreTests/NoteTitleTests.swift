import Testing
@testable import PopupNotesCore

@Suite struct NoteTitleTests {
    @Test func emptyIsNewNote() { #expect(NoteTitle.title(from: "") == "New Note") }
    @Test func whitespaceOnlyIsNewNote() { #expect(NoteTitle.title(from: "   \n\n ") == "New Note") }
    @Test func firstNonEmptyLine() { #expect(NoteTitle.title(from: "Hello\nworld") == "Hello") }
    @Test func skipsLeadingBlankLines() { #expect(NoteTitle.title(from: "\n\n  Groceries \nmilk") == "Groceries") }

    // "\r\n" is ONE Character in Swift, so a split on "\n" never sees it.
    @Test func crlfEndsTheTitleLine() { #expect(NoteTitle.title(from: "Title\r\nBody") == "Title") }
    @Test func loneCarriageReturnEndsTheTitleLine() { #expect(NoteTitle.title(from: "A\rB") == "A") }
    @Test func unicodeLineSeparatorEndsTheTitleLine() { #expect(NoteTitle.title(from: "A\u{2028}B") == "A") }
    @Test func crlfOnlyIsNewNote() { #expect(NoteTitle.title(from: "\r\n \r\n\t") == "New Note") }
    @Test func skipsLeadingCRLFBlankLines() { #expect(NoteTitle.title(from: "\r\n\r\n  Title\r\nx") == "Title") }

    @Test func trimsTabsAndNonBreakingSpaces() {
        #expect(NoteTitle.title(from: "\t\u{00A0} Plan \t\nx") == "Plan")
    }

    @Test func keepsEmoji() {
        #expect(NoteTitle.title(from: "Welcome to Popup Notes 👋\n\nbody") == "Welcome to Popup Notes 👋")
    }

    @Test func capsAVeryLongLine() {
        let title = NoteTitle.title(from: String(repeating: "x", count: 10_000))
        #expect(title.count == NoteTitle.maxLength)
    }

    @Test func capNeverSplitsAGraphemeCluster() {
        let family = "👨‍👩‍👧‍👦"
        let text = String(repeating: "a", count: NoteTitle.maxLength - 1) + family + "tail"
        let title = NoteTitle.title(from: text)
        #expect(title.count == NoteTitle.maxLength)
        #expect(title.hasSuffix(family))
    }

    @Test func longBodyStillYieldsTheFirstLine() {
        let text = "Shopping\n" + String(repeating: "line\n", count: 50_000)
        #expect(NoteTitle.title(from: text) == "Shopping")
    }

    // MARK: Markdown

    @Test(arguments: [
        ("# Plan\nbody", "Plan"),
        ("## **Bold** move", "Bold move"),
        ("- [ ] buy milk", "buy milk"),
        ("1. First step", "First step"),
        ("> quoted", "quoted"),
        ("[Docs](https://example.com) to read", "Docs to read"),
        ("`make` fails", "make fails"),
    ])
    func titleReadsWithoutMarkdown(_ text: String, title: String) {
        #expect(NoteTitle.title(from: text) == title)
    }

    @Test(arguments: [("#", "#"), ("---", "---"), ("```swift", "```swift"), ("#hashtag", "#hashtag"),
                      ("- ", "-"), ("**", "**")])
    func syntaxOnlyTitleIsKeptAsTyped(_ text: String, title: String) {
        #expect(NoteTitle.title(from: text) == title)
    }

    @Test func previewReadsWithoutMarkdown() {
        #expect(NoteTitle.preview(from: "# Groceries\n- milk\n- eggs") == "milk")
        #expect(NoteTitle.preview(from: "Title\n\n## Section **one**") == "Section one")
    }

    // MARK: Preview

    @Test func previewIsTheNextNonBlankLine() {
        #expect(NoteTitle.preview(from: "Shopping\n\n  milk  \neggs") == "milk")
    }

    @Test func previewIsEmptyWithoutASecondLine() {
        #expect(NoteTitle.preview(from: "Only a title") == "")
        #expect(NoteTitle.preview(from: "Title\n \n\t") == "")
        #expect(NoteTitle.preview(from: "") == "")
    }

    @Test func previewHandlesCRLF() {
        #expect(NoteTitle.preview(from: "Title\r\n\r\nBody line\r\nmore") == "Body line")
    }

    @Test func previewSkipsTheWholeTitleLineEvenWhenItIsLong() {
        let text = String(repeating: "t", count: 500) + "\nsecond"
        #expect(NoteTitle.preview(from: text) == "second")
    }

    @Test func previewIsCapped() {
        let preview = NoteTitle.preview(from: "T\n" + String(repeating: "p", count: 1_000))
        #expect(preview.count == NoteTitle.maxLength)
    }

    @Test func previewGivesUpOnATitleLineLongerThanTheScanWindow() {
        let text = String(repeating: "t", count: NoteTitle.previewScanLimit + 10) + "\nsecond"
        #expect(NoteTitle.preview(from: text) == "")
    }

    // MARK: A title of its own

    @Test func aTitleNamesTheNoteAsTyped() {
        #expect(NoteTitle.title("  Plan **B**  ", text: "# Something else") == "Plan **B**")
    }

    @Test func aBlankTitleFallsBackToTheFirstLine() {
        #expect(NoteTitle.title(" \t", text: "# Groceries\nmilk") == "Groceries")
        #expect(NoteTitle.title("", text: "") == "New Note")
    }

    @Test func aLongTitleIsCapped() {
        #expect(NoteTitle.title(String(repeating: "t", count: 500), text: "").count == NoteTitle.maxLength)
    }

    @Test func underATitleThePreviewIsTheFirstLine() {
        #expect(NoteTitle.preview(title: "Groceries", text: "\n- milk\n- eggs") == "milk")
        #expect(NoteTitle.preview(title: "Groceries", text: "") == "")
    }

    @Test func untitledThePreviewSkipsTheLineThatNamesTheNote() {
        #expect(NoteTitle.preview(title: "", text: "Groceries\n- milk") == "milk")
    }

    @Test func singleLineTurnsLineBreaksIntoSpaces() {
        #expect(NoteTitle.singleLine("A\nB\r\nC\u{2028}D") == "A B C D")
        #expect(NoteTitle.singleLine("Plain") == "Plain")
    }

    // MARK: Moving a first line into the title

    @Test(arguments: [
        ("# Plan\n\nbody", "Plan", "body"),
        ("Groceries\nmilk", "Groceries", "milk"),
        ("\n\n  ## Week 12 ##  \n \n\tindented stays\nmore", "Week 12", "\tindented stays\nmore"),
        ("Only a title", "Only a title", ""),
        ("Title\r\n\r\nCRLF body", "Title", "CRLF body"),
        ("Welcome 👋\n- item", "Welcome 👋", "- item"),
    ])
    func splitMovesAHeadingOrPlainLine(_ text: String, title: String, rest: String) throws {
        let split = try #require(NoteTitle.split(text))
        #expect(split.title == title)
        #expect(split.text == rest)
    }

    @Test(arguments: [
        "- [ ] buy milk\nmore", "1. First\n2. Second", "> quoted", "▸ Toggle\n\tinside", "```\ncode\n```",
        "---\nafter", "#\nbare hash", "**Bold** start", "[Docs](https://example.com) to read", "`make` fails",
        "2*3*4 is 24", "", " \n\t\n",
    ])
    func splitLeavesWhatIsPartOfTheNote(_ text: String) {
        #expect(NoteTitle.split(text) == nil)
    }

    @Test func splitLeavesAParagraphLongerThanATitle() {
        let long = String(repeating: "word ", count: 40) + "\nbody"
        #expect(NoteTitle.split(long) == nil)
    }
}
