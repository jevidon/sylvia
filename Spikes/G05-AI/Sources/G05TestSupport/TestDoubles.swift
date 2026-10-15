import Foundation
import Synchronization
import SylviaAI

// Test doubles for SylviaAI's injected dependencies. They live here, not in SylviaAI, so nothing that links only the
// library can use them (review R3-07): in particular, keys are held only by a Keychain-backed `CredentialStore` outside
// tests.

/// Holds credentials in memory, for host tests only (the data-protection Keychain needs an app host; see the
/// Keychain tests in ATSProbe).
public final class InMemoryCredentialStore: CredentialStore {
    private let items = Mutex<[CredentialRef: Secret]>([:])
    public init() {}

    public func save(_ secret: Secret, for ref: CredentialRef) throws(CredentialStoreError) {
        items.withLock { $0[ref] = secret }
    }

    public func secret(for ref: CredentialRef) throws(CredentialStoreError) -> Secret {
        guard let secret = items.withLock({ $0[ref] }) else { throw .notFound }
        return secret
    }

    public func delete(_ ref: CredentialRef) throws(CredentialStoreError) {
        _ = items.withLock { $0.removeValue(forKey: ref) }
    }
}

/// Records requested sleeps and returns immediately (deterministic tests).
public final class RecordingSleeper: Sleeper {
    private let storage = Mutex<[Duration]>([])
    public init() {}
    public func sleep(for duration: Duration) async throws {
        storage.withLock { $0.append(duration) }
        try Task.checkCancellation()
    }
    public var sleeps: [Duration] { storage.withLock { $0 } }
}

/// A clock tests advance by hand.
public final class ManualClock: AIClock {
    private let current: Mutex<Date>
    public init(_ start: Date = Date(timeIntervalSince1970: 1_791_590_400)) { current = Mutex(start) }
    public func now() -> Date { current.withLock { $0 } }
    public func advance(by seconds: TimeInterval) { current.withLock { $0 = $0.addingTimeInterval(seconds) } }
}

/// Connectivity a test sets by hand.
public final class FakeConnectivity: ConnectivityProbe {
    private let state: Mutex<Bool>
    public init(online: Bool) { state = Mutex(online) }
    public var isOnline: Bool { state.withLock { $0 } }
    public func set(online: Bool) { state.withLock { $0 = online } }
}

/// Keeps every diagnostic log event so tests can check what was logged (and that no secret or content was).
public final class CapturingLogSink: AILogSink {
    private let storage = Mutex<[AILogEvent]>([])
    public init() {}
    public func record(_ event: AILogEvent) { storage.withLock { $0.append(event) } }
    public var events: [AILogEvent] { storage.withLock { $0 } }
    public var renderedLines: [String] { events.map(\.rendered) }
}
