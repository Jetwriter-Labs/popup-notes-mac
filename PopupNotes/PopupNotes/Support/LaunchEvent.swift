import AppKit
import Carbon.HIToolbox
import PopupNotesCore

extension AppLaunchKind {
    /// The reason for this launch, read from the `kAEOpenApplication` event
    /// AppKit is dispatching underneath `applicationDidFinishLaunching`.
    ///
    /// Only valid from inside that callback — `currentAppleEvent` is non-nil
    /// just while the event is being handled, and is still nil in
    /// `applicationWillFinishLaunching`. Even a bare `exec` or an Xcode Run
    /// gets a synthesized, parameterless `oapp`, so those count as user
    /// launches; if there is no open event at all, stay quiet and treat it
    /// as a system launch.
    static var current: AppLaunchKind {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication) else { return .system }
        var keywords: Set<UInt32> = []
        if event.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem)) != nil {
            keywords.insert(logInItemCode)
        }
        if event.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsServiceItem)) != nil {
            keywords.insert(serviceItemCode)
        }
        let propertyData = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
        return classify(parameterKeywords: keywords, propertyDataCode: propertyData)
    }
}
