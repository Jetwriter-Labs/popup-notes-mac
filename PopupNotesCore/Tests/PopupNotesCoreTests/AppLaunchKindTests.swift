import Testing
@testable import PopupNotesCore

@Suite struct AppLaunchKindTests {
    /// Finder / Spotlight / Raycast / `open -a`: a bare `oapp` with no
    /// parameters — the shape observed on macOS 26.5.
    @Test func bareOpenEventIsAUserLaunch() {
        #expect(AppLaunchKind.classify(parameterKeywords: [], propertyDataCode: nil) == .user)
    }

    @Test func logInItemKeywordIsASystemLaunch() {
        #expect(AppLaunchKind.classify(parameterKeywords: [AppLaunchKind.logInItemCode],
                                       propertyDataCode: nil) == .system)
    }

    @Test func serviceItemKeywordIsASystemLaunch() {
        #expect(AppLaunchKind.classify(parameterKeywords: [AppLaunchKind.serviceItemCode],
                                       propertyDataCode: nil) == .system)
    }

    /// The other encoding: the reason arrives as the enum value of the
    /// event's `keyAEPropData` parameter rather than as a bare keyword.
    @Test func logInItemAsPropertyDataIsASystemLaunch() {
        #expect(AppLaunchKind.classify(parameterKeywords: [],
                                       propertyDataCode: AppLaunchKind.logInItemCode) == .system)
    }

    @Test func serviceItemAsPropertyDataIsASystemLaunch() {
        #expect(AppLaunchKind.classify(parameterKeywords: [],
                                       propertyDataCode: AppLaunchKind.serviceItemCode) == .system)
    }

    /// Unrelated parameters must not be mistaken for a background launch.
    @Test func unrelatedParametersStayAUserLaunch() {
        let unrelated = AppLaunchKind.fourCharCode("xyzw")
        #expect(AppLaunchKind.classify(parameterKeywords: [unrelated],
                                       propertyDataCode: unrelated) == .user)
    }

    /// The codes must match the Carbon constants they stand in for:
    /// `keyAELaunchedAsLogInItem = 'lgit'`, `keyAELaunchedAsServiceItem = 'svit'`.
    @Test func codesMatchTheCarbonFourCharConstants() {
        #expect(AppLaunchKind.logInItemCode == 0x6C67_6974)   // 'lgit'
        #expect(AppLaunchKind.serviceItemCode == 0x7376_6974) // 'svit'
    }

    @Test func onlyAUserLaunchOpensThePanel() {
        #expect(AppLaunchKind.user.shouldShowPanelOnLaunch)
        #expect(!AppLaunchKind.system.shouldShowPanelOnLaunch)
    }
}
