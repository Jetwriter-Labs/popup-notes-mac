/// Why this process came up, as far as the launch Apple Event can tell.
///
/// The app has no Dock icon and no main window, so a launch that puts nothing
/// on screen looks to the user like nothing happened — that is what opening
/// "Popup Notes" from Spotlight or Raycast used to do. A launch the user asked
/// for should therefore show the panel; a launch the *system* performed must
/// stay silent and just take up its place in the menu bar.
public enum AppLaunchKind: Sendable, Equatable {
    /// A person opened the app: Finder, Dock, Spotlight, Raycast, `open -a`.
    case user
    /// The system started it in the background — a login item or a Services
    /// item. Putting UI on screen here would ambush the user at login.
    case system

    /// Carbon's `keyAELaunchedAsLogInItem`.
    public static let logInItemCode = fourCharCode("lgit")
    /// Carbon's `keyAELaunchedAsServiceItem`.
    public static let serviceItemCode = fourCharCode("svit")

    /// Classifies a `kAEOpenApplication` event from the codes it carries.
    ///
    /// `AERegistry.h` describes both markers the same way: present in the open
    /// event, the app "probably shouldn't open up untitled documents, etc."
    /// A marker can arrive either as a bare parameter keyword on the event or
    /// as the enum value of its `keyAEPropData` parameter, so both are checked
    /// — a plain user launch carries neither (on macOS 26.5 its event is an
    /// `'aevt'/'oapp'` with an empty parameter record).
    public static func classify(
        parameterKeywords: some Sequence<UInt32>,
        propertyDataCode: UInt32?
    ) -> AppLaunchKind {
        let systemMarkers: Set<UInt32> = [logInItemCode, serviceItemCode]
        if let propertyDataCode, systemMarkers.contains(propertyDataCode) { return .system }
        return parameterKeywords.contains(where: systemMarkers.contains) ? .system : .user
    }

    /// Whether a launch of this kind should put the notes panel on screen.
    public var shouldShowPanelOnLaunch: Bool { self == .user }

    /// Packs a four-character ASCII string into an `OSType`/`FourCharCode`,
    /// so the constants above read as the Carbon literals they mirror.
    static func fourCharCode(_ string: String) -> UInt32 {
        string.unicodeScalars.reduce(0) { ($0 << 8) | (UInt32($1.value) & 0xFF) }
    }
}
