/// Pure selection rules for the notes list, kept out of the views so they
/// can be unit-tested.
public enum NoteSelection {
    /// The note to select after `removed` leaves `ids` (the list order): the
    /// one that slides into its row, else the one above it, else nil.
    public static func neighbor<ID: Equatable>(ofRemoving removed: ID, in ids: [ID]) -> ID? {
        guard let i = ids.firstIndex(of: removed) else { return nil }
        if ids.indices.contains(i + 1) { return ids[i + 1] }
        return i > 0 ? ids[i - 1] : nil
    }
}
