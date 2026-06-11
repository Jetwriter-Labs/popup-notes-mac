import SwiftUI
import AppKit
import PopupNotesCore

/// Click-to-record control for the global shortcut. While recording, a local
/// key monitor captures the next keystroke; Esc cancels. Combos must include
/// ⌘ or ⌃ (Option-only combos are broken with `RegisterEventHotKey` on
/// macOS 15+, see `HotKeyCombo.isValidGlobalHotKey`).
struct HotKeyRecorderView: View {
    /// Applies the combo (re-registering the Carbon hotkey); false = rejected.
    let apply: (HotKeyCombo) -> Bool

    @State private var combo: HotKeyCombo = HotKeyStore.saved
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var feedback: String?

    var body: some View {
        LabeledContent("Open notes") {
            HStack(spacing: 8) {
                Button(isRecording ? "Type new shortcut (⎋ cancels)" : combo.displayString) {
                    isRecording ? stopRecording() : startRecording()
                }
                if combo != .default && !isRecording {
                    Button("Reset to \(HotKeyCombo.default.displayString)") {
                        commit(.default)
                    }
                }
            }
        }
        if let feedback {
            Text(feedback)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func startRecording() {
        feedback = nil
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil // swallow keystrokes while recording
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        isRecording = false
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 { stopRecording(); return } // Esc cancels
        let candidate = HotKeyCombo(keyCode: UInt32(event.keyCode),
                                    modifiers: KeyModifiers(event.modifierFlags))
        guard candidate.isValidGlobalHotKey else {
            feedback = "Include ⌘ or ⌃ in the shortcut."
            return
        }
        stopRecording()
        commit(candidate)
    }

    private func commit(_ candidate: HotKeyCombo) {
        if apply(candidate) {
            combo = candidate
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
