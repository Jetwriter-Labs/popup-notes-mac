import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers
import PopupNotesCore

/// The Settings window: General (launch-at-login, global shortcut, JSON
/// export/import) and About (local-only promise, open source, JetWriter).
struct SettingsView: View {
    let container: ModelContainer
    let appDelegate: AppDelegate
    @State private var status: String?

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { general }
            Tab("About", systemImage: "info.circle") { AboutView() }
        }
        .frame(width: 460)
    }

    private var general: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: Binding(
                    get: { LaunchAtLogin.isEnabled },
                    set: { LaunchAtLogin.isEnabled = $0 }
                ))
            }
            Section("Shortcut") {
                HotKeyRecorderView { appDelegate.applyHotKey($0) }
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
        .frame(height: 300)
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

/// Who made this, what it does with your data (nothing), and where the code is.
private struct AboutView: View {
    private static let repoURL = URL(string: "https://github.com/GorvGoyl/popup-notes-mac")!
    private static let jetwriterURL = URL(string: "https://jetwriter.ai")!

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text("Popup Notes").font(.title2.bold())
            Text("Version \(version)").font(.callout).foregroundStyle(.secondary)

            Text("""
                Fully local: your notes live in a database on this Mac and \
                never leave it. No analytics, no tracking, no account.
                """)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            HStack(spacing: 16) {
                Link("Open source — GitHub", destination: Self.repoURL)
                Link("Made by JetWriter", destination: Self.jetwriterURL)
            }

            Text("© 2026 Gourav Goyal · MIT License")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(height: 300)
    }
}
