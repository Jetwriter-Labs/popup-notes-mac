import SwiftUI
import PopupNotesCore

/// The selected note: its title field above its text, and the outline beside
/// them once the text has headings. Editing the title or the text bumps
/// `modified` so the note re-sorts to the top of the sidebar; opening or
/// closing a toggle doesn't.
struct NoteDetailView: View {
    @Bindable var note: Note
    /// Changing it moves keyboard focus into the note — its title while the
    /// note is blank, else its text (see NotesView.newNote).
    var focusRequest = 0
    /// Whether the note takes keyboard focus when it appears (see NotesView).
    var takesFocus = true

    @AppStorage(NoteOutline.showsOutlineKey) private var showsOutline = true
    @State private var outline = NoteOutline()
    @State private var width: CGFloat = 0
    @FocusState private var titleIsFocused: Bool
    @State private var titleSelection: TextSelection?
    @State private var textFocus = NoteTextEditor.FocusRequest()

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                titleField
                NoteTextEditor(text: $note.text, onEdit: { note.modified = .now }, focusRequest: textFocus,
                               takesFocusOnAppear: takesFocus && !note.isBlank, outline: outline,
                               onExitAtTop: focusTitle)
            }
            // The detail column's 52pt top toolbar strip is empty (controls live in
            // the sidebar), so the title fills it, level with the sidebar's buttons.
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
        .onAppear {
            outline.update(headings: MarkdownOutline.headings(in: note.text))
            // A new note starts at its title; any other, at the end of its text.
            if takesFocus, note.isBlank { Task { focusTitle() } }
        }
        .onChange(of: focusRequest) {
            if note.isBlank {
                focusTitle()
            } else {
                textFocus = .init(id: textFocus.id + 1)
            }
        }
    }

    /// Plain text, bold and a size above a `#` heading in the text, wrapping
    /// onto a few lines when it's long. Return, ↓ and Tab go on into the
    /// text, as from a title in Notion.
    private var titleField: some View {
        TextField("Title", text: title, selection: $titleSelection, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.largeTitle.bold())
            .lineLimit(1...4)
            .focused($titleIsFocused)
            .onSubmit(focusTextAtStart)
            .onKeyPress(.downArrow) { focusTextAtStart(); return .handled }
            .onKeyPress(.tab) { focusTextAtStart(); return .handled }
            // Lines up with the text below (its inset plus line padding), and
            // a one-line title with the sidebar's toolbar buttons.
            .padding(.leading, 13)
            .padding(.trailing, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    /// Typing a title is an edit, and it stays on one line: a line break
    /// (⌥↩, or pasted) becomes a space.
    private var title: Binding<String> {
        Binding(get: { note.title }, set: { typed in
            let title = NoteTitle.singleLine(typed)
            guard title != note.title else { return }
            note.title = title
            note.modified = .now
        })
    }

    /// Focus to the title, the caret at its end — as ↑ or ⌫ from the text
    /// expect. A field selects all of its text as it takes focus, which the
    /// next keystroke would replace, so the caret moves once it has.
    private func focusTitle() {
        titleIsFocused = true
        DispatchQueue.main.async { titleSelection = TextSelection(insertionPoint: note.title.endIndex) }
    }

    private func focusTextAtStart() {
        textFocus = .init(id: textFocus.id + 1, atStart: true)
    }

    /// Below this, the outline would squeeze the note: it steps aside until
    /// the panel is widened again.
    private static let minWidthForOutline: CGFloat = 420

    private var outlineWidth: CGFloat { min(220, max(150, (width * 0.3).rounded())) }
}
