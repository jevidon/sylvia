import Foundation
import G05TestSupport
import Testing
@testable import SylviaAI

enum Configs {
    static func generic(_ server: FakeHTTPServer, path: String = "/v1", streaming: Bool = true, credential: CredentialRef? = nil,
                        model: String = "local-model") -> ProviderConfig {
        ProviderConfig(kind: .openAICompatibleChat, displayName: "Local", baseURL: try! BaseURL.normalize(server.baseURL.absoluteString + path),
                       model: model, credential: credential, capabilities: ProviderCapabilities(streaming: streaming),
                       requestTimeoutMs: 5_000, allowInsecureLocalHTTP: true)
    }

    static func openAI(_ credential: CredentialRef = CredentialRef(origin: "https://api.openai.com")) -> ProviderConfig {
        ProviderConfig(kind: .openAIResponses, displayName: "OpenAI", baseURL: ProviderKind.openAIResponses.defaultBaseURL!,
                       model: "model-under-test", credential: credential, requestTimeoutMs: 5_000)
    }

    static func anthropic(_ credential: CredentialRef = CredentialRef(origin: "https://api.anthropic.com")) -> ProviderConfig {
        ProviderConfig(kind: .anthropicMessages, displayName: "Anthropic", baseURL: ProviderKind.anthropicMessages.defaultBaseURL!,
                       model: "claude-test", credential: credential, requestTimeoutMs: 5_000)
    }
}

func collect(_ stream: AsyncThrowingStream<GenerationEvent, any Error>) async -> DecodeOutcome {
    var outcome = DecodeOutcome()
    do {
        for try await event in stream { outcome.events.append(event) }
    } catch let error as ProviderError {
        outcome.error = error
    } catch {
        outcome.error = ProviderError(kind: .connectionLost, acceptance: .uncertain, host: "?", detail: "\(error)")
    }
    return outcome
}

let sampleRequest = GenerationRequest(system: "System text.", messages: [.init(role: .user, text: "What does c1 mean?")], maxOutputTokens: 200)

/// Brief items 1 and 9: each adapter end to end over real HTTP to an in-process server on 127.0.0.1:0.
@Suite("Provider adapters end to end (loopback fake server)")
struct ProviderEndToEndTests {
    @Test func genericAdapterStreamsFromAFakeLocalServer() async throws {
        let server = try await FakeHTTPServer { _ in
            .sse([
                ": keepalive\n\n",
                "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"model\":\"local-model\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"Hel\"},\"finish_reason\":null}]}\n\n",
                "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"lo — 😀\"},\"finish_reason\":\"stop\"}]}\n\n",
                "data: [DONE]\n\n",
            ], pauseMs: 5)
        }
        let config = Configs.generic(server)
        #expect(config.endpointURL.path() == "/v1/chat/completions")
        let provider = HTTPTextGenerationProvider(config: config, credentials: InMemoryCredentialStore(), transport: URLSessionTransport())
        let outcome = await collect(provider.streamGeneration(sampleRequest))
        #expect(outcome.error == nil)
        #expect(outcome.text == "Hello — 😀")
        #expect(outcome.finish == .complete)

        let request = try #require(server.requests.first)
        #expect(request.method == "POST")
        #expect(request.path == "/v1/chat/completions")
        #expect(request.headers["authorization"] == nil, "no credential configured, so no Authorization header")
        let json = try #require(request.json)
        #expect(json["model"] as? String == "local-model")
        #expect(json["stream"] as? Bool == true)
        #expect(json["stream_options"] == nil, "stream_options is only sent when the endpoint declares it")
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages.map { $0["role"] } == ["system", "user"])
        #expect(json["tools"] == nil, "Sylvia never offers tools")
    }

    @Test func genericAdapterWorksWithANonStreamingEndpoint() async throws {
        let server = try await FakeHTTPServer { _ in
            .json(200, #"{"id":"x","object":"chat.completion","model":"m","choices":[{"index":0,"message":{"role":"assistant","content":"Plain answer."},"finish_reason":"stop"}]}"#)
        }
        let provider = HTTPTextGenerationProvider(config: Configs.generic(server, streaming: false), credentials: InMemoryCredentialStore(),
                                                  transport: URLSessionTransport())
        let outcome = await collect(provider.streamGeneration(sampleRequest))
        #expect(outcome.text == "Plain answer.")
        #expect(outcome.finish == .complete)
        #expect(server.requests.first?.json?["stream"] as? Bool == false)
    }

    @Test func genericAdapterToleratesAServerThatIgnoresStreamTrue() async throws {
        let server = try await FakeHTTPServer { _ in
            .json(200, #"{"id":"x","object":"chat.completion","choices":[{"index":0,"message":{"role":"assistant","content":"Whole reply."},"finish_reason":"stop"}]}"#)
        }
        let provider = HTTPTextGenerationProvider(config: Configs.generic(server), credentials: InMemoryCredentialStore(), transport: URLSessionTransport())
        let outcome = await collect(provider.streamGeneration(sampleRequest))
        #expect(outcome.text == "Whole reply.")
    }

    @Test func genericAdapterSendsBearerKeyOnlyToItsOwnOrigin() async throws {
        let server = try await FakeHTTPServer { _ in
            .sse(["data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"ok\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"])
        }
        let store = InMemoryCredentialStore()
        let ref = try #require(CredentialRef(for: server.baseURL))
        try store.save(Secret(Canary.apiKey), for: ref)
        let provider = HTTPTextGenerationProvider(config: Configs.generic(server, credential: ref), credentials: store, transport: URLSessionTransport())
        _ = await collect(provider.streamGeneration(sampleRequest))
        let request = try #require(server.requests.first)
        #expect(request.headers["authorization"] == "Bearer \(Canary.apiKey)")
        #expect(!request.bodyText.contains(Canary.apiKey), "the key travels in the header only")
        #expect(!request.path.contains("sk-"), "never in the URL")
    }

    @Test func openAIResponsesAdapterRequestShapeAndStream() async throws {
        let server = try await FakeHTTPServer { _ in
            .sse([
                "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_9\",\"model\":\"model-under-test\",\"status\":\"in_progress\"},\"sequence_number\":0}\n\n",
                "event: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"item_id\":\"m\",\"output_index\":0,\"content_index\":0,\"delta\":\"Answer [c1].\",\"sequence_number\":1}\n\n",
                "event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_9\",\"status\":\"completed\",\"usage\":{\"input_tokens\":10,\"output_tokens\":3}},\"sequence_number\":2}\n\n",
            ])
        }
        let store = InMemoryCredentialStore()
        let ref = CredentialRef(origin: "https://api.openai.com")
        try store.save(Secret(Canary.apiKey), for: ref)
        let provider = HTTPTextGenerationProvider(config: Configs.openAI(ref), credentials: store,
                                                  transport: LoopbackRewriteTransport(target: server.baseURL))
        let outcome = await collect(provider.streamGeneration(sampleRequest))
        #expect(outcome.text == "Answer [c1].")
        #expect(outcome.finish == .complete)
        let request = try #require(server.requests.first)
        #expect(request.path == "/v1/responses")
        #expect(request.headers["authorization"] == "Bearer \(Canary.apiKey)")
        #expect(request.headers["accept"] == "text/event-stream")
        let json = try #require(request.json)
        #expect(json["store"] as? Bool == false, "Responses stores by default; Sylvia opts out")
        #expect(json["stream"] as? Bool == true)
        #expect(json["instructions"] as? String == "System text.")
        #expect(json["max_output_tokens"] as? Int == 200)
        #expect((json["input"] as? [[String: String]])?.first?["content"] == "What does c1 mean?")
        #expect(json["tools"] == nil && json["previous_response_id"] == nil)
    }

    @Test func anthropicAdapterRequestShapeAndStream() async throws {
        let server = try await FakeHTTPServer { _ in
            .sse([
                "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_9\",\"model\":\"claude-test\",\"content\":[],\"usage\":{\"input_tokens\":9,\"output_tokens\":1}}}\n\n",
                "event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
                "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Grounded [c1].\"}}\n\n",
                "event: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":4}}\n\n",
                "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n",
            ])
        }
        let store = InMemoryCredentialStore()
        let ref = CredentialRef(origin: "https://api.anthropic.com")
        try store.save(Secret(Canary.anthropicKey), for: ref)
        let provider = HTTPTextGenerationProvider(config: Configs.anthropic(ref), credentials: store,
                                                  transport: LoopbackRewriteTransport(target: server.baseURL))
        let outcome = await collect(provider.streamGeneration(sampleRequest))
        #expect(outcome.text == "Grounded [c1].")
        #expect(outcome.finish == .complete)
        let request = try #require(server.requests.first)
        #expect(request.path == "/v1/messages")
        #expect(request.headers["x-api-key"] == Canary.anthropicKey)
        #expect(request.headers["authorization"] == nil)
        #expect(request.headers["anthropic-version"] == "2023-06-01")
        let json = try #require(request.json)
        #expect(json["system"] as? String == "System text.")
        #expect(json["max_tokens"] as? Int == 200)
        #expect(json["stream"] as? Bool == true)
        #expect(json["thinking"] == nil && json["tools"] == nil && json["fallbacks"] == nil,
                "no thinking config, tools or server-side model fallback are requested")
        #expect((json["messages"] as? [[String: String]])?.map { $0["role"] } == ["user"])
    }

    @Test func earlyCloseMidStreamIsConnectionLostWithPartialText() async throws {
        let server = try await FakeHTTPServer { _ in
            .sse(["data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"partial \"},\"finish_reason\":null}]}\n\n",
                  "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"text"], pauseMs: 20, abortAtEnd: true)
        }
        let provider = HTTPTextGenerationProvider(config: Configs.generic(server), credentials: InMemoryCredentialStore(), transport: URLSessionTransport())
        let outcome = await collect(provider.streamGeneration(sampleRequest))
        #expect(outcome.text == "partial ")
        #expect(outcome.error?.kind == .connectionLost)
        #expect(outcome.error?.acceptance == .uncertain)
    }
}
