import SwiftUI
import SwiftData
import PopupNotesCore

/// The notes master-detail: a sidebar list + the selected note's editor, hosted
/// in the floating panel. Owns selection (persisted across launches) and the
/// new/delete actions.
struct NotesView: View {
    var onEscape: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Query(sort: \Note.modified, order: .reverse) private var notes: [Note]
    @State private var selection: UUID?
    @AppStorage("lastSelectedNoteID") private var lastSelectedRaw = ""

    var body: some View {
        NavigationSplitView {
            NotesListView(notes: notes,
                          selection: $selection,
                          onNew: newNote,
                          onDelete: delete)
                .navigationSplitViewColumnWidth(min: 130, ideal: 200)
        } detail: {
            if let id = selection, let note = notes.first(where: { $0.id == id }) {
                NoteDetailView(note: note).id(id)
            } else {
                ContentUnavailableView("No Note Selected", systemImage: "note.text",
                                       description: Text("Select a note or create one."))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { OnboardingStripView() }
        .frame(minWidth: 360, minHeight: 220)
        .onAppear(perform: restoreSelection)
        .onChange(of: selection) { _, newValue in
            lastSelectedRaw = newValue?.uuidString ?? ""
        }
        .onExitCommand { onEscape() }
    }

    private func restoreSelection() {
        if notes.isEmpty { newNote(); return }
        guard selection == nil || !notes.contains(where: { $0.id == selection }) else { return }
        let remembered = UUID(uuidString: lastSelectedRaw).flatMap { id in
            notes.contains(where: { $0.id == id }) ? id : nil
        }
        selection = remembered ?? notes.first?.id
    }

    private func newNote() {
        let note = Note()
        context.insert(note)
        selection = note.id
    }

    private func delete(_ note: Note) {
        if selection == note.id { selection = nil }
        context.delete(note)
    }
}
