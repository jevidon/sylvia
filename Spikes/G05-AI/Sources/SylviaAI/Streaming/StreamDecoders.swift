import Foundation

/// Turns one dialect's SSE events into provider-neutral `GenerationEvent`s.
public protocol StreamDecoder: Sendable {
    mutating func decode(_ event: SSEEvent) throws(ProviderError) -> [GenerationEvent]
    /// Called at end of input. Throws `connectionLost` (acceptance uncertain) if the provider's final event never arrived.
    mutating func finish() throws(ProviderError) -> [GenerationEvent]
    var hasTerminated: Bool { get }
}

enum JSON {
    static func object(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

extension ProviderError {
    static func malformed(_ host: String, _ detail: String) -> ProviderError {
        ProviderError(kind: .invalidResponse, acceptance: .uncertain, host: host, detail: detail)
    }

    static func endedEarly(_ host: String) -> ProviderError {
        ProviderError(kind: .connectionLost, acceptance: .uncertain, host: host,
                      detail: "stream ended before the provider's final event")
    }
}

// MARK: - Generic OpenAI-compatible /chat/completions

/// Decoder for `chat.completion.chunk` streams terminated by `data: [DONE]`.
/// Only `choices[0].delta.content` becomes answer text. `delta.refusal` is surfaced as refusal text.
/// `reasoning_content` / `reasoning` fields (used by several local servers) and a leading `<think>…</think>`
/// block are discarded as provider-internal reasoning. Tool or function calls are rejected, never executed.
public struct ChatCompletionsDecoder: StreamDecoder {
    let host: String
    let redactor: Redactor
    var thinkFilter = ThinkTagFilter()
    var finishReason: FinishReason?
    var reportedReasoning = false
    var reportedTool = false
    var accepted = false
    public private(set) var hasTerminated = false

    public init(host: String, redactor: Redactor) {
        self.host = host
        self.redactor = redactor
    }

    public mutating func decode(_ event: SSEEvent) throws(ProviderError) -> [GenerationEvent] {
        guard !hasTerminated else { return [] }
        let data = event.data.trimmingCharacters(in: .whitespaces)
        if data == "[DONE]" {
            hasTerminated = true
            var out = flushThink()
            if finishReason == nil { out.append(.status(.finishReasonMissing)) }
            out.append(.finished(resolvedFinish))
            return out
        }
        guard let object = JSON.object(data) else { throw .malformed(host, "chat stream chunk is not a JSON object") }
        return try decodeObject(object, streaming: true)
    }

    /// Decodes a whole non-streaming `chat.completion` body (for endpoints without streaming).
    public mutating func decodeNonStreaming(_ body: Data) throws(ProviderError) -> [GenerationEvent] {
        guard let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            throw .malformed(host, "chat completion body is not a JSON object")
        }
        var out = try decodeObject(object, streaming: false)
        out += flushThink()
        hasTerminated = true
        if finishReason == nil { out.append(.status(.finishReasonMissing)) }
        out.append(.finished(resolvedFinish))
        return out
    }

    mutating func decodeObject(_ object: [String: Any], streaming: Bool) throws(ProviderError) -> [GenerationEvent] {
        if let error = object["error"] {
            let body = ProviderErrorBody.parse((try? JSONSerialization.data(withJSONObject: ["error": error])) ?? Data())
            hasTerminated = true
            throw ProviderError(kind: .providerStreamError, acceptance: .uncertain, host: host,
                                providerCode: body.code.map(redactor.scrub), detail: body.message.map(redactor.scrub))
        }
        var out: [GenerationEvent] = []
        if !accepted {
            accepted = true
            out.append(.status(.accepted(responseID: object["id"] as? String, model: object["model"] as? String)))
        }
        if let usage = object["usage"] as? [String: Any] {
            out.append(.usage(TokenUsage(inputTokens: usage["prompt_tokens"] as? Int, outputTokens: usage["completion_tokens"] as? Int)))
        }
        guard let choices = object["choices"] as? [[String: Any]] else {
            if object["usage"] != nil { return out }  // final usage-only chunk
            throw .malformed(host, "chat chunk has no choices array")
        }
        guard let choice = choices.first(where: { ($0["index"] as? Int ?? 0) == 0 }) else { return out }
        guard let message = (streaming ? choice["delta"] : choice["message"]) as? [String: Any] else {
            if let reason = choice["finish_reason"] as? String { finishReason = Self.map(reason) }
            return out
        }
        if message["reasoning_content"] is String || message["reasoning"] is String || message["reasoning"] is [String: Any] {
            if !reportedReasoning { reportedReasoning = true; out.append(.status(.reasoningOmitted)) }
        }
        let toolCalls = message["tool_calls"] as? [[String: Any]]
        if (toolCalls?.isEmpty == false) || message["function_call"] is [String: Any] {
            if !reportedTool {
                reportedTool = true
                let function = (toolCalls?.first?["function"] as? [String: Any]) ?? (message["function_call"] as? [String: Any])
                out.append(.status(.toolCallRejected(name: function?["name"] as? String)))
            }
        }
        if let content = message["content"] as? String, !content.isEmpty {
            let (visible, sawThink) = thinkFilter.consume(content)
            if sawThink && !reportedReasoning { reportedReasoning = true; out.append(.status(.reasoningOmitted)) }
            if !visible.isEmpty { out.append(.text(visible)) }
        }
        if let refusal = message["refusal"] as? String, !refusal.isEmpty {
            out.append(.refusal(refusal))
            finishReason = finishReason ?? .refused
        }
        if let reason = choice["finish_reason"] as? String {
            let mapped = Self.map(reason)
            // A refusal seen in content outranks a plain "stop".
            if !(finishReason == .refused && mapped == .complete) { finishReason = mapped }
            if reportedTool { finishReason = .toolCallRejected }
        }
        return out
    }

    /// The finish reason to report. A missing finish_reason is tolerated (some servers omit it) and read as complete,
    /// but once the model emitted a tool or function call the answer is never complete, whatever finish_reason says or
    /// in whichever chunk the call arrived (I-04): it ends as a rejected tool call.
    var resolvedFinish: FinishReason { reportedTool ? .toolCallRejected : (finishReason ?? .complete) }

    mutating func flushThink() -> [GenerationEvent] {
        let rest = thinkFilter.finish()
        return rest.isEmpty ? [] : [.text(rest)]
    }

    public mutating func finish() throws(ProviderError) -> [GenerationEvent] {
        guard !hasTerminated else { return [] }
        // Some servers close without [DONE] after a finish_reason; that is a complete stream.
        if finishReason != nil {
            hasTerminated = true
            return flushThink() + [.finished(resolvedFinish)]
        }
        throw .endedEarly(host)
    }

    static func map(_ reason: String) -> FinishReason {
        switch reason {
        case "stop": .complete
        case "length": .outputLimit
        case "tool_calls", "function_call": .toolCallRejected
        case "content_filter": .contentFiltered
        default: .incomplete(reason)
        }
    }
}

