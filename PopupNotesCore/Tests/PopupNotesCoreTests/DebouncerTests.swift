import Testing
import Foundation
@testable import PopupNotesCore

@Suite @MainActor struct DebouncerTests {
    @Test func manualDebouncerKeepsOnlyLatestAndFiresOnDemand() {
        let d = ManualDebouncer()
        var fired: [Int] = []
        d.schedule { fired.append(1) }
        d.schedule { fired.append(2) } // replaces the first
        #expect(fired.isEmpty)         // nothing fires until we say so
        d.fireNow()
        #expect(fired == [2])
    }

    @Test func manualDebouncerCancelDropsPendingAction() {
        let d = ManualDebouncer()
        var fired = false
        d.schedule { fired = true }
        d.cancel()
        d.fireNow()
        #expect(!fired)
    }

    @Test func realDebouncerFiresOnceAfterInterval() async {
        let d = Debouncer(interval: .milliseconds(20))
        await confirmation("fires exactly once") { fulfilled in
            d.schedule { fulfilled() }
            d.schedule { fulfilled() } // coalesced into one
            try? await Task.sleep(for: .milliseconds(120))
        }
    }
}
