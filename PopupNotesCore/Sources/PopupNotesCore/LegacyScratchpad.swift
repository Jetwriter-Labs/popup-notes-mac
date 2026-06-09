import Foundation

/// Reads the pre-SwiftData single scratchpad file for one-time migration.
public enum LegacyScratchpad {
    /// Returns the file's text, or nil if missing/unreadable/blank.
    public static func read(at url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    /// Default location of the legacy file.
    public static func defaultURL(fileManager: FileManager = .default) -> URL? {
        try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                             appropriateFor: nil, create: false)
            .appendingPathComponent("PopupNotes/scratchpad.md")
    }
}
