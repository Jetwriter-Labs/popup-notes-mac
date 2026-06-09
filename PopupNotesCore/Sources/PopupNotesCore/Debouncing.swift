import Foundation

/// Coalesces rapid calls into a single deferred action. `@MainActor` because
/// the fired action mutates `NoteStore` and touches the file system from the
/// store's isolation domain.
@MainActor
public protocol Debouncing {
    func schedule(_ action: @escaping @MainActor () -> Void)
    func cancel()
}

/// Production debouncer backed by a cancellable `Task` sleep.
@MainActor
public final class Debouncer: Debouncing {
    private let interval: Duration
    private var task: Task<Void, Never>?

    public init(interval: Duration) { self.interval = interval }

    public func schedule(_ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { [interval] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }
}

/// Test double: stores the latest scheduled action and fires it only when
/// `fireNow()` is called, making `NoteStore` save timing deterministic.
@MainActor
public final class ManualDebouncer: Debouncing {
    private var pending: (@MainActor () -> Void)?
    public init() {}

    public func schedule(_ action: @escaping @MainActor () -> Void) { pending = action }
    public func cancel() { pending = nil }

    public func fireNow() {
        let action = pending
        pending = nil
        action?()
    }
}
