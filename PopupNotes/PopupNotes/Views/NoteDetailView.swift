import SwiftUI
import PopupNotesCore

/// The editor for the selected note. Editing the text bumps `modified` so the
/// note re-sorts to the top of the sidebar.
struct NoteDetailView: View {
    @Bindable var note: Note
    @FocusState private var focused: Bool

    var body: some View {
        TextEditor(text: Binding(
            get: { note.text },
            set: { note.text = $0; note.modified = .now }
        ))
        .font(.body)
        .scrollContentBackground(.hidden)
        .padding(8)
        .focused($focused)
        .onAppear { focused = true }
    }
}
