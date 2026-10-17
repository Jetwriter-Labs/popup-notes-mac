import AppKit

extension NSAttributedString.Key {
    /// Marks the lines whose background `MarkdownTextView` draws: a
    /// `MarkdownTheme.Decoration` raw value.
    static let markdownDecoration = NSAttributedString.Key("PopupNotesMarkdownDecoration")
}

/// How Markdown looks in the editor: fonts, colors and paragraph styles.
/// Colors are the system's dynamic ones, so light and dark mode and
/// Increase Contrast need nothing extra.
final class MarkdownTheme {
    static let shared = MarkdownTheme()

    /// Line backgrounds drawn by the text view, not by text attributes.
    enum Decoration: Int {
        case code = 1
        case quote
        case rule
    }

    let bodyFont: NSFont
    let codeFont: NSFont
    /// Where tabs stop: list nesting is done with tabs, so this is the
    /// width of one level.
    let tabInterval: CGFloat = 20
    /// Room on each side of the text inside a code block's background.
    let codeInset: CGFloat = 6
    /// Room for the bar drawn left of a quote.
    let quoteInset: CGFloat = 12

    let textColor = NSColor.textColor
    /// `#`, `**`, backticks and the like: present, but quiet.
    let syntaxColor = NSColor.tertiaryLabelColor
    let listMarkerColor = NSColor.secondaryLabelColor
    let quoteColor = NSColor.secondaryLabelColor
    let doneColor = NSColor.secondaryLabelColor
    let linkColor = NSColor.linkColor
    let codeBackground = NSColor.quaternarySystemFill
    let quoteBar = NSColor.tertiaryLabelColor
    let ruleColor = NSColor.separatorColor
    /// A rule's own `---`, faint under the line drawn through it.
    let ruleSyntaxColor = NSColor.quaternaryLabelColor

    private var fonts: [FontKey: NSFont] = [:]
    private var prefixWidths: [String: CGFloat] = [:]

    init(bodySize: CGFloat = NSFont.preferredFont(forTextStyle: .body).pointSize) {
        bodyFont = .systemFont(ofSize: bodySize)
        codeFont = .monospacedSystemFont(ofSize: (bodySize * 0.92).rounded(), weight: .regular)
    }

    // MARK: Attributes

    /// Plain text — and what the editor types with, so an empty line's
    /// caret is body-sized even right below a big heading.
    lazy var baseAttributes: [NSAttributedString.Key: Any] = [
        .font: bodyFont,
        .foregroundColor: textColor,
        .paragraphStyle: paragraphStyle(),
    ]

    func headingFont(level: Int) -> NSFont {
        let scale: [CGFloat] = [1.6, 1.35, 1.15, 1, 1, 1]
        let size = (bodyFont.pointSize * scale[min(max(level, 1), 6) - 1]).rounded()
        return font(size: size, weight: level <= 2 ? .bold : .semibold)
    }

    /// Air above headings sets sections apart — but not above the first
    /// line, where it would only push the note's title down.
    func headingParagraphStyle(level: Int, isFirstLine: Bool) -> NSParagraphStyle {
        let before: CGFloat = isFirstLine ? 0 : [8, 6, 4, 2, 2, 2][min(max(level, 1), 6) - 1]
        return paragraphStyle(spacingBefore: before)
    }

    /// Wrapped lines of a list item or quote line up under its text, not
    /// under its marker. `prefix` is the line's leading syntax as typed.
    func hangingParagraphStyle(prefix: String, firstLineIndent: CGFloat = 0) -> NSParagraphStyle {
        paragraphStyle(firstLineIndent: firstLineIndent, headIndent: firstLineIndent + width(of: prefix))
    }

    func codeParagraphStyle() -> NSParagraphStyle {
        paragraphStyle(firstLineIndent: codeInset, headIndent: codeInset, tailIndent: -codeInset)
    }

    private func paragraphStyle(firstLineIndent: CGFloat = 0, headIndent: CGFloat = 0, tailIndent: CGFloat = 0,
                                spacingBefore: CGFloat = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.tabStops = []
        style.defaultTabInterval = tabInterval
        style.firstLineHeadIndent = firstLineIndent
        style.headIndent = headIndent
        style.tailIndent = tailIndent
        style.paragraphSpacingBefore = spacingBefore
        return style
    }

    /// The width of a line's leading syntax in the body font, tabs included.
    private func width(of prefix: String) -> CGFloat {
        if let width = prefixWidths[prefix] { return width }
        let measured = NSAttributedString(string: prefix, attributes: [
            .font: bodyFont, .paragraphStyle: paragraphStyle(),
        ]).size().width.rounded(.up)
        if prefixWidths.count > 500 { prefixWidths.removeAll() } // prefixes repeat; this never really grows
        prefixWidths[prefix] = measured
        return measured
    }

    // MARK: Fonts

    private struct FontKey: Hashable {
        var size: CGFloat
        var weight: CGFloat
        var italic: Bool
        var monospaced: Bool
    }

    /// The system font, or SF Mono, with the given traits. Cached: every
    /// restyled line asks for the same handful of fonts.
    func font(size: CGFloat, weight: NSFont.Weight = .regular, italic: Bool = false,
              monospaced: Bool = false) -> NSFont {
        let key = FontKey(size: size, weight: weight.rawValue, italic: italic, monospaced: monospaced)
        if let font = fonts[key] { return font }
        var font: NSFont = monospaced ? .monospacedSystemFont(ofSize: size, weight: weight)
                                      : .systemFont(ofSize: size, weight: weight)
        if italic {
            let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.italic))
            font = NSFont(descriptor: descriptor, size: size) ?? font
        }
        fonts[key] = font
        return font
    }
}
