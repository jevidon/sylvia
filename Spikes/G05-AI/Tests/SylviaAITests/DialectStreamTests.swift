import Foundation
import Testing
@testable import SylviaAI

/// Brief items 1-2: per-dialect stream decoding through the same path the provider uses
/// (`HTTPTextGenerationProvider.decodeStream`), with byte-level chunk splitting.
struct DecodeOutcome {
    var events: [GenerationEvent] = []
    var error: ProviderError?

    var text: String { events.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined() }
    var refusal: String { events.compactMap { if case .refusal(let t) = $0 { t } else { nil } }.joined() }
    var finish: FinishReason? { events.compactMap { if case .finished(let r) = $0 { r } else { nil } }.last }
    var statuses: [GenerationStatus] { events.compactMap { if case .status(let s) = $0 { s } else { nil } } }
    var usage: TokenUsage? { events.compactMap { if case .usage(let u) = $0 { u } else { nil } }.last }
}

enum StreamHarness {
    static func chunks(_ bytes: [UInt8], every size: Int) -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream { continuation in
            var index = 0
            while index < bytes.count {
                let end = min(index + size, bytes.count)
                continuation.yield(Data(bytes[index..<end]))
                index = end
            }
            continuation.finish()
        }
    }

    static func decode(_ kind: ProviderKind, _ raw: String, chunkSize: Int = 7) async -> DecodeOutcome {
        var outcome = DecodeOutcome()
        do {
            try await HTTPTextGenerationProvider.decodeStream(chunks(Array(raw.utf8), every: chunkSize), kind: kind, host: "fake.test",
                                                              redactor: Redactor()) { outcome.events.append($0) }
        } catch let error as ProviderError {
            outcome.error = error
        } catch {
            Issue.record("unexpected error type \(error)")
        }
        return outcome
    }

    /// Decodes with every chunk size from 1 to 64 and checks text and finish are identical (split UTF-8, partial events).
    static func decodeAllSplits(_ kind: ProviderKind, _ raw: String, sourceLocation: SourceLocation = #_sourceLocation) async -> DecodeOutcome {
        let reference = await decode(kind, raw, chunkSize: Array(raw.utf8).count)
        for size in 1...64 {
            let outcome = await decode(kind, raw, chunkSize: size)
            #expect(outcome.text == reference.text, "chunk size \(size) changed the text", sourceLocation: sourceLocation)
            #expect(outcome.finish == reference.finish, "chunk size \(size) changed the finish", sourceLocation: sourceLocation)
            #expect(outcome.error == reference.error, "chunk size \(size) changed the error", sourceLocation: sourceLocation)
        }
        return reference
    }
}

@Suite("Generic OpenAI-compatible chat stream")
struct ChatCompletionsStreamTests {
    static func chunk(_ delta: String, finish: String? = nil) -> String {
        let finishJSON = finish.map { "\"\($0)\"" } ?? "null"
        return "data: {\"id\":\"chatcmpl-1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"local-model\",\"choices\":[{\"index\":0,\"delta\":\(delta),\"finish_reason\":\(finishJSON)}]}\n\n"
    }

    @Test func normalStreamWithSplitUTF8AndCRLF() async {
        let raw = (Self.chunk(#"{"role":"assistant","content":""}"#) + Self.chunk(#"{"content":"Café — "}"#)
            + Self.chunk(#"{"content":"😀 ok [c1]"}"#) + Self.chunk("{}", finish: "stop") + "data: [DONE]\n\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
        let outcome = await StreamHarness.decodeAllSplits(.openAICompatibleChat, raw)
        #expect(outcome.error == nil)
        #expect(outcome.text == "Café — 😀 ok [c1]")
        #expect(outcome.finish == .complete)
        #expect(outcome.statuses.contains(.accepted(responseID: "chatcmpl-1", model: "local-model")))
    }

    @Test func commentsAndKeepalivesBetweenChunksAreIgnored() async {
        let raw = ": keepalive\n\n" + Self.chunk(#"{"content":"a"}"#) + ":\n\n: ping\n\n" + Self.chunk(#"{"content":"b"}"#, finish: "stop") + "data: [DONE]\n\n"
        let outcome = await StreamHarness.decodeAllSplits(.openAICompatibleChat, raw)
        #expect(outcome.text == "ab")
        #expect(outcome.finish == .complete)
    }

    @Test func reasoningFieldsAreNeverAnswerText() async {
        let raw = Self.chunk(#"{"reasoning_content":"SECRET-REASONING the user wants"}"#) + Self.chunk(#"{"reasoning":"MORE-REASONING"}"#)
            + Self.chunk(#"{"content":"The answer."}"#, finish: "stop") + "data: [DONE]\n\n"
        let outcome = await StreamHarness.decodeAllSplits(.openAICompatibleChat, raw)
        #expect(outcome.text == "The answer.")
        #expect(!outcome.text.contains("REASONING"))
        #expect(outcome.statuses.contains(.reasoningOmitted))
    }

    @Test func leadingThinkBlockIsStrippedEvenWhenTagsAreSplit() async {
        let raw = Self.chunk(#"{"content":"  <thi"}"#) + Self.chunk(#"{"content":"nk>SECRET plan</th"}"#)
            + Self.chunk(#"{"content":"ink>\n\nFinal answer <b>kept</b>."}"#, finish: "stop") + "data: [DONE]\n\n"
        let outcome = await StreamHarness.decodeAllSplits(.openAICompatibleChat, raw)
        #expect(outcome.text == "Final answer <b>kept</b>.")
        #expect(outcome.statuses.contains(.reasoningOmitted))
    }

    @Test func thinkTagLaterInTheAnswerIsLeftAlone() async {
        let raw = Self.chunk(#"{"content":"Use <think> literally."}"#, finish: "stop") + "data: [DONE]\n\n"
        let outcome = await StreamHarness.decode(.openAICompatibleChat, raw)
        #expect(outcome.text == "Use <think> literally.")
    }

    @Test func toolCallIsRejectedAndArgumentsNeverSurface() async {
        let raw = Self.chunk(#"{"content":"Let me look that up."}"#)
            + Self.chunk(#"{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"delete_library","arguments":""}}]}"#)
            + Self.chunk(#"{"tool_calls":[{"index":0,"function":{"arguments":"{\"confirm\":true}"}}]}"#)
            + Self.chunk("{}", finish: "tool_calls") + "data: [DONE]\n\n"
        let outcome = await StreamHarness.decodeAllSplits(.openAICompatibleChat, raw)
        #expect(outcome.text == "Let me look that up.")
        #expect(outcome.statuses.contains(.toolCallRejected(name: "delete_library")))
        #expect(outcome.finish == .toolCallRejected)
        #expect(!outcome.text.contains("confirm"))
    }

    /// I-04: a server that omits finish_reason is tolerated, but a tool call is never reported as a complete answer,
    /// whether the stream ends with [DONE], a bare close, a contradictory "stop", or as a single JSON body.
    @Test func toolCallWithoutAToolFinishReasonIsNeverComplete() async throws {
        let call = Self.chunk(#"{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"fetch_url","arguments":"{}"}}]}"#)
        let streams = [
            ("[DONE] with no finish_reason", call + "data: [DONE]\n\n"),
            ("finish_reason stop after the call", call + Self.chunk("{}", finish: "stop") + "data: [DONE]\n\n"),
            ("close after finish_reason stop", call + Self.chunk("{}", finish: "stop")),
            ("finish_reason in a chunk without a delta", call + #"data: {"choices":[{"index":0,"finish_reason":"stop"}]}"# + "\n\ndata: [DONE]\n\n"),
        ]
        for (label, raw) in streams {
            let outcome = await StreamHarness.decodeAllSplits(.openAICompatibleChat, raw)
            #expect(outcome.finish == .toolCallRejected, "\(label)")
            #expect(outcome.statuses.contains(.toolCallRejected(name: "fetch_url")), "\(label)")
        }
        var decoder = ChatCompletionsDecoder(host: "fake.test", redactor: Redactor())
        let body = #"{"choices":[{"index":0,"message":{"role":"assistant","content":null,"tool_calls":[{"id":"c","type":"function","function":{"name":"fetch_url","arguments":"{}"}}]}}]}"#
        let events = try decoder.decodeNonStreaming(Data(body.utf8))
        #expect(events.last == .finished(.toolCallRejected), "single JSON body without finish_reason")
        // And without a tool call a missing finish_reason still reads as complete, flagged.
        let plain = await StreamHarness.decodeAllSplits(.openAICompatibleChat, Self.chunk(#"{"content":"Fine."}"#) + "data: [DONE]\n\n")
        #expect(plain.finish == .complete)
        #expect(plain.statuses.contains(.finishReasonMissing))
    }

    @Test func refusalIsSurfacedSeparately() async {
        let raw = Self.chunk(#"{"refusal":"I can't help with that."}"#) + Self.chunk("{}", finish: "stop") + "data: [DONE]\n\n"
        let outcome = await StreamHarness.decodeAllSplits(.openAICompatibleChat, raw)
        #expect(outcome.text.isEmpty)
        #expect(outcome.refusal == "I can't help with that.")
        #expect(outcome.finish == .refused)
    }

    @Test func malformedJSONIsAnInvalidResponseWithUncertainAcceptance() async {
        let raw = Self.chunk(#"{"content":"partial"}"#) + "data: {\"choices\":[{\"delta\":{\"content\":\"x\"}\n\n"
        let outcome = await StreamHarness.decodeAllSplits(.openAICompatibleChat, raw)
        #expect(outcome.text == "partial")
        #expect(outcome.error?.kind == .invalidResponse)
        #expect(outcome.error?.acceptance == .uncertain)
    }

    @Test func errorObjectMidStreamIsAProviderError() async {
        let raw = Self.chunk(#"{"content":"partial"}"#) + "data: {\"error\":{\"message\":\"model crashed\",\"type\":\"server_error\",\"code\":\"oom\"}}\n\n"
        let outcome = await StreamHarness.decodeAllSplits(.openAICompatibleChat, raw)
        #expect(outcome.text == "partial")
        #expect(outcome.error?.kind == .providerStreamError)
        #expect(outcome.error?.providerCode == "oom")
    }

    @Test func earlyEOFWithoutFinishIsConnectionLostAndKeepsPartialText() async {
        let raw = Self.chunk(#"{"content":"half an ans"}"#) + "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"wer"
        let outcome = await StreamHarness.decodeAllSplits(.openAICompatibleChat, raw)
        #expect(outcome.text == "half an ans")
        #expect(outcome.error?.kind == .connectionLost)
        #expect(outcome.error?.acceptance == .uncertain)
    }

    @Test func finishReasonWithoutDoneIsComplete() async {
        let raw = Self.chunk(#"{"content":"done"}"#, finish: "stop")
        let outcome = await StreamHarness.decode(.openAICompatibleChat, raw)
        #expect(outcome.finish == .complete)
        #expect(outcome.error == nil)
    }

    @Test func doneWithoutFinishReasonIsCompleteButFlagged() async {
        let raw = Self.chunk(#"{"content":"done"}"#) + "data: [DONE]\n\n"
        let outcome = await StreamHarness.decode(.openAICompatibleChat, raw)
        #expect(outcome.finish == .complete)
        #expect(outcome.statuses.contains(.finishReasonMissing))
    }

    @Test func lengthFinishIsOutputLimitNotComplete() async {
        let raw = Self.chunk(#"{"content":"cut"}"#, finish: "length") + "data: [DONE]\n\n"
        #expect(await StreamHarness.decode(.openAICompatibleChat, raw).finish == .outputLimit)
    }

    @Test func usageOnlyFinalChunkIsReported() async {
        let raw = Self.chunk(#"{"content":"x"}"#, finish: "stop")
            + "data: {\"id\":\"c\",\"object\":\"chat.completion.chunk\",\"choices\":[],\"usage\":{\"prompt_tokens\":12,\"completion_tokens\":3,\"total_tokens\":15}}\n\n"
            + "data: [DONE]\n\n"
        let outcome = await StreamHarness.decode(.openAICompatibleChat, raw)
        #expect(outcome.usage == TokenUsage(inputTokens: 12, outputTokens: 3))
        #expect(outcome.finish == .complete)
    }

    @Test func nonStreamingBodyDecodes() throws {
        var decoder = ChatCompletionsDecoder(host: "fake.test", redactor: Redactor())
        let body = #"{"id":"x","object":"chat.completion","model":"m","choices":[{"index":0,"message":{"role":"assistant","content":"<think>hidden</think>Visible [c1]"},"finish_reason":"stop"}],"usage":{"prompt_tokens":5,"completion_tokens":2}}"#
        let events = try decoder.decodeNonStreaming(Data(body.utf8))
        let text = events.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined()
        #expect(text == "Visible [c1]")
        #expect(events.last == .finished(.complete))
        #expect(events.contains(.usage(TokenUsage(inputTokens: 5, outputTokens: 2))))
    }

    @Test func oversizedLineIsRejected() async {
        let raw = "data: " + String(repeating: "x", count: (1 << 20) + 10) + "\n\n"
        let outcome = await StreamHarness.decode(.openAICompatibleChat, raw, chunkSize: 65_536)
        #expect(outcome.error?.kind == .invalidResponse)
    }
}

@Suite("OpenAI Responses stream")
struct OpenAIResponsesStreamTests {
    static func event(_ json: String) -> String {
        let type = (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])?["type"] as? String ?? "?"
        return "event: \(type)\ndata: \(json)\n\n"
    }

    static let created = event(#"{"type":"response.created","response":{"id":"resp_1","object":"response","status":"in_progress","model":"model-x","output":[]},"sequence_number":0}"#)

    @Test func normalStreamFromTheReferenceShapes() async {
        let raw = Self.created
            + Self.event(#"{"type":"response.in_progress","response":{"id":"resp_1","status":"in_progress"},"sequence_number":1}"#)
            + Self.event(#"{"type":"response.output_item.added","output_index":0,"item":{"id":"msg_1","status":"in_progress","type":"message","role":"assistant","content":[]},"sequence_number":2}"#)
            + Self.event(#"{"type":"response.content_part.added","item_id":"msg_1","output_index":0,"content_index":0,"part":{"type":"output_text","text":"","annotations":[]},"sequence_number":3}"#)
            + Self.event(#"{"type":"response.output_text.delta","item_id":"msg_1","output_index":0,"content_index":0,"delta":"Thoreau — ","sequence_number":4,"logprobs":[]}"#)
            + Self.event(#"{"type":"response.output_text.delta","item_id":"msg_1","output_index":0,"content_index":0,"delta":"deliberately [c1].","sequence_number":5,"logprobs":[]}"#)
            + Self.event(#"{"type":"response.output_text.done","item_id":"msg_1","output_index":0,"content_index":0,"text":"Thoreau — deliberately [c1].","sequence_number":6}"#)
            + Self.event(#"{"type":"response.completed","response":{"id":"resp_1","status":"completed","usage":{"input_tokens":40,"output_tokens":9,"total_tokens":49}},"sequence_number":7}"#)
        let outcome = await StreamHarness.decodeAllSplits(.openAIResponses, raw)
        #expect(outcome.error == nil)
        #expect(outcome.text == "Thoreau — deliberately [c1].")
        #expect(outcome.finish == .complete)
        #expect(outcome.usage == TokenUsage(inputTokens: 40, outputTokens: 9))
        #expect(outcome.statuses.first == .accepted(responseID: "resp_1", model: "model-x"))
    }

    @Test func reasoningItemsAndSummariesAreDiscarded() async {
        let raw = Self.created
            + Self.event(#"{"type":"response.output_item.added","output_index":0,"item":{"id":"rs_1","type":"reasoning","summary":[]},"sequence_number":1}"#)
            + Self.event(#"{"type":"response.reasoning_summary_text.delta","item_id":"rs_1","output_index":0,"summary_index":0,"delta":"SECRET-SUMMARY","sequence_number":2}"#)
            + Self.event(#"{"type":"response.reasoning_text.delta","item_id":"rs_1","output_index":0,"content_index":0,"delta":"SECRET-RAW","sequence_number":3}"#)
            + Self.event(#"{"type":"response.output_text.delta","item_id":"msg_1","output_index":1,"content_index":0,"delta":"Answer.","sequence_number":4}"#)
            + Self.event(#"{"type":"response.completed","response":{"id":"resp_1","status":"completed"},"sequence_number":5}"#)
        let outcome = await StreamHarness.decodeAllSplits(.openAIResponses, raw)
        #expect(outcome.text == "Answer.")
        #expect(!outcome.text.contains("SECRET"))
        #expect(outcome.statuses.contains(.reasoningOmitted))
    }

    @Test func functionCallIsRejected() async {
        let raw = Self.created
            + Self.event(#"{"type":"response.output_item.added","output_index":0,"item":{"id":"fc_1","type":"function_call","name":"fetch_url","arguments":"","call_id":"call_1"},"sequence_number":1}"#)
            + Self.event(#"{"type":"response.function_call_arguments.delta","item_id":"fc_1","output_index":0,"delta":"{\"url\":\"https://evil.example\"}","sequence_number":2}"#)
            + Self.event(#"{"type":"response.function_call_arguments.done","item_id":"fc_1","output_index":0,"arguments":"{\"url\":\"https://evil.example\"}","sequence_number":3}"#)
            + Self.event(#"{"type":"response.completed","response":{"id":"resp_1","status":"completed"},"sequence_number":4}"#)
        let outcome = await StreamHarness.decodeAllSplits(.openAIResponses, raw)
        #expect(outcome.statuses.contains(.toolCallRejected(name: "fetch_url")))
        #expect(outcome.finish == .toolCallRejected)
        #expect(!outcome.text.contains("evil"))
    }

    @Test func refusalIsSurfacedSeparately() async {
        let raw = Self.created
            + Self.event(#"{"type":"response.refusal.delta","item_id":"msg_1","output_index":0,"content_index":0,"delta":"I can't ","sequence_number":1}"#)
            + Self.event(#"{"type":"response.refusal.delta","item_id":"msg_1","output_index":0,"content_index":0,"delta":"help.","sequence_number":2}"#)
            + Self.event(#"{"type":"response.refusal.done","item_id":"msg_1","output_index":0,"content_index":0,"refusal":"I can't help.","sequence_number":3}"#)
            + Self.event(#"{"type":"response.completed","response":{"id":"resp_1","status":"completed"},"sequence_number":4}"#)
        let outcome = await StreamHarness.decodeAllSplits(.openAIResponses, raw)
        #expect(outcome.refusal == "I can't help.")
        #expect(outcome.text.isEmpty)
        #expect(outcome.finish == .refused)
    }

    @Test func incompleteForOutputLimitIsNotComplete() async {
        let raw = Self.created
            + Self.event(#"{"type":"response.output_text.delta","item_id":"m","output_index":0,"content_index":0,"delta":"Cut off","sequence_number":1}"#)
            + Self.event(#"{"type":"response.incomplete","response":{"id":"resp_1","status":"incomplete","incomplete_details":{"reason":"max_output_tokens"}},"sequence_number":2}"#)
        let outcome = await StreamHarness.decodeAllSplits(.openAIResponses, raw)
        #expect(outcome.finish == .outputLimit)
        #expect(outcome.text == "Cut off")
    }

    @Test func failedResponseAndErrorEventAreProviderErrors() async {
        let failed = Self.created + Self.event(#"{"type":"response.failed","response":{"id":"resp_1","status":"failed","error":{"code":"server_error","message":"The model failed to generate a response."}},"sequence_number":1}"#)
        let failedOutcome = await StreamHarness.decodeAllSplits(.openAIResponses, failed)
        #expect(failedOutcome.error?.kind == .providerStreamError)
        #expect(failedOutcome.error?.providerCode == "server_error")
        let error = Self.created + Self.event(#"{"type":"error","code":"ERR_SOMETHING","message":"Something went wrong","param":null,"sequence_number":1}"#)
        let errorOutcome = await StreamHarness.decodeAllSplits(.openAIResponses, error)
        #expect(errorOutcome.error?.kind == .providerStreamError)
        #expect(errorOutcome.error?.acceptance == .uncertain)
    }

    @Test func earlyEOFIsConnectionLost() async {
        let raw = Self.created + Self.event(#"{"type":"response.output_text.delta","item_id":"m","output_index":0,"content_index":0,"delta":"Half","sequence_number":1}"#)
        let outcome = await StreamHarness.decodeAllSplits(.openAIResponses, raw)
        #expect(outcome.text == "Half")
        #expect(outcome.error?.kind == .connectionLost)
    }

    @Test func malformedJSONIsInvalidResponse() async {
        let raw = Self.created + "event: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\n\n"
        let outcome = await StreamHarness.decode(.openAIResponses, raw)
        #expect(outcome.error?.kind == .invalidResponse)
    }
}

@Suite("Anthropic Messages stream")
struct AnthropicMessagesStreamTests {
    static func event(_ type: String, _ json: String) -> String { "event: \(type)\ndata: \(json)\n\n" }

    static let start = event("message_start", #"{"type": "message_start", "message": {"id": "msg_1", "type": "message", "role": "assistant", "content": [], "model": "claude-test", "stop_reason": null, "stop_sequence": null, "usage": {"input_tokens": 25, "output_tokens": 1}}}"#)

    @Test func basicStreamFromTheReference() async {
        let raw = Self.start
            + Self.event("content_block_start", #"{"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}"#)
            + Self.event("ping", #"{"type": "ping"}"#)
            + Self.event("content_block_delta", #"{"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Hello"}}"#)
            + Self.event("content_block_delta", #"{"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": " — café 😀!"}}"#)
            + Self.event("content_block_stop", #"{"type": "content_block_stop", "index": 0}"#)
            + Self.event("message_delta", #"{"type": "message_delta", "delta": {"stop_reason": "end_turn", "stop_sequence":null}, "usage": {"output_tokens": 15}}"#)
            + Self.event("message_stop", #"{"type": "message_stop"}"#)
        let outcome = await StreamHarness.decodeAllSplits(.anthropicMessages, raw)
        #expect(outcome.error == nil)
        #expect(outcome.text == "Hello — café 😀!")
        #expect(outcome.finish == .complete)
        #expect(outcome.usage == TokenUsage(inputTokens: 25, outputTokens: 15))
        #expect(outcome.statuses.first == .accepted(responseID: "msg_1", model: "claude-test"))
    }

    @Test func thinkingBlocksAreNeverAnswerText() async {
        let raw = Self.start
            + Self.event("content_block_start", #"{"type": "content_block_start", "index": 0, "content_block": {"type": "thinking", "thinking": "", "signature": ""}}"#)
            + Self.event("content_block_delta", #"{"type": "content_block_delta", "index": 0, "delta": {"type": "thinking_delta", "thinking": "SECRET-THINKING 1071 = 2 × 462 + 147"}}"#)
            + Self.event("content_block_delta", #"{"type": "content_block_delta", "index": 0, "delta": {"type": "signature_delta", "signature": "EqQBCgIYAhIM1gbcDa9GJwZA2b3hGgxBdjrkzLoky3dl1pkiMOYds"}}"#)
            + Self.event("content_block_stop", #"{"type": "content_block_stop", "index": 0}"#)
            + Self.event("content_block_start", #"{"type": "content_block_start", "index": 1, "content_block": {"type": "redacted_thinking", "data": "SECRET-REDACTED"}}"#)
            + Self.event("content_block_stop", #"{"type": "content_block_stop", "index": 1}"#)
            + Self.event("content_block_start", #"{"type": "content_block_start", "index": 2, "content_block": {"type": "text", "text": ""}}"#)
            + Self.event("content_block_delta", #"{"type": "content_block_delta", "index": 2, "delta": {"type": "text_delta", "text": "The greatest common divisor is **21**."}}"#)
            + Self.event("content_block_stop", #"{"type": "content_block_stop", "index": 2}"#)
            + Self.event("message_delta", #"{"type": "message_delta", "delta": {"stop_reason": "end_turn", "stop_sequence": null}}"#)
            + Self.event("message_stop", #"{"type": "message_stop"}"#)
        let outcome = await StreamHarness.decodeAllSplits(.anthropicMessages, raw)
        #expect(outcome.text == "The greatest common divisor is **21**.")
        #expect(!outcome.text.contains("SECRET"))
        #expect(!outcome.text.contains("EqQB"))
        #expect(outcome.statuses.contains(.reasoningOmitted))
        #expect(outcome.finish == .complete)
    }

    @Test func textDeltaAimedAtAThinkingBlockIsRejected() async {
        let raw = Self.start
            + Self.event("content_block_start", #"{"type": "content_block_start", "index": 0, "content_block": {"type": "thinking", "thinking": ""}}"#)
            + Self.event("content_block_delta", #"{"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "SECRET-SMUGGLED"}}"#)
        let outcome = await StreamHarness.decodeAllSplits(.anthropicMessages, raw)
        #expect(outcome.text.isEmpty)
        #expect(outcome.error?.kind == .invalidResponse)
    }

    @Test func toolUseIsRejectedAndInputJSONNeverSurfaces() async {
        let raw = Self.start
            + Self.event("content_block_start", #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#)
            + Self.event("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Okay, let's check:"}}"#)
            + Self.event("content_block_stop", #"{"type":"content_block_stop","index":0}"#)
            + Self.event("content_block_start", #"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"get_weather","input":{}}}"#)
            + Self.event("content_block_delta", #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"location\": \"San Fra"}}"#)
            + Self.event("content_block_delta", #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"ncisco\"}"}}"#)
            + Self.event("content_block_stop", #"{"type":"content_block_stop","index":1}"#)
            + Self.event("message_delta", #"{"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":89}}"#)
            + Self.event("message_stop", #"{"type":"message_stop"}"#)
        let outcome = await StreamHarness.decodeAllSplits(.anthropicMessages, raw)
        #expect(outcome.text == "Okay, let's check:")
        #expect(outcome.statuses.contains(.toolCallRejected(name: "get_weather")))
        #expect(outcome.finish == .toolCallRejected)
        #expect(!outcome.text.contains("San"))
    }

    @Test func refusalStopReasonKeepsPartialTextAndIsRefused() async {
        let raw = Self.start
            + Self.event("content_block_start", #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#)
            + Self.event("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"I started"}}"#)
            + Self.event("message_delta", #"{"type":"message_delta","delta":{"stop_reason":"refusal","stop_sequence":null},"stop_details":{"type":"refusal","category":"cyber"},"usage":{"output_tokens":3}}"#)
            + Self.event("message_stop", #"{"type":"message_stop"}"#)
        let outcome = await StreamHarness.decodeAllSplits(.anthropicMessages, raw)
        #expect(outcome.finish == .refused)
        #expect(outcome.text == "I started")
    }

    @Test func maxTokensIsOutputLimit() async {
        let raw = Self.start
            + Self.event("message_delta", #"{"type":"message_delta","delta":{"stop_reason":"max_tokens"},"usage":{"output_tokens":3}}"#)
            + Self.event("message_stop", #"{"type":"message_stop"}"#)
        #expect(await StreamHarness.decode(.anthropicMessages, raw).finish == .outputLimit)
    }

    @Test func overloadedErrorEventIsUncertainProviderError() async {
        let raw = Self.start
            + Self.event("content_block_start", #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#)
            + Self.event("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Part"}}"#)
            + Self.event("error", #"{"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}}"#)
        let outcome = await StreamHarness.decodeAllSplits(.anthropicMessages, raw)
        #expect(outcome.text == "Part")
        #expect(outcome.error?.kind == .providerStreamError)
        #expect(outcome.error?.providerCode == "overloaded_error")
        #expect(outcome.error?.acceptance == .uncertain)
        #expect(outcome.error?.isTransient == false)
    }

    @Test func earlyEOFIsConnectionLost() async {
        let raw = Self.start + Self.event("content_block_start", #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#)
            + "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"cut"
        let outcome = await StreamHarness.decodeAllSplits(.anthropicMessages, raw)
        #expect(outcome.error?.kind == .connectionLost)
    }

    @Test func unknownEventTypesAreIgnored() async {
        let raw = Self.start + Self.event("future_event", #"{"type":"future_event","x":1}"#)
            + Self.event("message_delta", #"{"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#)
            + Self.event("message_stop", #"{"type":"message_stop"}"#)
        let outcome = await StreamHarness.decode(.anthropicMessages, raw)
        #expect(outcome.error == nil)
        #expect(outcome.finish == .complete)
    }
}
