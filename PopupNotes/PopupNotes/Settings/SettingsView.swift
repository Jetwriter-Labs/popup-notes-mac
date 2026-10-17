import SwiftUI
import SwiftData
import AppKit
import Accessibility
import ServiceManagement
import UniformTypeIdentifiers
import PopupNotesCore

/// The Settings window: General (launch-at-login, global shortcut, JSON
/// export/import) and About (local-only promise, open source, JetWriter).
struct SettingsView: View {
    let container: ModelContainer
    let appDelegate: AppDelegate
    @State private var status: String?
    @State private var problem: Problem?

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { general }
            Tab("About", systemImage: "info.circle") { AboutView() }
        }
        .frame(width: 460)
        .alert(problem?.title ?? "", isPresented: problemPresented, presenting: problem) { _ in
            Button("OK") {}
        } message: { problem in
            Text(problem.message)
        }
    }

    private var general: some View {
        Form {
            Section {
                LaunchAtLoginRow()
                MenuBarIconRow()
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
        .frame(minHeight: 300)
        .onChange(of: status) { _, new in
            if let new { AccessibilityNotification.Announcement(new).post() }
        }
    }

    private var problemPresented: Binding<Bool> {
        Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })
    }

    private func exportNotes() {
        status = nil
        // A throwing fetch: on a damaged store, "no notes" must not be
        // written over the user's last good backup.
        let notes: [Note]
        let data: Data
        do {
            notes = try NotesRepository(context: container.mainContext).allNotes()
            data = try NotesJSON.encode(notes.map(ExportedNote.init))
        } catch {
            problem = Problem(title: "Export failed",
                              message: "Popup Notes couldn’t read your notes. \(error.localizedDescription)")
            return
        }
        let panel = NSSavePanel()
        let today = Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        panel.nameFieldStringValue = "Popup Notes Export \(today).json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Self.write(data, to: url)
            status = "Exported \(Self.count(notes.count))."
        } catch {
            problem = Problem(title: "Export failed", message: error.localizedDescription)
        }
    }

    /// Atomic, so a failed write can't destroy the backup it replaces. The
    /// sandbox may grant the chosen file but not its folder, which an atomic
    /// replace needs; only in that case write in place instead.
    private static func write(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch let error as CocoaError where error.code == .fileWriteNoPermission {
            try data.write(to: url)
        }
    }

    private func importNotes() {
        status = nil
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let incoming: [ExportedNote]
        do {
            let data = try Data(contentsOf: url)
            do {
                incoming = try NotesJSON.decode(data)
            } catch {
                problem = Problem(title: "Import failed",
                                  message: "“\(url.lastPathComponent)” isn’t a Popup Notes export file. Nothing was changed.")
                return
            }
        } catch {
            problem = Problem(title: "Import failed",
                              message: "Couldn’t read “\(url.lastPathComponent)”. \(error.localizedDescription)")
            return
        }
        let repo = NotesRepository(context: container.mainContext)
        let summary: ImportSummary
        do {
            summary = try repo.importNotes(incoming)
        } catch {
            problem = Problem(title: "Import failed",
                              message: "Popup Notes couldn’t read your existing notes, so nothing was imported. \(error.localizedDescription)")
            return
        }
        do {
            try repo.save()
        } catch {
            // No rollback: on the shared context it would also throw away
            // unsaved typing in the panel. The changes stay pending; autosave
            // and the next panel close retry.
            problem = Problem(title: "Imported, but not saved yet",
                              message: "Saving failed (\(error.localizedDescription)). Popup Notes will keep trying.")
            return
        }
        report(summary)
    }

    private func report(_ summary: ImportSummary) {
        var parts: [String] = []
        if summary.added > 0 { parts.append("\(Self.count(summary.added)) added") }
        if summary.updated > 0 { parts.append("\(Self.count(summary.updated)) updated") }
        if summary.unchanged > 0 { parts.append("\(Self.count(summary.unchanged)) already up to date") }
        if summary.keptNewer > 0 { parts.append("\(Self.count(summary.keptNewer)) kept (newer here)") }
        status = parts.isEmpty ? "The file had no notes." : "Imported: " + parts.joined(separator: ", ") + "."
        if summary.keptNewer > 0 {
            let n = summary.keptNewer
            problem = Problem(
                title: n == 1 ? "1 note was newer on this Mac" : "\(n) notes were newer on this Mac",
                message: """
                    \(n == 1 ? "It was" : "They were") changed on this Mac more recently than \
                    the copy in this file, so \(n == 1 ? "it was" : "they were") kept. To use the \
                    file’s version instead, delete \(n == 1 ? "that note" : "those notes") here \
                    and import again.
                    """)
        }
    }

    private static func count(_ n: Int) -> String { n == 1 ? "1 note" : "\(n) notes" }
}

private struct Problem {
    let title: String
    let message: String
}

/// Launch at Login, showing the real login-item state. It's re-read whenever
/// Settings comes forward, since it can change elsewhere (the onboarding
/// strip's Enable button, System Settings ▸ Login Items). Never enables on
/// its own: register() runs only from the user's click.
private struct LaunchAtLoginRow: View {
    @State private var status = LaunchAtLogin.status

    var body: some View {
        Toggle("Launch at Login", isOn: Binding(get: { status == .enabled }, set: { setEnabled($0) }))
            .onAppear(perform: refresh)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
                // Settings coming forward — not the notes panel or an open/save
                // panel, so the panel's show path never waits on this.
                guard let window = note.object as? NSWindow, !(window is NSPanel) else { return }
                refresh()
            }
        if status == .requiresApproval {
            LabeledContent("Turned off in System Settings") {
                Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
            }
            .font(.callout)
        }
    }

    private func refresh() { status = LaunchAtLogin.status }

    private func setEnabled(_ enabled: Bool) {
        // Switched off in Login Items, register() can't turn it back on —
        // only the user can, over there.
        if enabled && status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        } else {
            LaunchAtLogin.setEnabled(enabled)
        }
        refresh()
    }
}

/// Show in Menu Bar. Turns itself off when macOS takes the icon away (see
/// MenuBarIcon), and says how to reach the notes panel without it. On
/// macOS 26 the system's own switch can also keep the icon hidden — even
/// right after this is turned on — and no API reports that switch, so the
/// way to it is always offered.
private struct MenuBarIconRow: View {
    @AppStorage(MenuBarIcon.isShownKey) private var isShown = true
    private var hotKey: HotKeyStatus { .shared }

    var body: some View {
        Toggle("Show in Menu Bar", isOn: $isShown)
        if !isShown {
            Text(hotKey.isRegistered
                 ? "Open the notes panel with \(hotKey.combo.displayString) or from Spotlight; Settings and Quit are in its ⋯ menu."
                 : "Open the notes panel from Spotlight; Settings and Quit are in its ⋯ menu.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        if #available(macOS 26, *) {
            LabeledContent("System Settings must allow it too") {
                Button("Open Menu Bar Settings…") { NSWorkspace.shared.open(MenuBarIcon.systemSettingsURL) }
            }
            .font(.callout)
        }
    }
}

/// Who made this, what it does with your data (nothing), and where the code is.
private struct AboutView: View {
    private static let repoURL = URL(string: "https://github.com/Jetwriter-Labs/popup-notes-mac")!
    private static let jetwriterURL = URL(string: "https://jetwriter.ai")!

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
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
