import Foundation
import Observation
import PopupNotesCore

/// The open note's outline, shared by its editor, which keeps it current,
/// and the outline pane, which shows it and asks the editor to jump.
@Observable
final class NoteOutline {
    /// `UserDefaults` key: whether the outline pane is shown.
    static let showsOutlineKey = "showsOutline"

    /// The setting itself, for code outside SwiftUI's `@AppStorage`. Shown
    /// until the user hides it.
    static var isShown: Bool {
        get { UserDefaults.standard.object(forKey: showsOutlineKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showsOutlineKey) }
    }

    private(set) var headings: [MarkdownHeading] = []
    /// The heading whose section the user is in: the one around the caret,
    /// or at the top of the editor when the caret is scrolled out of view.
    private(set) var current: Int?
    /// Two headings make an outline worth its room; one is just a title.
    /// Kept apart from `headings` so the detail view, which only decides
    /// whether to show the pane, isn't redrawn on every keystroke.
    private(set) var isWorthShowing = false

    /// Set by the editor: scrolls it to a heading.
    @ObservationIgnored var revealHeading: ((MarkdownHeading) -> Void)?

    // Observation notifies on every assignment, equal or not, so only real
    // changes are written.

    func update(headings: [MarkdownHeading]) {
        guard headings != self.headings else { return }
        self.headings = headings
        let worthShowing = headings.count >= 2
        if worthShowing != isWorthShowing { isWorthShowing = worthShowing }
    }

    func update(current: Int?) {
        if current != self.current { self.current = current }
    }

    func reveal(_ index: Int) {
        guard headings.indices.contains(index) else { return }
        revealHeading?(headings[index])
    }
}
