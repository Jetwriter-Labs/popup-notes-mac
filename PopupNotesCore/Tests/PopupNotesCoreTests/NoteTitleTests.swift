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
}
