/// Generates the seeded first-run "Welcome" note. Pure text; the first line
/// doubles as the note's sidebar title (see `NoteTitle`), which itself
/// demonstrates the title-from-first-line rule to the new user. Written in
/// Markdown, so it shows off the styling, and its headings fill the outline.
public enum WelcomeNote {
    public static func text(hotKeyDisplay: String) -> String {
        """
        # Welcome to Popup Notes 👋

        Press \(hotKeyDisplay) in any app to open this panel — Esc, ⌘W or a click outside dismisses it.

        ## Basics
        - The first line of a note is its title in the sidebar.
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
