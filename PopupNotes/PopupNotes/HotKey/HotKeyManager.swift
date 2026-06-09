import AppKit
import Carbon.HIToolbox
import PopupNotesCore

/// Wraps Carbon `RegisterEventHotKey`. The C event callback cannot capture
/// Swift context, so we pass `self` via an `Unmanaged` pointer and hop back to
/// the main actor to invoke the stored closure.
@MainActor
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onFire: (() -> Void)?

    /// Returns false if the combo is invalid or registration fails.
    @discardableResult
    func register(_ combo: HotKeyCombo, onFire: @escaping () -> Void) -> Bool {
        guard combo.isValidGlobalHotKey else { return false }
        // Verify our mirrored constants equal Carbon's real values.
        assert(KeyModifiers.command.rawValue == UInt32(cmdKey))
        assert(KeyModifiers.control.rawValue == UInt32(controlKey))
        assert(KeyModifiers.option.rawValue == UInt32(optionKey))
        assert(KeyModifiers.shift.rawValue == UInt32(shiftKey))

        self.onFire = onFire

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData -> OSStatus in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { manager.fire() } }
            return noErr
        }
        let status = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec,
                                         Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        guard status == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: OSType(0x504E_4F54), id: 1) // 'PNOT'
        let regStatus = RegisterEventHotKey(combo.keyCode, combo.carbonModifierFlags,
                                            hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        return regStatus == noErr
    }

    private func fire() { onFire?() }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef); self.hotKeyRef = nil }
        if let handlerRef { RemoveEventHandler(handlerRef); self.handlerRef = nil }
    }
}
