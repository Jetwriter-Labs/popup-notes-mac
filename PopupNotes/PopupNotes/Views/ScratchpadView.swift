import SwiftUI
import PopupNotesCore

/// The chromeless editor: a TextEditor bound to NoteStore, a placeholder when
/// empty, material background, and Esc-to-dismiss.
struct ScratchpadView: View {
    @Bindable var store: NoteStore
    var onDismiss: () -> Void

    @FocusState private var editorFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: Binding(
                get: { store.text },
                set: { store.updateText($0) }
            ))
            .font(.body)
            .scrollContentBackground(.hidden)   // let the material show through
            .padding(12)
            .focused($editorFocused)

            if store.text.isEmpty {
                Text("Jot a note…")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 17)
                    .padding(.vertical, 20)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 480, height: 320)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear { editorFocused = true }
        .onExitCommand { onDismiss() }          // Esc
    }
}
