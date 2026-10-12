import Foundation

/// Lifecycle of one part of one asset version (plan 15.4, 15.5).
///
///     pending ──request──▶ requested(n) ──bodyReceived──▶ received(n) ──verified──▶ verified
///        ▲                    │                              │
///        │                    └──failed──▶ failed(n) ◀───────┘
///        │                                   │
///        └──────────── (request again: requested(n+1)) ◀──────┘
///
/// A verified part is never requested again for the same version. Only a version change whose new
/// manifest lists different bytes for this part (`invalidate`) returns it to pending.
public enum PartState: Equatable, Hashable, Sendable {
    case pending
    case requested(attempt: Int)
    case received(attempt: Int)
    case verified
    case failed(attempt: Int, failure: PartFailure)

    public var isVerified: Bool { self == .verified }
    public var attempts: Int {
        switch self {
        case .pending, .verified: 0
        case .requested(let n), .received(let n), .failed(let n, _): n
        }
    }
}

public enum PartEvent: Equatable, Sendable {
    case request
    case bodyReceived
    case verified
    case failed(PartFailure)
    case invalidate
}

public struct IllegalPartTransition: Error, Equatable, Sendable {
    public let from: PartState
    public let event: PartEvent
}

public struct PartStateMachine: Equatable, Sendable {
    public private(set) var state: PartState = .pending

    public init(state: PartState = .pending) { self.state = state }

    public mutating func apply(_ event: PartEvent) throws(IllegalPartTransition) {
        switch (state, event) {
        case (.pending, .request):
            state = .requested(attempt: 1)
        case (.failed(let attempt, _), .request):
            state = .requested(attempt: attempt + 1)
        case (.requested(let attempt), .bodyReceived):
            state = .received(attempt: attempt)
        case (.requested(let attempt), .failed(let failure)), (.received(let attempt), .failed(let failure)):
            state = .failed(attempt: attempt, failure: failure)
        case (.received, .verified):
            state = .verified
        case (_, .invalidate):
            state = .pending
        default:
            throw IllegalPartTransition(from: state, event: event)
        }
    }
}

/// Overall stage of a transfer job. "All parts received" is never shown as ready: the job is ready
/// only after the assembled file's full SHA-256 matches the manifest (plan 15.4).
public enum TransferStage: Equatable, Hashable, Sendable {
    case preparing
    case downloading
    case paused(PauseReason)
    case allPartsVerified
    case finalizing
    case readyForImport
}

/// Byte counters kept apart so the UI can say "3.1 of 5.2 GB verified" (plan 15.5).
public struct TransferProgress: Equatable, Hashable, Sendable {
    public var totalBytes: Int64
    public var receivedBytes: Int64
    public var verifiedBytes: Int64

    public init(totalBytes: Int64, receivedBytes: Int64 = 0, verifiedBytes: Int64 = 0) {
        self.totalBytes = totalBytes
        self.receivedBytes = receivedBytes
        self.verifiedBytes = verifiedBytes
    }

    public var isFullyVerified: Bool { verifiedBytes == totalBytes }
}
