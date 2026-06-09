import Testing
import Foundation
@testable import PopupNotesCore

@Suite struct LegacyScratchpadTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("legacy-\(UUID().uuidString).md")
    }
    @Test func missingFileReturnsNil() {
        #expect(LegacyScratchpad.read(at: tempURL()) == nil)
    }
    @Test func emptyFileReturnsNil() throws {
        let url = tempURL(); try "  \n\n".write(to: url, atomically: true, encoding: .utf8)
        #expect(LegacyScratchpad.read(at: url) == nil)
        try? FileManager.default.removeItem(at: url)
    }
    @Test func nonEmptyReturnsContents() throws {
        let url = tempURL(); try "old note\nline2".write(to: url, atomically: true, encoding: .utf8)
        #expect(LegacyScratchpad.read(at: url) == "old note\nline2")
        try? FileManager.default.removeItem(at: url)
    }
}
