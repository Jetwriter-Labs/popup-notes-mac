import SwiftUI
import PopupNotesCore

/// The editor for the selected note, with its outline beside it once the
/// note has headings. Editing the text bumps `modified` so the note
/// re-sorts to the top of the sidebar.
struct NoteDetailView: View {
    @Bindable var note: Note
    /// Changing it moves keyboard focus into the editor (see NotesView.newNote).
    var focusRequest = 0
    /// Whether the editor takes keyboard focus when it appears (see NotesView).
    var takesFocus = true

    @AppStorage(NoteOutline.showsOutlineKey) private var showsOutline = true
    @State private var outline = NoteOutline()
    @State private var width: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            NoteTextEditor(text: Binding(
                get: { note.text },
                set: { note.text = $0; note.modified = .now }
            ), focusRequest: focusRequest, takesFocusOnAppear: takesFocus, outline: outline)
            // The detail column's 52pt top toolbar strip is empty (controls live in
            // the sidebar), so let the editor fill it and start the text at the top.
            // Top only — the bottom safe area carries the onboarding strip (see NotesView).
            .ignoresSafeArea(.container, edges: .top)

            if showsOutline, outline.isWorthShowing, width >= Self.minWidthForOutline {
                Divider()
                NoteOutlineView(outline: outline) { showsOutline = false }
                    .frame(width: outlineWidth)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // The editor keeps the outline current, a beat after each change;
        // seeded here so a note with headings opens with its outline in
        // place rather than reflowing into it.
        .onAppear { outline.update(headings: MarkdownOutline.headings(in: note.text)) }
    }

    /// Below this, the outline would squeeze the note: it steps aside until
    /// the panel is widened again.
    private static let minWidthForOutline: CGFloat = 420

    private var outlineWidth: CGFloat { min(220, max(150, (width * 0.3).rounded())) }
}
