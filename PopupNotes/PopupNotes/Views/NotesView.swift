import SwiftUI
import SwiftData
import PopupNotesCore

/// The notes master-detail: a sidebar list + the selected note's editor, hosted
/// in the floating panel. Owns selection (persisted across launches) and every
/// change to it: new, delete, and discarding notes left blank.
struct NotesView: View {
    var onEscape: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Query(sort: \Note.modified, order: .reverse) private var notes: [Note]
    @State private var selection: UUID?
    /// Bumped to move the caret into the title when ⌘N keeps the open blank note.
    @State private var focusRequest = 0
    /// The note selected by a delete made with ⌫ in the sidebar: its editor
    /// must not take focus, so the next ⌫ goes on acting on the list (a
    /// held key is ignored there) instead of erasing that note's text.
    @State private var listKeepsFocusFor: UUID?
    /// A note left by deselecting (a click in empty sidebar space) — still
    /// discarded if blank, once another note is selected.
    @State private var leftViaDeselect: UUID?
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
                NoteDetailView(note: note, focusRequest: focusRequest,
                               takesFocus: listKeepsFocusFor != id).id(id)
            } else {
                ContentUnavailableView {
                    Label(notes.isEmpty ? "No Notes" : "No Note Selected", systemImage: "note.text")
                } description: {
                    Text(notes.isEmpty ? "Create a note to get started." : "Select a note or create one.")
                } actions: {
                    Button("New Note", action: newNote)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { OnboardingStripView() }
        .frame(minWidth: 360, minHeight: 220)
        .onAppear(perform: restoreSelection)
        .onChange(of: selection) { old, new in
            lastSelectedRaw = new?.uuidString ?? ""
            if new != listKeepsFocusFor { listKeepsFocusFor = nil }
            // Only once another note is selected — never down to zero notes.
            if new == nil {
                leftViaDeselect = old ?? leftViaDeselect
            } else {
                if let left = old ?? leftViaDeselect { discardIfBlank(left) }
                leftViaDeselect = nil
            }
        }
        .onExitCommand { onEscape() }
    }

    private func restoreSelection() {
        if notes.isEmpty { insertNote(); return }
        guard selection == nil || !notes.contains(where: { $0.id == selection }) else { return }
        let remembered = UUID(uuidString: lastSelectedRaw).flatMap { id in
            notes.contains(where: { $0.id == id }) ? id : nil
        }
        selection = remembered ?? notes.first?.id
    }

    /// Always a fresh note, selected — its title takes focus.
    private func insertNote() {
        let note = Note()
        context.insert(note)
        selection = note.id
    }

    /// ⌘N, the toolbar, the ⋯ menu, the empty state. If the open note is
    /// still blank, stay in it rather than stack another empty note.
    private func newNote() {
        if let id = selection, let current = notes.first(where: { $0.id == id }),
           current.isAlive, current.isBlank {
            focusRequest += 1
        } else {
            insertNote()
        }
    }

    private func delete(_ note: Note, fromKeyboard: Bool) {
        guard note.isAlive else { return }
        // Move selection off the note BEFORE deleting it, in the same update,
        // so no editor is ever bound to a deleted model.
        if selection == note.id {
            let next = NoteSelection.neighbor(ofRemoving: note.id, in: notes.map(\.id))
            if fromKeyboard { listKeepsFocusFor = next }
            selection = next
        }
        let wasLast = notes.allSatisfy { $0.id == note.id }
        context.delete(note)
        if wasLast { insertNote() } // never leave the panel with nothing to type into
    }

    /// Apple Notes behavior: a note left blank disappears once you move to
    /// another note. Deferred a turn, so the old editor is torn down (and an
    /// input method has committed) first; looked up afresh, so a note that
    /// was deleted meanwhile is simply not found.
    private func discardIfBlank(_ id: UUID) {
        Task { @MainActor in
            guard selection != id,
                  let note = NotesRepository(context: context).note(id: id),
                  note.isAlive, note.isBlank else { return }
            context.delete(note)
        }
    }
}
