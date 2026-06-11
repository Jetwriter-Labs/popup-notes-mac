/// Generates the seeded first-run "Welcome" note. Pure text; the first line
/// doubles as the note's sidebar title (see `NoteTitle`), which itself
/// demonstrates the title-from-first-line rule to the new user.
public enum WelcomeNote {
    public static func text(hotKeyDisplay: String) -> String {
        """
        Welcome to Popup Notes 👋

        Press \(hotKeyDisplay) in any app to open this panel — Esc or a click outside dismisses it.

        A few basics:
        • The first line of a note is its title in the sidebar.
        • ⌘N makes a new note · right-click a note to delete it.
        • Notes save automatically and live only on this Mac.
        • Settings (⌘,): change the shortcut, launch at login, export your notes.

        Delete this note whenever you're done with it.
        """
    }
}
