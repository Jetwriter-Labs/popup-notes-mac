import Observation
import PopupNotesCore

/// This process's live global-hotkey state. Every view that shows the
/// shortcut (menu bar, onboarding strip, Settings) observes it, so they all
/// update the moment it changes. Deliberately in memory rather than in
/// UserDefaults: a second running copy (a dev build beside the installed
/// app) shares the defaults domain, and its failure must not mislabel this one.
@Observable
final class HotKeyStatus {
    static let shared = HotKeyStatus()

    /// The shortcut this process registered — or, after a failure, the one it
    /// tried to keep.
    var combo: HotKeyCombo = HotKeyStore.saved
    /// Whether `combo` is actually registered. Starts true so nothing flashes
    /// a failure before the first registration attempt at launch.
    var isRegistered = true

    private init() {}
}
