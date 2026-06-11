import SwiftUI
import AppKit
import PopupNotesCore

/// Sidebar: the list of notes (title + relative date), a New Note button, and an
/// options menu (Settings, Quit). Delete is a confirmed context-menu action.
struct NotesListView: View {
    let notes: [Note]
    @Binding var selection: UUID?
    var onNew: () -> Void
    var onDelete: (Note) -> Void

    @State private var pendingDelete: Note?

    var body: some View {
        List(selection: $selection) {
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title).lineLimit(1)
                    Text(note.modified, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(note.id)
                .contextMenu {
                    Button("Delete", role: .destructive) { pendingDelete = note }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button(action: onNew) { Image(systemName: "square.and.pencil") }
                    .keyboardShortcut("n", modifiers: .command)
                    .help("New Note (⌘N)")
            }
            ToolbarItem {
                Menu {
                    SettingsLink { Text("Settings…") }
                    Divider()
                    Button("Quit Popup Notes") { NSApplication.shared.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("Options")
            }
        }
        .confirmationDialog("Delete this note?", isPresented: deletePresented, presenting: pendingDelete) { note in
            Button("Delete", role: .destructive) { onDelete(note); pendingDelete = nil }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    private var deletePresented: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }
}
