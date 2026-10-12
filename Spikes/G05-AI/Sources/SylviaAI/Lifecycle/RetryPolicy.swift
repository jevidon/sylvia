import Foundation

/// Capped exponential backoff with Retry-After (plan 14.4). Only `ProviderError.isTransient` failures are
/// retried automatically, and only before any output was received.
public struct RetryPolicy: Sendable, Equatable {
    public var maxAttempts: Int
    public var initialDelay: Duration
    public var multiplier: Double
    public var maxDelay: Duration
    /// A Retry-After longer than this is not waited out automatically; the request becomes failed_retryable.
    public var maxRetryAfter: Duration
    /// Full jitter between half and all of the computed delay; `false` for deterministic tests.
    public var jitter: Bool

    public init(maxAttempts: Int = 3, initialDelay: Duration = .seconds(1), multiplier: Double = 2, maxDelay: Duration = .seconds(20),
                maxRetryAfter: Duration = .seconds(60), jitter: Bool = true) {
        self.maxAttempts = maxAttempts
        self.initialDelay = initialDelay
        self.multiplier = multiplier
        self.maxDelay = maxDelay
        self.maxRetryAfter = maxRetryAfter
        self.jitter = jitter
    }

    /// Delay before the attempt that follows attempt number `attempt` (1-based); nil means do not retry automatically.
    public func delay(afterAttempt attempt: Int, retryAfter: Duration?, random: Double = Double.random(in: 0...1)) -> Duration? {
        guard attempt < maxAttempts else { return nil }
        if let retryAfter {
            guard retryAfter <= maxRetryAfter else { return nil }
            return max(retryAfter, .zero)
        }
        let base = initialDelay * pow(multiplier, Double(attempt - 1))
        let capped = min(base, maxDelay)
        return jitter ? capped * (0.5 + 0.5 * min(max(random, 0), 1)) : capped
    }
}

public protocol Sleeper: Sendable {
    func sleep(for duration: Duration) async throws
}

public struct TaskSleeper: Sleeper {
    public init() {}
    public func sleep(for duration: Duration) async throws { try await Task.sleep(for: duration) }
}

public protocol AIClock: Sendable {
    func now() -> Date
}

public struct SystemClock: AIClock {
    public init() {}
    public func now() -> Date { Date() }
}

/// Whether the device currently has a usable network path. The coordinator never waits for connectivity and
/// never sends automatically when it returns (plan 14.4 default: manual send).
public protocol ConnectivityProbe: Sendable {
    var isOnline: Bool { get }
}
