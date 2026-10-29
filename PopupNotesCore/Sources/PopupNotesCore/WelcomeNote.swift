/// The seeded first-run "Welcome" note: a title, and text in Markdown, so it
/// shows off the styling, and its headings fill the outline.
public enum WelcomeNote {
    public static let title = "Welcome to Popup Notes 👋"

    public static func text(hotKeyDisplay: String) -> String {
        """
        Press \(hotKeyDisplay) in any app to open this panel — Esc, ⌘W or a click outside dismisses it.

        ## Basics
        - A note's title goes in the field at the top; Return moves on to the text below.
        - ⌘N makes a new note · right-click a note to delete it.
        - Notes save automatically and live only on this Mac.
        - Settings (⌘,): change the shortcut, launch at login, export your notes.

        ## Markdown
        - Start a line with `#` for a heading; type **bold** (⌘B), *italic* (⌘I) or `code`.
        - Lists carry on when you press Return, and Tab nests them.
        - [ ] Click a box to check off a task.
        ▸ Type > and a space for a toggle — click its arrow to open it.
        \tWhatever is indented under a toggle folds away with it. ⌘↩ opens or closes the one you're in.

        ## Outline
        Headings appear in the outline beside the note — click one to jump to it.

        Delete this note whenever you're done with it.
        """
    }
}
