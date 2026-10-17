import Testing
import Foundation
@testable import PopupNotesCore

@Suite struct MarkdownInlineTests {
    /// The text each span of `kind` covers, in order.
    private func covered(_ kind: MarkdownSpan.Kind, in string: String) -> [String] {
        let text = MarkdownText(string)
        return MarkdownInline.spans(in: text, range: NSRange(location: 0, length: text.length))
            .filter { $0.kind == kind }
            .map { text.string(in: $0.range) }
    }

    private func styled(_ string: String) -> Bool {
        let text = MarkdownText(string)
        return !MarkdownInline.spans(in: text, range: NSRange(location: 0, length: text.length)).isEmpty
    }

    private func plain(_ string: String) -> String {
        let text = MarkdownText(string)
        return MarkdownInline.plainText(in: text, range: NSRange(location: 0, length: text.length))
    }

    // MARK: Emphasis

    @Test func strong() {
        #expect(covered(.strong, in: "a **bold** b") == ["**bold**"])
        #expect(covered(.syntax, in: "a **bold** b") == ["**", "**"])
        #expect(covered(.strong, in: "__bold__") == ["__bold__"])
    }

    @Test func emphasis() {
        #expect(covered(.emphasis, in: "an *italic* word") == ["*italic*"])
        #expect(covered(.emphasis, in: "an _italic_ word") == ["_italic_"])
    }

    @Test func strongInsideEmphasis() {
        #expect(covered(.emphasis, in: "***both***") == ["***both***"])
        #expect(covered(.strong, in: "***both***") == ["**both**"])
    }

    @Test func emphasisNestedInStrong() {
        #expect(covered(.strong, in: "**bold *it* bold**") == ["**bold *it* bold**"])
        #expect(covered(.emphasis, in: "**bold *it* bold**") == ["*it*"])
    }

    @Test func ruleOfThree() {
        #expect(covered(.emphasis, in: "*foo**bar**baz*") == ["*foo**bar**baz*"])
        #expect(covered(.strong, in: "*foo**bar**baz*") == ["**bar**"])
    }

    @Test func underscoresInsideWordsStayPlain() {
        #expect(!styled("call snake_case_name here"))
    }

    @Test func asterisksInsideWordsEmphasize() {
        #expect(covered(.emphasis, in: "un*frigging*believable") == ["*frigging*"])
    }

    @Test(arguments: ["5 * 3 = 15", "a * b * c", "**open", "close**", "*not closed", "* spaced *"])
    func nothingToStyle(_ string: String) {
        #expect(!styled(string))
    }

    @Test func emojiNextToDelimiters() {
        #expect(covered(.strong, in: "**😀**") == ["**😀**"])
        #expect(covered(.emphasis, in: "*hi*😀") == ["*hi*"])
    }

    @Test func strikethroughNeedsTwoTildes() {
        #expect(covered(.strikethrough, in: "~~gone~~") == ["~~gone~~"])
        #expect(!styled("about ~5 min, ~10 tops"))
        #expect(!styled("~~~three~~~"))
    }

    // MARK: Code

    @Test func codeSpans() {
        #expect(covered(.code, in: "run `make` now") == ["`make`"])
        #expect(covered(.syntax, in: "run `make` now") == ["`", "`"])
        #expect(covered(.code, in: "``a ` b``") == ["``a ` b``"])
    }

    @Test func nothingInsideCodeIsStyled() {
        #expect(covered(.code, in: "`**not bold**`") == ["`**not bold**`"])
        #expect(covered(.strong, in: "`**not bold**`").isEmpty)
    }

    @Test func codeInsideStrong() {
        #expect(covered(.strong, in: "**a `b` c**") == ["**a `b` c**"])
        #expect(covered(.code, in: "**a `b` c**") == ["`b`"])
    }

    @Test func unclosedBacktickIsText() {
        #expect(!styled("it`s fine"))
    }

    @Test func backslashEscapes() {
        #expect(covered(.emphasis, in: "\\*not italic\\*").isEmpty)
        #expect(covered(.syntax, in: "\\*not italic\\*") == ["\\", "\\"])
    }

    // MARK: Links

    @Test func inlineLink() {
        let string = "see [the docs](https://example.com) now"
        #expect(covered(.link, in: string) == ["the docs"])
        #expect(covered(.url, in: string) == ["https://example.com"])
        #expect(covered(.syntax, in: string) == ["[", "](", ")"])
    }

    @Test func imageLink() {
        #expect(covered(.syntax, in: "![alt](cat.png)") == ["![", "](", ")"])
        #expect(covered(.link, in: "![alt](cat.png)") == ["alt"])
    }

    @Test func linkDestinationWithParentheses() {
        #expect(covered(.url, in: "[w](https://en.wikipedia.org/wiki/Swift_(language))")
                == ["https://en.wikipedia.org/wiki/Swift_(language)"])
    }

    @Test func emphasisInsideLinkText() {
        #expect(covered(.strong, in: "[**big** deal](u)") == ["**big**"])
    }

    @Test(arguments: ["[just brackets]", "[text] (space)", "[unclosed](paren", "[x]"])
    func notLinks(_ string: String) {
        #expect(covered(.link, in: string).isEmpty)
    }

    @Test func autolink() {
        #expect(covered(.link, in: "<https://example.com/a_b_>") == ["https://example.com/a_b_"])
        #expect(covered(.syntax, in: "<https://example.com>") == ["<", ">"])
        #expect(covered(.link, in: "<notalink>").isEmpty)
        #expect(covered(.link, in: "a <b> c").isEmpty)
    }

    @Test func bareURLs() {
        #expect(covered(.link, in: "see https://example.com/some_path_here.") == ["https://example.com/some_path_here"])
        #expect(covered(.link, in: "(https://example.com)") == ["https://example.com"])
        #expect(covered(.link, in: "https://en.wikipedia.org/wiki/Swift_(language)")
                == ["https://en.wikipedia.org/wiki/Swift_(language)"])
        #expect(covered(.link, in: "HTTP://EXAMPLE.COM") == ["HTTP://EXAMPLE.COM"])
        #expect(covered(.emphasis, in: "https://example.com/*star*").isEmpty)
    }

    @Test(arguments: ["xhttps://a.b", "https://", "http:// x", "ftp://a.b"])
    func notBareURLs(_ string: String) {
        #expect(covered(.link, in: string).isEmpty)
    }

    @Test func boldURL() {
        #expect(covered(.strong, in: "**https://example.com**") == ["**https://example.com**"])
        #expect(covered(.link, in: "**https://example.com**") == ["https://example.com"])
    }

    // MARK: Limits and plain text

    @Test func veryLongLinesAreNotParsed() {
        let string = "**x**" + String(repeating: "a", count: MarkdownInline.maxLength)
        #expect(!styled(string))
    }

    @Test func anUnmatchedCloserDoesNotHideOpenersOfAnotherKind() {
        // The `_` finds no opener, which bounds later `_` searches — not `*` ones.
        #expect(covered(.emphasis, in: "*a b_ c*") == ["*a b_ c*"])
    }

    @Test func plainTextDropsSyntax() {
        #expect(plain("**Bold** and *it*, `code`, [link](url) \\*") == "Bold and it, code, link *")
        #expect(plain("<https://x.com>") == "https://x.com")
        #expect(plain("no markdown") == "no markdown")
    }
}
