import SwiftUI
import PopupNotesCore

/// The editor for the selected note. Editing the text bumps `modified` so the
/// note re-sorts to the top of the sidebar.
struct NoteDetailView: View {
    @Bindable var note: Note

    var body: some View {
        NoteTextEditor(text: Binding(
            get: { note.text },
            set: { note.text = $0; note.modified = .now }
        ))
    }
}
