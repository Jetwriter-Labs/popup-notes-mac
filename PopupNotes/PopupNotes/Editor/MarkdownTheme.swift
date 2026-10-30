import AppKit

extension NSAttributedString.Key {
    /// Marks the lines whose background `MarkdownTextView` draws: a
    /// `MarkdownTheme.Decoration` raw value.
    static let markdownDecoration = NSAttributedString.Key("PopupNotesMarkdownDecoration")
    /// Marks the lines a closed toggle folds away: they aren't laid out.
    nonisolated static let markdownHidden = NSAttributedString.Key("PopupNotesMarkdownHidden")
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
    /// Lines a fifth taller than the font's own, and room after each
    /// paragraph and list item, so a note reads as lines of text rather
    /// than one dense block.
    let lineHeightMultiple: CGFloat = 1.2
    let paragraphSpacing: CGFloat = 6
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

    /// Body text two sizes up from the system's 13 pt, which suits a
    /// control's label more than a note you read and write in.
    init(bodySize: CGFloat = NSFont.preferredFont(forTextStyle: .body).pointSize + 2) {
        bodyFont = .systemFont(ofSize: bodySize)
        codeFont = .monospacedSystemFont(ofSize: (bodySize * 0.92).rounded(), weight: .regular)
    }

    /// The note's title, in its field above the text: a step up from a `#`
    /// heading, so it reads as the title rather than one more heading.
    lazy var titleFont = font(size: (headingFont(level: 1).pointSize * 1.2).rounded(), weight: .bold)

    // MARK: Attributes

    /// Plain text — and what the editor types with, so an empty line's
    /// caret is body-sized even right below a big heading.
    lazy var baseAttributes: [NSAttributedString.Key: Any] = [
        .font: bodyFont,
        .foregroundColor: textColor,
        .paragraphStyle: paragraphStyle(),
    ]

    func headingFont(level: Int) -> NSFont {
        let scale: [CGFloat] = [1.5, 1.3, 1.15, 1, 1, 1]
        let size = (bodyFont.pointSize * scale[min(max(level, 1), 6) - 1]).rounded()
        return font(size: size, weight: level <= 2 ? .bold : .semibold)
    }

    /// Air above headings sets sections apart — but not above the first
    /// line, where it would only push the text away from the title. Less
    /// below, so a heading sits with the lines it heads.
    func headingParagraphStyle(level: Int, isFirstLine: Bool) -> NSParagraphStyle {
        let before: CGFloat = isFirstLine ? 0 : [12, 10, 8, 6, 6, 6][min(max(level, 1), 6) - 1]
        return paragraphStyle(spacingBefore: before, spacingAfter: 2, lineHeightMultiple: 1.1)
    }

    /// An empty line is space enough: none added after it.
    lazy var blankParagraphStyle = paragraphStyle(spacingAfter: 0)

    /// Wrapped lines of a list item or quote line up under its text, not
    /// under its marker. `prefix` is the line's leading syntax as typed.
    func hangingParagraphStyle(prefix: String, firstLineIndent: CGFloat = 0) -> NSParagraphStyle {
        paragraphStyle(firstLineIndent: firstLineIndent, headIndent: firstLineIndent + width(of: prefix))
    }

    /// A toggle's arrow — its `▾` / `▸` marker — a size up from the text, so
    /// it's easy to see and to click.
    lazy var toggleMarkerFont = font(size: (bodyFont.pointSize * 1.3).rounded())

    /// A toggle's title starts at the tab stop past its marker, where the
    /// lines indented under it start too: `kern` widens the space after the
    /// marker to reach it, and wrapped title lines line up there. The line
    /// keeps the body text's height, bigger arrow and all. (The height is
    /// multiplied before it's held to that, so it's the multiplied one.)
    func toggleTitleIndent(prefix: String) -> (kern: CGFloat, paragraphStyle: NSParagraphStyle) {
        let prefixWidth = width(of: prefix, markerFont: toggleMarkerFont)
        let stop = (prefixWidth / tabInterval).rounded(.up) * tabInterval
        let style = paragraphStyle(headIndent: stop).mutableCopy() as! NSMutableParagraphStyle
        style.minimumLineHeight = bodyLineHeight * lineHeightMultiple
        style.maximumLineHeight = bodyLineHeight * lineHeightMultiple
        return (stop - prefixWidth, style)
    }

    /// Where the lines inside a toggle start: its title's indent.
    func toggleContentIndent(prefix: String) -> CGFloat {
        toggleTitleIndent(prefix: prefix).paragraphStyle.headIndent
    }

    private lazy var bodyLineHeight = (bodyFont.ascender - bodyFont.descender + bodyFont.leading).rounded(.up)

    /// A code block's lines stay together, as code is written.
    func codeParagraphStyle() -> NSParagraphStyle {
        paragraphStyle(firstLineIndent: codeInset, headIndent: codeInset, tailIndent: -codeInset, spacingAfter: 0,
                       lineHeightMultiple: 1.1)
    }

    private func paragraphStyle(firstLineIndent: CGFloat = 0, headIndent: CGFloat = 0, tailIndent: CGFloat = 0,
                                spacingBefore: CGFloat = 0, spacingAfter: CGFloat? = nil,
                                lineHeightMultiple: CGFloat? = nil) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.tabStops = []
        style.defaultTabInterval = tabInterval
        style.firstLineHeadIndent = firstLineIndent
        style.headIndent = headIndent
        style.tailIndent = tailIndent
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter ?? paragraphSpacing
        style.lineHeightMultiple = lineHeightMultiple ?? self.lineHeightMultiple
        return style
    }

    /// The width of a line's leading syntax in the body font, tabs included
    /// — its marker (the first character past the indentation) in
    /// `markerFont`, if given.
    private func width(of prefix: String, markerFont: NSFont? = nil) -> CGFloat {
        let key = markerFont == nil ? prefix : "\u{1}" + prefix
        if let width = prefixWidths[key] { return width }
        let measuring = NSMutableAttributedString(string: prefix, attributes: [
            .font: bodyFont, .paragraphStyle: paragraphStyle(),
        ])
        if let markerFont, let marker = prefix.utf16.firstIndex(where: { $0 != 0x20 && $0 != 0x09 }) {
            let location = prefix.utf16.distance(from: prefix.utf16.startIndex, to: marker)
            measuring.addAttribute(.font, value: markerFont, range: NSRange(location: location, length: 1))
        }
        let measured = measuring.size().width.rounded(.up)
        if prefixWidths.count > 500 { prefixWidths.removeAll() } // prefixes repeat; this never really grows
        prefixWidths[key] = measured
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
