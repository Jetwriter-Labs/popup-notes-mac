import SwiftUI
import AppKit
import Accessibility
import PopupNotesCore

/// Click-to-record control for the global shortcut. While recording, a local
/// key monitor captures the next keystroke typed in this window; Esc cancels.
/// Combos must include ⌘ or ⌃ (Option-only combos are broken with
/// `RegisterEventHotKey` on macOS 15+, see `HotKeyCombo.isValidGlobalHotKey`),
/// and ⌘ alone is refused because it would take that shortcut from every app.
struct HotKeyRecorderView: View {
    /// Applies the combo (re-registering the Carbon hotkey); false = rejected.
    let apply: (HotKeyCombo) -> Bool

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var feedback: String?
    private var hotKey: HotKeyStatus { .shared }

    private var message: String? {
        feedback ?? (hotKey.isRegistered ? nil
            : "This shortcut isn't active — another app may be using it. Record a different one.")
    }

    var body: some View {
        LabeledContent("Open notes") {
            HStack(spacing: 8) {
                Button(isRecording ? "Type new shortcut (⎋ cancels)" : hotKey.combo.displayString) {
                    isRecording ? stopRecording() : startRecording()
                }
                if hotKey.combo != .default && !isRecording {
                    Button("Reset to \(HotKeyCombo.default.displayString)") {
                        commit(.default)
                    }
                }
            }
        }
        // Whatever takes the keyboard away from Settings ends the recording:
        // closing the window, another tab, the hotkey showing the notes panel.
        .onDisappear(perform: stopRecording)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            if isRecording { stopRecording() }
        }
        .onChange(of: feedback) { _, new in
            if let new { AccessibilityNotification.Announcement(new).post() }
        }
        if let message {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func startRecording() {
        feedback = nil
        isRecording = true
        // A local monitor sees keystrokes for EVERY window of the app, the
        // notes panel included. Only keys typed in the recorder's own window
        // (key, since its button was just clicked) are a recording; anything
        // else ends the recording and goes through untouched — otherwise
        // typing in a note would vanish, and ⌘V there would become the
        // system-wide hotkey. A nil window never matches.
        let recorderWindow = NSApp.keyWindow
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak recorderWindow] event in
            guard let recorderWindow, event.window === recorderWindow else {
                stopRecording()
                return event
            }
            handle(event)
            return nil // swallow keystrokes while recording
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        isRecording = false
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 { feedback = nil; stopRecording(); return } // Esc cancels
        let candidate = HotKeyCombo(keyCode: UInt32(event.keyCode),
                                    modifiers: KeyModifiers(event.modifierFlags))
        guard !candidate.usesCommandAlone else {
            feedback = "\(candidate.displayString) would stop working in every other app. Add ⌃, ⌥ or ⇧."
            return
        }
        guard candidate.isValidGlobalHotKey else {
            feedback = "Include ⌘ or ⌃ in the shortcut."
            return
        }
        stopRecording()
        commit(candidate)
    }

    private func commit(_ candidate: HotKeyCombo) {
        if apply(candidate) {
            feedback = nil
        } else {
            feedback = "That shortcut couldn't be registered — it may be taken. Try another."
        }
    }
}

private extension KeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option)  { insert(.option) }
        if flags.contains(.shift)   { insert(.shift) }
    }
}
