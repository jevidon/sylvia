import Foundation

/// A user's cancel request, observable two ways:
/// - polled (`isCancelled`), as `StreamingCopier` does between chunks once bytes are moving;
/// - pushed (`onCancel`), for waits that poll nothing: a share provider that has not delivered its file yet (an iCloud
///   download, a mail attachment being fetched) or a coordinated read that is waiting for another writer. Without the
///   push, Cancel did nothing until the provider delivered or stalled for 60 s (G0.3 review finding R2-01).
public final class CancellationSignal: @unchecked Sendable {
    /// Identifies one `onCancel` handler so a finished wait can remove it.
    public struct Registration: Hashable, Sendable {
        fileprivate let token: UInt64
    }

    private let lock = NSLock()
    private var cancelled = false
    private var nextToken: UInt64 = 0
    private var handlers: [UInt64: @Sendable () -> Void] = [:]

    public init() {}

    public var isCancelled: Bool { lock.withLock { cancelled } }

    /// Marks the signal cancelled and runs every registered handler once, outside the lock. Later calls do nothing.
    public func cancel() {
        let pending: [@Sendable () -> Void] = lock.withLock {
            guard !cancelled else { return [] }
            cancelled = true
            defer { handlers.removeAll() }
            return handlers.keys.sorted().compactMap { handlers[$0] }
        }
        for handler in pending { handler() }
    }

    /// Runs `handler` once when the signal is cancelled: immediately (on the caller's thread) if it already is,
    /// otherwise on the thread that calls `cancel()`. Remove the registration when the wait it guards is over.
    @discardableResult
    public func onCancel(_ handler: @escaping @Sendable () -> Void) -> Registration {
        let registration: Registration? = lock.withLock {
            guard !cancelled else { return nil }
            nextToken += 1
            handlers[nextToken] = handler
            return Registration(token: nextToken)
        }
        guard let registration else {
            handler()
            return Registration(token: 0)
        }
        return registration
    }

    public func remove(_ registration: Registration) {
        _ = lock.withLock { handlers.removeValue(forKey: registration.token) }
    }
}
