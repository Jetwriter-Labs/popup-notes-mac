import SwiftUI
import PopupNotesCore

/// One-time first-run helpers pinned under the notes UI: a hotkey hint that
/// retires itself after the first real hotkey use (or its X button), and the
/// launch-at-login consent row — App Review 2.4.5(iii): explicit opt-in via
/// the Enable button, never a silent default. Renders nothing once both rows
/// have retired.
struct OnboardingStripView: View {
    @AppStorage(OnboardingDefaults.didUseHotkeyOnceKey) private var didUseHotkey = false
    @AppStorage(OnboardingDefaults.didDismissHotkeyHintKey) private var didDismissHint = false
    @AppStorage(OnboardingDefaults.didPromptLaunchAtLoginKey) private var didAnswerLogin = false
    @AppStorage(OnboardingDefaults.hotKeyRegisteredKey) private var hotKeyRegistered = true
    // Same defaults key HotKeyStore writes, so the hint live-updates when the
    // user records a new shortcut in Settings.
    @AppStorage("hotKeyCombo") private var comboData = Data()

    private var showHotkeyHint: Bool { !didUseHotkey && !didDismissHint }

    private var comboDisplay: String {
        ((try? JSONDecoder().decode(HotKeyCombo.self, from: comboData)) ?? .default).displayString
    }

    var body: some View {
        if showHotkeyHint || !didAnswerLogin {
            VStack(spacing: 0) {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    if showHotkeyHint { hotkeyRow }
                    if !didAnswerLogin { loginRow }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(.bar)
        }
    }

    private var hotkeyRow: some View {
        HStack(spacing: 6) {
            Image(systemName: hotKeyRegistered ? "keyboard" : "exclamationmark.triangle")
            Text(hotKeyRegistered
                 ? "Press \(comboDisplay) in any app to open Popup Notes"
                 : "Your shortcut is unavailable — set a new one in Settings (⌘,)")
            Spacer()
            Button { didDismissHint = true } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss shortcut hint")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var loginRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "power")
            Text("Start at login so your shortcut is ready after a restart")
            Spacer()
            Button("Enable") {
                LaunchAtLogin.isEnabled = true
                didAnswerLogin = true
            }
            Button("Not Now") { didAnswerLogin = true }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .controlSize(.small)
    }
}
