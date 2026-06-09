import Foundation

/// Encodes/decodes the notes export file: a JSON array of `ExportedNote`,
/// pretty-printed with ISO-8601 dates.
public enum NotesJSON {
    public static func encode(_ notes: [ExportedNote]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(notes)
    }

    public static func decode(_ data: Data) throws -> [ExportedNote] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ExportedNote].self, from: data)
    }
}
