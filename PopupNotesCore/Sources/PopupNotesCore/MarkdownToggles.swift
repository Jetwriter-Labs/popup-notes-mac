import Foundation

/// Notion-style toggles: a `▾ Title` line — `▸` while closed — that folds
/// away the lines indented under it. Whether a toggle is open is part of the
/// text, so it survives relaunches and export; opening or closing one swaps
/// that one character. `MarkdownBlocks` works out which lines each toggle
/// holds (`toggleDepth`) and which are folded away (`isHidden`).
public enum MarkdownToggles {
    /// The lines toggle `index` holds: the run right after it that is
    /// inside it. Empty for a toggle with nothing under it yet.
    public static func body(of index: Int, in lines: [MarkdownLine]) -> Range<Int> {
        let depth = lines[index].toggleDepth
        var end = index + 1
        while end < lines.count, lines[end].toggleDepth > depth { end += 1 }
        return (index + 1)..<end
    }

    /// The innermost toggle that line `index` is inside, if any.
    public static func parent(of index: Int, in lines: [MarkdownLine]) -> Int? {
        let depth = lines[index].toggleDepth
        guard depth > 0 else { return nil }
        var parent = index - 1
        while parent >= 0, lines[parent].toggleDepth >= depth { parent -= 1 }
        return parent >= 0 ? parent : nil
    }

    /// The toggle that ⌘↩ opens or closes with the caret at `location`: the
    /// one on the caret's line, or else the innermost one around it.
    public static func toggle(around location: Int, in lines: [MarkdownLine]) -> Int? {
        guard let index = MarkdownBlocks.lineIndex(containing: location, in: lines) else { return nil }
        return lines[index].isToggle ? index : parent(of: index, in: lines)
    }

    /// Opens or closes toggle `index`: the edit that swaps its marker, or nil
    /// when it already is.
    public static func fold(_ index: Int, open: Bool, in lines: [MarkdownLine]) -> MarkdownEdit? {
        guard case .toggle(let isOpen) = lines[index].block, isOpen != open,
              let marker = lines[index].marker else { return nil }
        return MarkdownEdit(range: marker, replacement: ToggleMarker.string(open: open), selection: nil)
    }

    /// Opens the closed toggles around line `index`, so that it shows.
    public static func reveal(_ index: Int, in lines: [MarkdownLine]) -> [MarkdownEdit] {
        var edits: [MarkdownEdit] = []
        // A hidden line in no toggle is the empty last line, which shows
        // with the line above it.
        var line = index > 0 && lines[index].isHidden && lines[index].toggleDepth == 0 ? index - 1 : index
        while let parent = parent(of: line, in: lines) {
            if let edit = fold(parent, open: true, in: lines) { edits.append(edit) }
            line = parent
        }
        return edits
    }

    /// Opens every toggle if any is closed, and otherwise closes them all.
    public static func foldAll(in lines: [MarkdownLine]) -> [MarkdownEdit] {
        let toggles = lines.indices.filter { lines[$0].isToggle }
        let open = toggles.contains { lines[$0].block == .toggle(isOpen: false) }
        return toggles.compactMap { fold($0, open: open, in: lines) }
    }

    /// Where a caret headed for `location` can go when closed toggles hide
    /// that line: just past the folded lines when moving `forward` and there
    /// are lines after them, else to the end of the line above them — the
    /// title of the toggle that folds them away. `location` itself when its
    /// line shows.
    public static func visibleLocation(_ location: Int, forward: Bool, in lines: [MarkdownLine]) -> Int {
        guard let index = MarkdownBlocks.lineIndex(containing: location, in: lines),
              lines[index].isHidden else { return location }
        var above = index
        while above > 0, lines[above].isHidden { above -= 1 }
        var below = index
        while below < lines.count, lines[below].isHidden { below += 1 }
        return forward && below < lines.count ? lines[below].range.location : NSMaxRange(lines[above].range)
    }
}
