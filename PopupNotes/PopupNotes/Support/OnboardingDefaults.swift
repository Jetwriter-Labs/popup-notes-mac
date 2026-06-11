import Foundation

/// One-time onboarding flags in `UserDefaults`. Each retires a piece of
/// first-run UI; `defaults delete ai.jetwriter.popupnotes` resets them all.
/// Key strings are shared with `OnboardingStripView`'s `@AppStorage`.
enum OnboardingDefaults {
    static let didRunFirstLaunchOnboardingKey = "didRunFirstLaunchOnboarding"
    static let didUseHotkeyOnceKey = "didUseHotkeyOnce"
    static let didDismissHotkeyHintKey = "didDismissHotkeyHint"
    static let didPromptLaunchAtLoginKey = "didPromptLaunchAtLogin" // reused legacy key — upgraders keep their answer
    static let hotKeyRegisteredKey = "hotKeyRegistered"

    static var didRunFirstLaunchOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: didRunFirstLaunchOnboardingKey) }
        set { UserDefaults.standard.set(newValue, forKey: didRunFirstLaunchOnboardingKey) }
    }

    static var didUseHotkeyOnce: Bool {
        get { UserDefaults.standard.bool(forKey: didUseHotkeyOnceKey) }
        set { UserDefaults.standard.set(newValue, forKey: didUseHotkeyOnceKey) }
    }

    /// Whether the most recent `RegisterEventHotKey` attempt succeeded.
    /// Defaults to true so the strip never flashes the failure text before
    /// the first registration attempt has written a real value.
    static var hotKeyRegistered: Bool {
        get { UserDefaults.standard.object(forKey: hotKeyRegisteredKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: hotKeyRegisteredKey) }
    }
}
