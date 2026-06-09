import SwiftUI
import AppKit
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
        .overlay(alignment: .topTrailing) { optionsMenu.padding(6) }
        .onAppear { editorFocused = true }
        .onExitCommand { onDismiss() }          // Esc
    }

    /// Discreet ⋯ menu so the app's options are reachable from the popup itself
    /// (not just the menu-bar item, which can be hidden behind the notch).
    private var optionsMenu: some View {
        Menu {
            Button("Open Notes File") { NotesFile.revealInFinder(store) }
            Toggle("Launch at Login", isOn: Binding(
                get: { LaunchAtLogin.isEnabled },
                set: { LaunchAtLogin.isEnabled = $0 }
            ))
            Divider()
            Button("Quit Popup Notes") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Options")
    }
}
