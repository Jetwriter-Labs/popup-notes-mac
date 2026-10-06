import Foundation

/// One-time onboarding flags in `UserDefaults`. Each retires a piece of
/// first-run UI; `defaults delete ai.jetwriter.popupnotes` resets them all.
/// Key strings are shared with `OnboardingStripView`'s `@AppStorage`.
/// (Whether the hotkey is registered is per-process state: `HotKeyStatus`.)
enum OnboardingDefaults {
    static let didRunFirstLaunchOnboardingKey = "didRunFirstLaunchOnboarding"
    static let didUseHotkeyOnceKey = "didUseHotkeyOnce"
    static let didDismissHotkeyHintKey = "didDismissHotkeyHint"
    static let didPromptLaunchAtLoginKey = "didPromptLaunchAtLogin" // reused legacy key — upgraders keep their answer
    /// Set by pre-consent builds (before cc4294f) that enabled launch-at-login unasked.
    static let legacyFirstRunDefaultsKey = "didApplyFirstRunDefaults"

    static var didRunFirstLaunchOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: didRunFirstLaunchOnboardingKey) }
        set { UserDefaults.standard.set(newValue, forKey: didRunFirstLaunchOnboardingKey) }
    }

    static var didUseHotkeyOnce: Bool {
        get { UserDefaults.standard.bool(forKey: didUseHotkeyOnceKey) }
        set { UserDefaults.standard.set(newValue, forKey: didUseHotkeyOnceKey) }
    }
}
