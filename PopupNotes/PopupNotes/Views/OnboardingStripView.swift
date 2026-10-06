import SwiftUI
import PopupNotesCore

/// Helpers pinned under the notes UI: the first-run hotkey hint, which
/// retires itself after the first real hotkey use (or its X button); the
/// launch-at-login consent row — App Review 2.4.5(iii): explicit opt-in via
/// the Enable button, never a silent default; and, whenever the shortcut
/// couldn't be registered, a warning in the hint's place, since the panel
/// then has to be opened from the menu bar. Renders nothing once all are retired.
struct OnboardingStripView: View {
    @AppStorage(OnboardingDefaults.didUseHotkeyOnceKey) private var didUseHotkey = false
    @AppStorage(OnboardingDefaults.didDismissHotkeyHintKey) private var didDismissHint = false
    @AppStorage(OnboardingDefaults.didPromptLaunchAtLoginKey) private var didAnswerLogin = false
    // Observed, so the hint and warning follow a shortcut change at once.
    private var hotKey: HotKeyStatus { .shared }

    private var showFailure: Bool { !hotKey.isRegistered }
    private var showHotkeyHint: Bool { hotKey.isRegistered && !didUseHotkey && !didDismissHint }

    var body: some View {
        if showFailure || showHotkeyHint || !didAnswerLogin {
            VStack(spacing: 0) {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    if showFailure { failureRow } else if showHotkeyHint { hotkeyRow }
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
            Image(systemName: "keyboard").accessibilityHidden(true)
            Text("Press \(hotKey.combo.displayString) in any app to open Popup Notes")
            Spacer()
            Button { didDismissHint = true } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss shortcut hint")
                .help("Dismiss")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    /// No dismiss button: it goes away by itself once a working shortcut is set.
    private var failureRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle").accessibilityHidden(true)
            Text("\(hotKey.combo.displayString) is unavailable — another app may be using it")
            Spacer()
            SettingsButton()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .controlSize(.small)
    }

    private var loginRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "power").accessibilityHidden(true)
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
