import SwiftUI
import PopupNotesCore

/// The editor for the selected note. Editing the text bumps `modified` so the
/// note re-sorts to the top of the sidebar.
struct NoteDetailView: View {
    @Bindable var note: Note
    /// Changing it moves keyboard focus into the editor (see NotesView.newNote).
    var focusRequest = 0
    /// Whether the editor takes keyboard focus when it appears (see NotesView).
    var takesFocus = true

    var body: some View {
        NoteTextEditor(text: Binding(
            get: { note.text },
            set: { note.text = $0; note.modified = .now }
        ), focusRequest: focusRequest, takesFocusOnAppear: takesFocus)
        // The detail column's 52pt top toolbar strip is empty (controls live in
        // the sidebar), so let the editor fill it and start the text at the top.
        // Top only — the bottom safe area carries the onboarding strip (see NotesView).
        .ignoresSafeArea(.container, edges: .top)
    }
}
