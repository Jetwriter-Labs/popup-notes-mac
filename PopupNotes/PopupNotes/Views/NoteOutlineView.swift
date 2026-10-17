import SwiftUI
import PopupNotesCore

/// The open note's headings, beside the editor, where they stay put while
/// the note scrolls. The section being read or edited is highlighted, and a
/// click jumps the editor to that heading.
struct NoteOutlineView: View {
    let outline: NoteOutline
    var onHide: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Outline")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Hide Outline", systemImage: "sidebar.trailing", action: onHide)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Hide Outline (⌃⌘O)")
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.vertical, 6)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        // Rows are identified by position: headings have no
                        // identity of their own, and offsets shift as you type.
                        ForEach(Array(outline.headings.enumerated()), id: \.offset) { index, heading in
                            OutlineRow(heading: heading, isCurrent: index == outline.current) {
                                outline.reveal(index)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.never)
                .onChange(of: outline.current) { _, current in
                    guard let current else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { proxy.scrollTo(current) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Outline")
    }
}

private struct OutlineRow: View {
    let heading: MarkdownHeading
    let isCurrent: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(verbatim: heading.title)
                .font(heading.depth == 0 ? .callout.weight(.medium) : .callout)
                .foregroundStyle(isCurrent ? .primary : .secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6 + CGFloat(min(heading.depth, 4)) * 12)
                .padding(.trailing, 6)
                .padding(.vertical, 3)
                .background(background, in: .rect(cornerRadius: 5))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(heading.title)
        .accessibilityValue("Heading level \(heading.level)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private var background: AnyShapeStyle {
        if isCurrent { return AnyShapeStyle(Color.accentColor.opacity(0.18)) }
        return isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear)
    }
}
