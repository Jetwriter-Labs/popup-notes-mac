import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers
import PopupNotesCore

/// The Settings window: launch-at-login plus JSON export/import.
struct SettingsView: View {
    let container: ModelContainer
    @State private var status: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: Binding(
                    get: { LaunchAtLogin.isEnabled },
                    set: { LaunchAtLogin.isEnabled = $0 }
                ))
            }
            Section("Data") {
                LabeledContent("Export all notes") {
                    Button("Export…") { exportNotes() }
                }
                LabeledContent("Import notes") {
                    Button("Import…") { importNotes() }
                }
                if let status {
                    Text(status).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 240)
    }

    private func exportNotes() {
        let exported = NotesRepository(context: container.mainContext)
            .allSortedByModified()
            .map(ExportedNote.init)
        guard let data = try? NotesJSON.encode(exported) else { status = "Export failed."; return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "PopupNotes-export.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
            status = "Exported \(exported.count) note(s)."
        } catch {
            status = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importNotes() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        guard let incoming = try? NotesJSON.decode(data) else {
            status = "Import failed: not a valid notes file."
            return
        }
        let repo = NotesRepository(context: container.mainContext)
        incoming.forEach { repo.upsert($0) }
        repo.save()
        status = "Imported \(incoming.count) note(s)."
    }
}
