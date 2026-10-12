import Foundation

/// A provider-neutral text generation request (plan 14.1).
public struct GenerationRequest: Sendable, Equatable {
    public struct Message: Sendable, Equatable {
        public enum Role: String, Sendable { case user, assistant }
        public var role: Role
        public var text: String
        public init(role: Role, text: String) {
            self.role = role
            self.text = text
        }
    }

    public var system: String
    public var messages: [Message]
    public var maxOutputTokens: Int

    public init(system: String, messages: [Message], maxOutputTokens: Int) {
        self.system = system
        self.messages = messages
        self.maxOutputTokens = maxOutputTokens
    }
}

public struct TokenUsage: Codable, Sendable, Equatable {
    public var inputTokens: Int?
    public var outputTokens: Int?

    public init(inputTokens: Int? = nil, outputTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

/// Why a stream ended, normalized across dialects.
public enum FinishReason: Sendable, Equatable, Codable {
    /// Natural end (stop, end_turn, stop_sequence, response.completed).
    case complete
    /// Output token limit reached: the answer is truncated and is never shown as complete (I-04).
    case outputLimit
    /// The model declined (refusal stop reason or refusal content).
    case refused
    /// Output withheld by a provider content filter.
    case contentFiltered
    /// The model asked to call a tool. Sylvia sends no tools and never executes one (plan 13.4, 14.4).
    case toolCallRejected
    /// The response filled the model's context window.
    case contextWindowExceeded
    /// Any other provider-reported incomplete state, with the provider's reason.
    case incomplete(String)
}

public enum GenerationStatus: Sendable, Equatable {
    /// The provider acknowledged the request (response or message id when supplied).
    case accepted(responseID: String?, model: String?)
    /// Provider-internal reasoning was received and discarded; it is never saved as the answer.
    case reasoningOmitted
    /// A tool call was received and rejected without parsing or executing its arguments.
    case toolCallRejected(name: String?)
    /// A chat stream ended with [DONE] but no finish_reason (some compatible servers omit it).
    case finishReasonMissing
    /// How the provider delivered the answer: as an event stream, or as one JSON body (a compatible server
    /// without streaming, or one that ignored `stream: true`). Emitted once, before any text.
    case delivery(streamed: Bool)
}

/// The provider-neutral stream event (plan 14.1: text, status and usage events).
public enum GenerationEvent: Sendable, Equatable {
    case status(GenerationStatus)
    case text(String)
    case refusal(String)
    case usage(TokenUsage)
    case finished(FinishReason)
}
