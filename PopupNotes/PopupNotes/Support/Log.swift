import Foundation
import os

/// Unified-logging channels (Console.app: subsystem `ai.jetwriter.popupnotes`).
/// Messages never include note text.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "ai.jetwriter.popupnotes"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let store = Logger(subsystem: subsystem, category: "store")
}
