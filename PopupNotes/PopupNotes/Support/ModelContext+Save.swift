import SwiftData
import os

extension ModelContext {
    /// Saves pending changes for the background save points (panel hide,
    /// quit, seeding), where there is no one to show an error to: a failure
    /// is logged, and the changes stay pending for autosave to retry.
    func saveLoggingErrors(_ moment: StaticString) {
        guard hasChanges else { return }
        do {
            try save()
        } catch {
            Log.store.error("Save failed (\(moment, privacy: .public)): \(String(reflecting: error), privacy: .public)")
        }
    }
}
