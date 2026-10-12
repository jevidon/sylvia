import Foundation

/// Request lifecycle states (plan 14.4).
public enum AskState: String, Codable, Sendable, CaseIterable {
    case draft
    case awaitingConsent = "awaiting_consent"
    case ready
    case sending
    case streaming
    case complete
    case cancelled
    case interrupted
    case failedRetryable = "failed_retryable"
    case failedFinal = "failed_final"

    public var isTerminal: Bool { [.complete, .cancelled, .interrupted, .failedRetryable, .failedFinal].contains(self) }
}

/// What a finished or stopped answer is, so a partial, refused or truncated response is never shown as a
/// completed answer (I-04).
public enum AnswerOutcome: String, Codable, Sendable {
    /// A normal end with answer text: the only outcome shown as "Complete".
    case answer
    case refusal
    case contentFiltered = "content_filtered"
    case outputLimit = "output_limit"
    case contextWindowExceeded = "context_window_exceeded"
    case toolCallRejected = "tool_call_rejected"
    case incomplete
    case partial
    /// The provider ended normally but sent no answer text (for example only reasoning, only a `<think>` block, or
    /// only `[DONE]`). Never complete: there is no answer to show.
    case noAnswerText = "no_answer_text"
}

public struct AttemptRecord: Codable, Sendable, Equatable {
    public var number: Int
    public var startedAt: Date
    public var endedAt: Date?
    public var failureKind: FailureKind?
    public var acceptance: Acceptance?
    public var httpStatus: Int?
    /// Partial text this attempt produced before a later attempt replaced it.
    public var supersededPartialText: String?

    enum CodingKeys: String, CodingKey {
        case number
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case failureKind = "failure_kind"
        case acceptance
        case httpStatus = "http_status"
        case supersededPartialText = "superseded_partial_text"
    }
}

public struct FailureSummary: Codable, Sendable, Equatable {
    public var kind: FailureKind
    public var acceptance: Acceptance
    public var userMessage: String
    public var retryAfterMs: Int?
    /// True when the generation may already have been accepted (and billed): resubmitting needs the user's say-so.
    public var resubmitNeedsConfirmation: Bool

    enum CodingKeys: String, CodingKey {
        case kind, acceptance
        case userMessage = "user_message"
        case retryAfterMs = "retry_after_ms"
        case resubmitNeedsConfirmation = "resubmit_needs_confirmation"
    }
}

/// One question and its answer. Persisted before sending and at every state change and checkpoint.
/// It holds the provider configuration (which has no secret) and the exact ContextPack.
public struct AskRecord: Codable, Sendable, Equatable {
    public var id: UUID
    public var conversationID: UUID
    public var question: String
    public var pack: ContextPack
    public var config: ProviderConfig
    public var state: AskState
    public var answerText: String
    public var refusalText: String
    public var outcome: AnswerOutcome?
    public var usage: TokenUsage?
    public var attempts: [AttemptRecord]
    public var failure: FailureSummary?
    public var queuedOffline: Bool
    public var reasoningOmitted: Bool
    public var toolCallRejected: Bool
    public var checkpointCount: Int
    public var createdAt: Date
    public var updatedAt: Date
    /// Label carried by any saved answer (plan 13.4: saved AI content keeps a model-generated label).
    public var generatedLabel: String { "Generated · \(pack.endpoint.host) · \(pack.endpoint.model)" }

    /// True when the answer holds visible text. Whitespace alone (for example what is left after a `<think>` block) is
    /// no answer.
    public var hasAnswerText: Bool { Self.isVisibleText(answerText) }

    static func isVisibleText(_ text: String) -> Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    enum CodingKeys: String, CodingKey {
        case id
        case conversationID = "conversation_id"
        case question, pack, config, state
        case answerText = "answer_text"
        case refusalText = "refusal_text"
        case outcome, usage, attempts, failure
        case queuedOffline = "queued_offline"
        case reasoningOmitted = "reasoning_omitted"
        case toolCallRejected = "tool_call_rejected"
        case checkpointCount = "checkpoint_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// The user-visible status, using the phrases fixed in plan 4.4.6 ("Asking a model").
    /// "Complete" is shown only for a normal end with answer text (I-04). A refusal or a content-filter stop with no
    /// answer text, and the failure states, have no phrase in that row; they show the classified, actionable reason
    /// instead (open question for the design package, recorded in the G0.5 report). Any stop after some answer text
    /// reads "Interrupted · partial answer", with the reason in `outcomeMessage`. A failed record always carries its
    /// classified failure; without one it reads "No answer", never "Draft · not sent", because a failed request may
    /// already have left the device.
    public var statusPhrase: String {
        switch state {
        case .draft, .awaitingConsent, .ready: return "Draft · not sent"
        case .sending: return "Sending to \(pack.endpoint.host)"
        case .streaming: return "Generated"
        case .complete: return outcome == .answer && hasAnswerText ? "Complete" : (outcomeMessage ?? failure?.userMessage ?? "No answer")
        case .interrupted: return "Interrupted · partial answer"
        // A cancelled request may already have left the device, so it never reads "Draft · not sent".
        case .cancelled: return hasAnswerText ? "Interrupted · partial answer" : (failure?.userMessage ?? "Cancelled")
        case .failedRetryable, .failedFinal: return failure?.userMessage ?? "No answer"
        }
    }

    /// Why the answer ended other than normally, shown with the status (the phrase alone for an interrupted answer
    /// says only that it is partial). Nil for a complete answer and for records that have not ended.
    public var outcomeMessage: String? {
        let host = pack.endpoint.host
        switch outcome {
        case nil, .answer?: return nil
        case .refusal?:
            if hasAnswerText { return "\(host) stopped partway and declined to continue. What arrived before that is kept as a partial answer." }
            // Only a refusal that came with text has a reply to show.
            return Self.isVisibleText(refusalText) ? "\(host) declined to answer this question. Its reply is shown apart from answers."
                                                   : "\(host) declined to answer this question and gave no reply to show."
        case .contentFiltered?:
            return hasAnswerText ? "\(host)'s content filter cut the answer off. What arrived before that is kept as a partial answer."
                                 : "\(host)'s content filter withheld the answer, so there is nothing to show."
        case .outputLimit?:
            return "The answer reached the maximum output for this endpoint and stopped. Raise the maximum output in provider settings for longer answers."
        case .contextWindowExceeded?:
            return "The answer stopped because the model's context window was full. Choose a narrower context and try again."
        case .incomplete?:
            return "\(host) stopped the answer before it finished."
        case .partial?:
            return failure?.userMessage
        case .toolCallRejected?, .noAnswerText?:
            return failure?.userMessage
        }
    }
}

/// Durable storage for ask records. The production store belongs to the persistence design (G0.5 recovery,
/// ADR on persistence); this spike uses one JSON file per record written atomically.
public protocol AskStore: Sendable {
    func save(_ record: AskRecord) async throws
    func load(_ id: UUID) async throws -> AskRecord?
    func all() async throws -> [AskRecord]
}

public actor FileAskStore: AskStore {
    public let directory: URL
    public private(set) var writeCount = 0

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func url(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }

    public func save(_ record: AskRecord) async throws {
        let data = try Self.encoder.encode(record)
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try data.write(to: url(record.id), options: options)
        writeCount += 1
    }

    public func load(_ id: UUID) async throws -> AskRecord? {
        guard FileManager.default.fileExists(atPath: url(id).path) else { return nil }
        return try Self.decoder.decode(AskRecord.self, from: Data(contentsOf: url(id)))
    }

    public func all() async throws -> [AskRecord] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try Self.decoder.decode(AskRecord.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    static var encoder: JSONEncoder { ContextPack.encoder() }
    static var decoder: JSONDecoder { ContextPack.decoder() }
}
