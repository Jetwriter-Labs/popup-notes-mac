import SwiftUI
import AppKit
import PopupNotesCore

/// Sidebar: the list of notes (title, then date · preview), a New Note button,
/// and an options menu (New Note, Settings, Quit). Delete — from the context
/// menu, VoiceOver's actions, or ⌫ with the list focused — asks first unless
/// the note is blank.
struct NotesListView: View {
    let notes: [Note]
    @Binding var selection: UUID?
    var onNew: () -> Void
    /// The note, and whether the delete came from ⌫ in the list.
    var onDelete: (Note, Bool) -> Void

    /// A snapshot, not the model: the dialog's title must not track live edits.
    @State private var pendingDelete: PendingDelete?

    var body: some View {
        List(selection: $selection) {
            ForEach(notes) { note in
                NoteRow(note: note)
                    .tag(note.id)
                    .contextMenu {
                        Button("Delete", role: .destructive) { requestDelete(note, fromKeyboard: false) }
                    }
                    .accessibilityAction(named: "Delete") { requestDelete(note, fromKeyboard: false) }
            }
        }
        .onDeleteCommand(perform: deleteSelected)
        .toolbar {
            ToolbarItem {
                Button("New Note", systemImage: "square.and.pencil", action: onNew)
                    .labelStyle(.iconOnly)
                    .keyboardShortcut("n", modifiers: .command)
                    .help("New Note (⌘N)")
            }
            ToolbarItem {
                Menu("Options", systemImage: "ellipsis.circle") {
                    Button("New Note", action: onNew) // ⌘N lives on the toolbar button
                    Divider()
                    SettingsButton()
                    Divider()
                    Button("Quit Popup Notes") { NSApplication.shared.terminate(nil) }
                }
                .labelStyle(.iconOnly)
                .help("Options")
            }
        }
        .confirmationDialog(pendingDelete?.prompt ?? "", isPresented: deletePresented,
                            titleVisibility: .visible, presenting: pendingDelete) { pending in
            Button("Delete", role: .destructive) {
                if let note = notes.first(where: { $0.id == pending.id }) { onDelete(note, pending.fromKeyboard) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    private var deletePresented: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    /// ⌫ / ⌦ while the list has focus (the editor handles its own).
    private func deleteSelected() {
        // A held key must not delete one note after another (each delete
        // moves the selection on). isARepeat is only valid on key events.
        if let event = NSApp.currentEvent, event.type == .keyDown, event.isARepeat { return }
        guard pendingDelete == nil, let id = selection,
              let note = notes.first(where: { $0.id == id }) else { return }
        requestDelete(note, fromKeyboard: true)
    }

    private func requestDelete(_ note: Note, fromKeyboard: Bool) {
        guard note.isAlive else { return }
        if note.isBlank {
            // Nothing to lose, so no question. A lone blank note just stays:
            // deleting it would only create another.
            if notes.count > 1 { onDelete(note, fromKeyboard) }
            return
        }
        let title = note.title
        let shown = title.count > 60 ? String(title.prefix(60)) + "…" : title
        pendingDelete = PendingDelete(id: note.id, prompt: "Delete “\(shown)”?", fromKeyboard: fromKeyboard)
    }
}

private struct PendingDelete: Identifiable {
    let id: UUID
    let prompt: String
    let fromKeyboard: Bool
}

/// One sidebar row. A separate view that holds only `note` lets SwiftUI skip
/// unchanged rows: typing re-renders just the edited row, not every row.
private struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: note.title)
                .lineLimit(1)
                .foregroundStyle(note.isBlank ? HierarchicalShapeStyle.secondary : .primary)
            // Re-evaluated every minute, so "5 min. ago" can't go stale while
            // the panel sits hidden. The string must be built in here:
            // Text(date, format:) would keep showing its cached result.
            TimelineView(.everyMinute) { _ in
                Text(verbatim: subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// One string, so when the column is narrow the preview truncates, not the date.
    private var subtitle: String {
        let date = note.modified.formatted(.relative(presentation: .named))
        let preview = note.preview
        return preview.isEmpty ? date : "\(date) · \(preview)"
    }
}
