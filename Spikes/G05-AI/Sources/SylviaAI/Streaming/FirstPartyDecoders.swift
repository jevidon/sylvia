import Foundation

// MARK: - OpenAI Responses API

/// Decoder for `POST /v1/responses` streams. Events are typed by `data.type` (the SSE `event:` line repeats it).
/// Only `response.output_text.delta` becomes answer text; `response.refusal.delta` is refusal text; reasoning
/// items and reasoning text/summary events are discarded; function and hosted-tool calls are rejected.
/// The stream ends at `response.completed`, `response.incomplete` or `response.failed`; there is no `[DONE]`.
public struct OpenAIResponsesDecoder: StreamDecoder {
    let host: String
    let redactor: Redactor
    var sawRefusal = false
    var sawTool = false
    var reportedReasoning = false
    public private(set) var hasTerminated = false

    public init(host: String, redactor: Redactor) {
        self.host = host
        self.redactor = redactor
    }

    public mutating func decode(_ event: SSEEvent) throws(ProviderError) -> [GenerationEvent] {
        guard !hasTerminated else { return [] }
        guard let object = JSON.object(event.data) else { throw .malformed(host, "responses event is not a JSON object") }
        guard let type = object["type"] as? String else { throw .malformed(host, "responses event has no type") }
        switch type {
        case "response.created", "response.in_progress", "response.queued":
            guard type == "response.created", let response = object["response"] as? [String: Any] else { return [] }
            return [.status(.accepted(responseID: response["id"] as? String, model: response["model"] as? String))]
        case "response.output_text.delta":
            guard let delta = object["delta"] as? String else { throw .malformed(host, "output_text.delta without delta") }
            return delta.isEmpty ? [] : [.text(delta)]
        case "response.refusal.delta":
            guard let delta = object["delta"] as? String else { throw .malformed(host, "refusal.delta without delta") }
            sawRefusal = true
            return delta.isEmpty ? [] : [.refusal(delta)]
        case "response.output_item.added":
            let item = object["item"] as? [String: Any]
            let itemType = item?["type"] as? String ?? ""
            if itemType == "reasoning" { return reasoningOnce() }
            if itemType == "message" { return [] }
            // function_call, custom_tool_call, web_search_call, file_search_call, mcp_call, …: never executed.
            if !sawTool {
                sawTool = true
                return [.status(.toolCallRejected(name: (item?["name"] as? String) ?? itemType))]
            }
            return []
        case _ where type.hasPrefix("response.reasoning"):
            return reasoningOnce()
        case "response.completed":
            hasTerminated = true
            var out = usageEvents(object)
            out.append(.finished(sawTool ? .toolCallRejected : sawRefusal ? .refused : .complete))
            return out
        case "response.incomplete":
            hasTerminated = true
            let response = object["response"] as? [String: Any]
            let reason = (response?["incomplete_details"] as? [String: Any])?["reason"] as? String ?? "unknown"
            var out = usageEvents(object)
            switch reason {
            case "max_output_tokens": out.append(.finished(.outputLimit))
            case "content_filter": out.append(.finished(.contentFiltered))
            default: out.append(.finished(.incomplete(reason)))
            }
            return out
        case "response.failed":
            hasTerminated = true
            let error = (object["response"] as? [String: Any])?["error"] as? [String: Any]
            throw ProviderError(kind: .providerStreamError, acceptance: .uncertain, host: host,
                                providerCode: (error?["code"] as? String).map(redactor.scrub),
                                detail: (error?["message"] as? String).map(redactor.scrub))
        case "error":
            hasTerminated = true
            throw ProviderError(kind: .providerStreamError, acceptance: .uncertain, host: host,
                                providerCode: (object["code"] as? String).map(redactor.scrub),
                                detail: (object["message"] as? String).map(redactor.scrub))
        default:
            // Unknown and irrelevant events (content_part.*, output_text.done, annotations, tool argument deltas)
            // carry nothing Sylvia shows; the versioning policy allows new types.
            return []
        }
    }

    mutating func reasoningOnce() -> [GenerationEvent] {
        guard !reportedReasoning else { return [] }
        reportedReasoning = true
        return [.status(.reasoningOmitted)]
    }

    func usageEvents(_ object: [String: Any]) -> [GenerationEvent] {
        guard let usage = (object["response"] as? [String: Any])?["usage"] as? [String: Any] else { return [] }
        return [.usage(TokenUsage(inputTokens: usage["input_tokens"] as? Int, outputTokens: usage["output_tokens"] as? Int))]
    }

    public mutating func finish() throws(ProviderError) -> [GenerationEvent] {
        guard hasTerminated else { throw .endedEarly(host) }
        return []
    }
}

// MARK: - Anthropic Messages API

/// Decoder for `POST /v1/messages` streams: message_start, content_block_start/delta/stop, message_delta,
/// message_stop, ping and error. Text deltas are accepted only for blocks opened as `text`; thinking,
/// redacted_thinking and signature content is never emitted; tool_use and server tool blocks are rejected.
public struct AnthropicMessagesDecoder: StreamDecoder {
    enum BlockKind { case text, reasoning, tool, other }
    let host: String
    let redactor: Redactor
    var blocks: [Int: BlockKind] = [:]
    var stopReason: FinishReason?
    var inputTokens: Int?
    var reportedReasoning = false
    var reportedTool = false
    public private(set) var hasTerminated = false

    public init(host: String, redactor: Redactor) {
        self.host = host
        self.redactor = redactor
    }

    public mutating func decode(_ event: SSEEvent) throws(ProviderError) -> [GenerationEvent] {
        guard !hasTerminated else { return [] }
        guard let object = JSON.object(event.data) else { throw .malformed(host, "messages event is not a JSON object") }
        guard let type = object["type"] as? String else { throw .malformed(host, "messages event has no type") }
        switch type {
        case "message_start":
            let message = object["message"] as? [String: Any]
            inputTokens = (message?["usage"] as? [String: Any])?["input_tokens"] as? Int
            return [.status(.accepted(responseID: message?["id"] as? String, model: message?["model"] as? String))]
        case "content_block_start":
            guard let index = object["index"] as? Int, let block = object["content_block"] as? [String: Any],
                  let blockType = block["type"] as? String else { throw .malformed(host, "content_block_start without index or block") }
            switch blockType {
            case "text":
                blocks[index] = .text
                let initial = block["text"] as? String ?? ""
                return initial.isEmpty ? [] : [.text(initial)]
            case "thinking", "redacted_thinking":
                blocks[index] = .reasoning
                guard !reportedReasoning else { return [] }
                reportedReasoning = true
                return [.status(.reasoningOmitted)]
            case "tool_use", "server_tool_use", "mcp_tool_use":
                blocks[index] = .tool
                guard !reportedTool else { return [] }
                reportedTool = true
                return [.status(.toolCallRejected(name: block["name"] as? String))]
            default:
                blocks[index] = .other
                return []
            }
        case "content_block_delta":
            guard let index = object["index"] as? Int, let delta = object["delta"] as? [String: Any],
                  let deltaType = delta["type"] as? String else { throw .malformed(host, "content_block_delta without index or delta") }
            guard deltaType == "text_delta" else { return [] }  // thinking, signature, input_json, citations
            guard blocks[index] == .text else {
                throw .malformed(host, "text delta for a block that was not opened as text")
            }
            guard let text = delta["text"] as? String else { throw .malformed(host, "text_delta without text") }
            return text.isEmpty ? [] : [.text(text)]
        case "content_block_stop":
            return []
        case "message_delta":
            var out: [GenerationEvent] = []
            if let reason = (object["delta"] as? [String: Any])?["stop_reason"] as? String {
                stopReason = Self.map(reason)
            }
            if let usage = object["usage"] as? [String: Any], let output = usage["output_tokens"] as? Int {
                out.append(.usage(TokenUsage(inputTokens: (usage["input_tokens"] as? Int) ?? inputTokens, outputTokens: output)))
            }
            return out
        case "message_stop":
            hasTerminated = true
            var reason = stopReason ?? .incomplete("no stop_reason")
            if reportedTool { reason = .toolCallRejected }
            return [.finished(reason)]
        case "ping":
            return []
        case "error":
            hasTerminated = true
            let error = object["error"] as? [String: Any]
            let code = (error?["type"] as? String).map(redactor.scrub)
            // overloaded_error mid-stream is the in-stream form of HTTP 529. The generation was already accepted,
            // so it is not replayed automatically.
            throw ProviderError(kind: .providerStreamError, acceptance: .uncertain, host: host,
                                providerCode: code, detail: (error?["message"] as? String).map(redactor.scrub))
        default:
            return []
        }
    }

    public mutating func finish() throws(ProviderError) -> [GenerationEvent] {
        guard hasTerminated else { throw .endedEarly(host) }
        return []
    }

    static func map(_ reason: String) -> FinishReason {
        switch reason {
        case "end_turn", "stop_sequence": .complete
        case "max_tokens": .outputLimit
        case "tool_use": .toolCallRejected
        case "refusal": .refused
        case "model_context_window_exceeded": .contextWindowExceeded
        default: .incomplete(reason)
        }
    }
}
