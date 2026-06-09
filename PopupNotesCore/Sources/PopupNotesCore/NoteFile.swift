import Foundation

/// Reads and writes the single scratchpad file. Pure Foundation — no app deps.
public struct NoteFile: Sendable, Equatable {
    public let url: URL
    public init(url: URL) { self.url = url }

    /// `~/Library/Application Support/PopupNotes/scratchpad.md`.
    public static func defaultFile(fileManager: FileManager = .default) throws -> NoteFile {
        let base = try fileManager.url(for: .applicationSupportDirectory,
                                       in: .userDomainMask,
                                       appropriateFor: nil,
                                       create: true)
        let dir = base.appendingPathComponent("PopupNotes", isDirectory: true)
        return NoteFile(url: dir.appendingPathComponent("scratchpad.md", isDirectory: false))
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func read() throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// Atomic write: Foundation writes to a temp file and renames, so a crash
    /// mid-write cannot corrupt the note. Creates the parent directory first.
    public func write(_ text: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
