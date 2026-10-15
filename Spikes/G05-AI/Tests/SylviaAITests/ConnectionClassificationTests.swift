import Foundation
import G05TestSupport
import Testing
@testable import SylviaAI

struct FakeInspector: NetworkPathInspector {
    let denied: Bool
    func isLocalNetworkDenied(_ error: URLError) -> Bool { denied }
}

/// Brief item 5 / plan 14.3: connection tests classify failures with actionable, secret-free messages.
/// Real loopback failures where they can be produced deterministically; URLProtocol stubs for DNS, offline and
/// untrusted certificates; an injected path inspector for local-network permission (device check pending).
@Suite("Connection test classification", .serialized)
struct ConnectionClassificationTests {
    /// `config` with the canary key stored for its own origin, and the store holding it.
    static func keyed(_ config: ProviderConfig) -> (InMemoryCredentialStore, ProviderConfig) {
        let store = InMemoryCredentialStore()
        var config = config
        let ref = CredentialRef(for: config.baseURL)!
        try! store.save(Secret(Canary.apiKey), for: ref)
        config.credential = ref
        return (store, config)
    }

    static func assertSafeMessage(_ report: ConnectionTestReport, sourceLocation: SourceLocation = #_sourceLocation) {
        let message = report.userMessage
        #expect(!message.contains(Canary.apiKey), sourceLocation: sourceLocation)
        #expect(!message.contains("CANARY"), sourceLocation: sourceLocation)
        #expect(!message.lowercased().contains("ai failed"), sourceLocation: sourceLocation)
        if case .failed(let error) = report.outcome {
            #expect(!"\(error) \(error.detail ?? "") \(error.providerCode ?? "")".contains("CANARY"), sourceLocation: sourceLocation)
        }
    }

    static func kind(_ report: ConnectionTestReport) -> FailureKind? {
        if case .failed(let error) = report.outcome { return error.kind }
        return nil
    }

    @Test func passingTestReportsDisclosureAndCapabilities() async throws {
        let server = try await FakeHTTPServer { _ in
            .sse(["data: {\"model\":\"served-model\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"OK\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"])
        }
        let report = await ConnectionTester(credentials: InMemoryCredentialStore(), transport: URLSessionTransport()).test(Configs.generic(server))
        #expect(report.outcome == .passed)
        #expect(report.endpoint?.disclosureRow == "127.0.0.1 · local · local-model")
        #expect(report.reportedModel == "served-model")
        #expect(report.streamed)
        let body = try #require(server.requests.first?.bodyText)
        #expect(body.contains("Reply with the single word OK."), "the probe sends only fixed text")
    }

    @Test func serverThatIgnoresStreamingIsReportedAsNotStreamed() async throws {
        // Many compatible servers answer `stream: true` with one chat.completion JSON body.
        let server = try await FakeHTTPServer { _ in
            .json(200, #"{"id":"x","object":"chat.completion","model":"served-model","choices":[{"index":0,"message":{"role":"assistant","content":"OK"},"finish_reason":"stop"}]}"#)
        }
        let report = await ConnectionTester(credentials: InMemoryCredentialStore(), transport: URLSessionTransport()).test(Configs.generic(server))
        #expect(report.outcome == .passed)
        #expect(!report.streamed, "the report describes what the server did, not what was configured")
        #expect(report.userMessage == "Connected to 127.0.0.1 · local · local-model. Test reply received.")
        let json = try #require(server.requests.first?.json)
        #expect(json["stream"] as? Bool == true)
    }

    // MARK: Conformance (R2-01, plan 14.1 "usable only if its configured route passes conformance tests", 14.3
    // "invalid response"): the test passes only when the reply ends normally with answer text.

    static func chatChunk(_ delta: String, finish: String? = nil) -> String {
        "data: {\"model\":\"served-model\",\"choices\":[{\"index\":0,\"delta\":\(delta),\"finish_reason\":\(finish.map { "\"\($0)\"" } ?? "null")}]}\n\n"
    }

    static func genericReport(_ sse: String, config: (FakeHTTPServer) -> ProviderConfig = { Configs.generic($0) }) async throws
        -> (ConnectionTestReport, FakeHTTPServer) {
        let server = try await FakeHTTPServer { _ in .sse([sse]) }
        let report = await ConnectionTester(credentials: InMemoryCredentialStore(), transport: URLSessionTransport()).test(config(server))
        return (report, server)
    }

    static func assertNotPassed(_ report: ConnectionTestReport, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(report.outcome != .passed, sourceLocation: sourceLocation)
        #expect(!report.userMessage.contains("Test reply received"), sourceLocation: sourceLocation)
        assertSafeMessage(report, sourceLocation: sourceLocation)
    }

    @Test func toolCallOnlyRouteFailsTheTest() async throws {
        // A gateway route that answers with a tool call and no text (the reviewer's probe).
        let sse = Self.chatChunk(#"{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"run_shell","arguments":""}}]}"#)
            + Self.chatChunk(#"{"tool_calls":[{"index":0,"function":{"arguments":"{\"cmd\":\"ls\"}"}}]}"#)
            + Self.chatChunk("{}", finish: "tool_calls") + "data: [DONE]\n\n"
        let (report, _) = try await Self.genericReport(sse)
        #expect(report.outcome == .failedConformance(.toolCall))
        #expect(report.userMessage == "127.0.0.1 answered the test by asking to run a tool. Sylvia never runs tools, so it can't use this route. Configure a text-only route or model for this endpoint.")
        Self.assertNotPassed(report)
        #expect(!report.userMessage.contains("run_shell") && !report.userMessage.contains("cmd"), "nothing from the tool call is shown")
    }

    @Test func toolCallAfterTextStillFailsTheTest() async throws {
        let sse = Self.chatChunk(#"{"content":"OK"}"#)
            + Self.chatChunk(#"{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"fetch_url","arguments":"{}"}}]}"#)
            + Self.chatChunk("{}", finish: "stop") + "data: [DONE]\n\n"
        let (report, _) = try await Self.genericReport(sse)
        #expect(report.outcome == .failedConformance(.toolCall))
        Self.assertNotPassed(report)
    }

    @Test func toolCallFailsTheTestOnTheFirstPartyAdapters() async throws {
        let responses = try await FakeHTTPServer { _ in
            .sse([OpenAIResponsesStreamTests.created
                  + OpenAIResponsesStreamTests.event(#"{"type":"response.output_item.added","output_index":0,"item":{"id":"fc_1","type":"function_call","name":"fetch_url","arguments":"","call_id":"call_1"},"sequence_number":1}"#)
                  + OpenAIResponsesStreamTests.event(#"{"type":"response.completed","response":{"id":"resp_1","status":"completed"},"sequence_number":2}"#)])
        }
        let anthropic = try await FakeHTTPServer { _ in
            .sse([AnthropicMessagesStreamTests.start
                  + AnthropicMessagesStreamTests.event("content_block_start", #"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"get_weather","input":{}}}"#)
                  + AnthropicMessagesStreamTests.event("content_block_stop", #"{"type":"content_block_stop","index":0}"#)
                  + AnthropicMessagesStreamTests.event("message_delta", #"{"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":9}}"#)
                  + AnthropicMessagesStreamTests.event("message_stop", #"{"type":"message_stop"}"#)])
        }
        let (openAIStore, openAIConfig) = Self.keyed(Configs.openAI())
        let (anthropicStore, anthropicConfig) = Self.keyed(Configs.anthropic())
        let openAIReport = await ConnectionTester(credentials: openAIStore, transport: LoopbackRewriteTransport(target: responses.baseURL)).test(openAIConfig)
        let anthropicReport = await ConnectionTester(credentials: anthropicStore, transport: LoopbackRewriteTransport(target: anthropic.baseURL)).test(anthropicConfig)
        #expect(openAIReport.outcome == .failedConformance(.toolCall))
        #expect(anthropicReport.outcome == .failedConformance(.toolCall))
        Self.assertNotPassed(openAIReport)
        Self.assertNotPassed(anthropicReport)
    }

    @Test func reasoningOnlyReplyAtTheOutputLimitFailsTheTest() async throws {
        // A model that reasons first and runs out of output before any answer text (the reviewer's probe).
        let sse = Self.chatChunk(#"{"reasoning_content":"The user wants OK. Let me think about whether"}"#)
            + Self.chatChunk("{}", finish: "length") + "data: [DONE]\n\n"
        let (report, _) = try await Self.genericReport(sse)
        #expect(report.outcome == .failedConformance(.outputLimitBeforeText(maxOutputTokens: ConnectionTester.defaultProbeOutputTokens)))
        #expect(report.userMessage.contains("reached the output limit (1024 tokens) before any reply text"))
        #expect(report.userMessage.contains("Raise the maximum output for this endpoint"))
        Self.assertNotPassed(report)
    }

    @Test func replyCutOffAtTheOutputLimitFailsTheTest() async throws {
        let sse = Self.chatChunk(#"{"content":"O"}"#) + Self.chatChunk("{}", finish: "length") + "data: [DONE]\n\n"
        let (report, _) = try await Self.genericReport(sse)
        #expect(report.outcome == .failedConformance(.outputLimitTruncated(maxOutputTokens: ConnectionTester.defaultProbeOutputTokens)))
        Self.assertNotPassed(report)
    }

    @Test func refusalOnlyReplyFailsTheTest() async throws {
        // delta.refusal with no answer text (the reviewer's probe), and the same with a plain "stop".
        for finish in ["stop", nil] as [String?] {
            let sse = Self.chatChunk(#"{"refusal":"I can't help with that."}"#) + Self.chatChunk("{}", finish: finish) + "data: [DONE]\n\n"
            let (report, _) = try await Self.genericReport(sse)
            #expect(report.outcome == .failedConformance(.refused), "finish \(finish ?? "missing")")
            #expect(report.userMessage == "127.0.0.1 answered but refused the test question, so Sylvia can't confirm it will answer questions. Check the model and any content policy on this endpoint.")
            Self.assertNotPassed(report)
        }
        // Anthropic's refusal stop reason with no text.
        let anthropic = try await FakeHTTPServer { _ in
            .sse([AnthropicMessagesStreamTests.start
                  + AnthropicMessagesStreamTests.event("message_delta", #"{"type":"message_delta","delta":{"stop_reason":"refusal","stop_sequence":null},"usage":{"output_tokens":1}}"#)
                  + AnthropicMessagesStreamTests.event("message_stop", #"{"type":"message_stop"}"#)])
        }
        let (store, config) = Self.keyed(Configs.anthropic())
        let report = await ConnectionTester(credentials: store, transport: LoopbackRewriteTransport(target: anthropic.baseURL)).test(config)
        #expect(report.outcome == .failedConformance(.refused))
        Self.assertNotPassed(report)
    }

    @Test func contentFilteredReplyFailsTheTest() async throws {
        let (report, _) = try await Self.genericReport(Self.chatChunk("{}", finish: "content_filter") + "data: [DONE]\n\n")
        #expect(report.outcome == .failedConformance(.contentFiltered))
        Self.assertNotPassed(report)
    }

    @Test func probeUsesTheOutputLimitRealQuestionsGet() async throws {
        let ok = Self.chatChunk(#"{"content":"OK"}"#, finish: "stop") + "data: [DONE]\n\n"
        let (defaultReport, defaultServer) = try await Self.genericReport(ok)
        #expect(defaultReport.outcome == .passed)
        #expect(try #require(defaultServer.requests.first?.json)["max_tokens"] as? Int == ConnectionTester.defaultProbeOutputTokens)
        let (configuredReport, configuredServer) = try await Self.genericReport(ok) { server in
            var config = Configs.generic(server)
            config.maxOutputTokens = 4_000
            return config
        }
        #expect(configuredReport.outcome == .passed)
        #expect(try #require(configuredServer.requests.first?.json)["max_tokens"] as? Int == 4_000)
    }

    /// Every finish reason, with and without text, a refusal or a tool call: only a normal end with text passes.
    @Test func onlyANormalEndWithTextPasses() {
        let reasons: [FinishReason?] = [nil, .complete, .outputLimit, .refused, .contentFiltered, .toolCallRejected, .contextWindowExceeded, .incomplete("x")]
        var passes = 0
        for finish in reasons {
            for sawText in [false, true] {
                for sawRefusal in [false, true] {
                    for sawToolCall in [false, true] {
                        let outcome = ConnectionTester.judge(finish: finish, sawText: sawText, sawRefusal: sawRefusal, sawToolCall: sawToolCall,
                                                             maxOutputTokens: 16, host: "h")
                        let shouldPass = finish == .complete && sawText && !sawRefusal && !sawToolCall
                        #expect((outcome == .passed) == shouldPass, "\(String(describing: finish)) text=\(sawText) refusal=\(sawRefusal) tool=\(sawToolCall)")
                        if outcome == .passed { passes += 1 }
                        if sawToolCall { #expect(outcome == .failedConformance(.toolCall)) }
                    }
                }
            }
        }
        #expect(passes == 1)
    }

    @Test func dnsFailure() async {
        StubURLProtocol.reset()
        StubURLProtocol.fail(host: "nowhere.invalid", with: .cannotFindHost)
        var unkeyed = Configs.openAI()
        unkeyed.baseURL = URL(string: "https://nowhere.invalid/v1")!
        let (store, config) = Self.keyed(unkeyed)
        let report = await ConnectionTester(credentials: store, transport: URLSessionTransport(protocolClasses: [StubURLProtocol.self])).test(config)
        #expect(Self.kind(report) == .dns)
        #expect(report.userMessage.contains("Couldn't find nowhere.invalid"))
        Self.assertSafeMessage(report)
    }

    @Test func localNetworkPermissionDenied() async {
        StubURLProtocol.reset()
        StubURLProtocol.fail(host: "192.168.1.20", with: .notConnectedToInternet)
        var config = Configs.generic(try! await FakeHTTPServer { _ in .json(200, "{}") })
        config.baseURL = URL(string: "http://192.168.1.20:1234/v1")!
        let report = await ConnectionTester(credentials: InMemoryCredentialStore(),
                                            transport: URLSessionTransport(protocolClasses: [StubURLProtocol.self]),
                                            inspector: FakeInspector(denied: true)).test(config)
        #expect(Self.kind(report) == .localNetworkPermissionDenied)
        #expect(report.userMessage.contains("Local Network"))
        Self.assertSafeMessage(report)
    }

    @Test func offlineIsNotMistakenForPermissionDenial() async {
        StubURLProtocol.reset()
        StubURLProtocol.fail(host: "192.168.1.21", with: .notConnectedToInternet)
        var config = Configs.generic(try! await FakeHTTPServer { _ in .json(200, "{}") })
        config.baseURL = URL(string: "http://192.168.1.21:1234/v1")!
        let report = await ConnectionTester(credentials: InMemoryCredentialStore(),
                                            transport: URLSessionTransport(protocolClasses: [StubURLProtocol.self]),
                                            inspector: FakeInspector(denied: false)).test(config)
        #expect(Self.kind(report) == .offline)
    }

    @Test func hostUnreachableOnAClosedLoopbackPort() async throws {
        let server = try await FakeHTTPServer { _ in .json(200, "{}") }
        let config = Configs.generic(server)
        server.stop()
        try await Task.sleep(for: .milliseconds(50))
        let report = await ConnectionTester(credentials: InMemoryCredentialStore(), transport: URLSessionTransport()).test(config)
        #expect(Self.kind(report) == .hostUnreachable)
        #expect(report.userMessage.contains("didn't accept the connection"))
    }

    @Test func tlsFailureAgainstAServerThatDoesNotSpeakTLS() async throws {
        let server = try await FakeHTTPServer { _ in .json(200, "{}") }
        var config = Configs.generic(server)
        config.baseURL = URL(string: "https://127.0.0.1:\(server.port)/v1")!
        let report = await ConnectionTester(credentials: InMemoryCredentialStore(), transport: URLSessionTransport()).test(config)
        #expect(Self.kind(report) == .tls)
        #expect(server.requests.isEmpty, "no HTTP request (and so no body or key) reached the server")
        #expect(server.nonHTTPConnectionCount >= 1, "the server saw a TLS handshake attempt, not HTTP")
    }

    @Test func untrustedCertificateIsTLS() async {
        StubURLProtocol.reset()
        StubURLProtocol.fail(host: "selfsigned.example", with: .serverCertificateUntrusted)
        var unkeyed = Configs.openAI()
        unkeyed.baseURL = URL(string: "https://selfsigned.example/v1")!
        let (store, config) = Self.keyed(unkeyed)
        let report = await ConnectionTester(credentials: store, transport: URLSessionTransport(protocolClasses: [StubURLProtocol.self])).test(config)
        #expect(Self.kind(report) == .tls)
        #expect(report.userMessage.contains("certificate"))
    }

    @Test func authenticationFailureWithKeyEchoedByServerIsScrubbed() async throws {
        let partial = String(Canary.apiKey.prefix(12)) + "***" + String(Canary.apiKey.suffix(6))
        let server = try await FakeHTTPServer { _ in
            .json(401, #"{"error":{"message":"Incorrect API key provided: \#(partial). Full: \#(Canary.apiKey)","type":"invalid_request_error","param":null,"code":"invalid_api_key"}}"#)
        }
        let (store, config) = Self.keyed(Configs.openAI())
        let report = await ConnectionTester(credentials: store, transport: LoopbackRewriteTransport(target: server.baseURL)).test(config)
        #expect(Self.kind(report) == .authentication)
        #expect(report.userMessage.contains("rejected the key"))
        Self.assertSafeMessage(report)
        if case .failed(let error) = report.outcome {
            #expect(!(error.detail ?? "").contains(String(Canary.apiKey.prefix(12))))
            #expect(!(error.detail ?? "").contains(String(Canary.apiKey.suffix(6))))
        }
    }

    @Test func unsupportedModelOpenAIShape() async throws {
        let server = try await FakeHTTPServer { _ in
            .json(404, #"{"error":{"message":"The model `no-such-model` does not exist or you do not have access to it.","type":"invalid_request_error","param":null,"code":"model_not_found"}}"#)
        }
        let (store, config) = Self.keyed(Configs.openAI())
        let report = await ConnectionTester(credentials: store, transport: LoopbackRewriteTransport(target: server.baseURL)).test(config)
        #expect(Self.kind(report) == .unsupportedModel)
        #expect(report.userMessage.contains("model"))
    }

    @Test func unsupportedModelAnthropicShape() async throws {
        let server = try await FakeHTTPServer { _ in
            .json(404, #"{"type":"error","error":{"type":"not_found_error","message":"model: claude-nope"},"request_id":"req_1"}"#)
        }
        let (store, config) = Self.keyed(Configs.anthropic())
        let report = await ConnectionTester(credentials: store, transport: LoopbackRewriteTransport(target: server.baseURL)).test(config)
        #expect(Self.kind(report) == .unsupportedModel)
    }

    @Test func unsupportedDialectWhenThePathDoesNotExist() async throws {
        // An Anthropic adapter pointed at an OpenAI-compatible server: /v1/messages is not there.
        let server = try await FakeHTTPServer { _ in .json(404, #"{"error":"Unexpected endpoint or method. (POST /v1/messages)"}"#) }
        let (store, config) = Self.keyed(Configs.anthropic())
        let report = await ConnectionTester(credentials: store, transport: LoopbackRewriteTransport(target: server.baseURL)).test(config)
        #expect(Self.kind(report) == .unsupportedDialect)
        #expect(report.userMessage.contains("/v1"))
    }

    @Test func missingVersionSegmentIsUnsupportedDialectWithAHint() async throws {
        let server = try await FakeHTTPServer { request in
            request.path == "/v1/chat/completions" ? .json(200, "{}") : .text(404, "Not Found")
        }
        let report = await ConnectionTester(credentials: InMemoryCredentialStore(), transport: URLSessionTransport())
            .test(Configs.generic(server, path: ""))
        #expect(server.requests.first?.path == "/chat/completions")
        #expect(Self.kind(report) == .unsupportedDialect)
        #expect(report.userMessage.contains("many servers expect it to end in /v1"))
    }

    @Test func rateLimitWithRetryAfter() async throws {
        let server = try await FakeHTTPServer { _ in
            .json(429, #"{"type":"error","error":{"type":"rate_limit_error","message":"Number of request tokens has exceeded your per-minute rate limit"}}"#,
                  headers: [("retry-after", "17")])
        }
        let (store, config) = Self.keyed(Configs.anthropic())
        let report = await ConnectionTester(credentials: store, transport: LoopbackRewriteTransport(target: server.baseURL)).test(config)
        #expect(Self.kind(report) == .rateLimited)
        if case .failed(let error) = report.outcome { #expect(error.retryAfter == .seconds(17)) }
        #expect(report.userMessage.contains("about 17 seconds"))
    }

    /// Plan 18.1: provider responses are untrusted. A hostile or broken server's Retry-After must never crash the
    /// parser (an unchecked Double-to-Int64 conversion trapped on huge values) and must never be waited out.
    @Test(arguments: [
        ("99999999999999999999", Optional(RetryAfter.ceiling)), ("9223372036854775807", RetryAfter.ceiling),
        (String(repeating: "9", count: 5_000), RetryAfter.ceiling), ("86401", RetryAfter.ceiling),
        ("Fri, 31 Dec 9999 23:59:59 GMT", RetryAfter.ceiling),
        ("1e300", nil), ("-5", nil), ("nan", nil), ("inf", nil), ("0x10", nil), ("1.5", nil), ("+3", nil),
    ])
    func hostileRetryAfterIsClampedOrIgnoredNeverTrapped(value: String, expected: Duration?) async throws {
        let parsed = RetryAfter.parse(value, now: Date(timeIntervalSince1970: 1_791_590_400))
        #expect(parsed == expected)
        if let parsed { #expect(RetryPolicy().delay(afterAttempt: 1, retryAfter: parsed) == nil, "a clamped value is never waited out") }

        // The real adapter path: a 429 carrying the header, through URLSession, the generic adapter and the classifier.
        let server = try await FakeHTTPServer { _ in
            .json(429, #"{"error":{"message":"slow down","type":"rate_limit_error"}}"#, headers: [("Retry-After", value)])
        }
        let report = await ConnectionTester(credentials: InMemoryCredentialStore(), transport: URLSessionTransport()).test(Configs.generic(server))
        #expect(Self.kind(report) == .rateLimited)
        Self.assertSafeMessage(report)
        if case .failed(let error) = report.outcome { #expect(error.retryAfter == expected) }
        if expected != nil { #expect(report.userMessage.contains("more than an hour")) }
    }

    @Test func validRetryAfterFormsStillParse() {
        let now = Date(timeIntervalSince1970: 1_791_590_400)
        #expect(RetryAfter.parse("0", now: now) == .zero)
        #expect(RetryAfter.parse(" 17 ", now: now) == .seconds(17))
        #expect(RetryAfter.parse("86400", now: now) == .seconds(86_400))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        #expect(RetryAfter.parse(formatter.string(from: now.addingTimeInterval(30)), now: now) == .seconds(30))
        #expect(RetryAfter.parse(formatter.string(from: now.addingTimeInterval(-30)), now: now) == .zero)
    }

    @Test func quotaExhaustedIsNotARateLimit() async throws {
        let server = try await FakeHTTPServer { _ in
            .json(429, #"{"error":{"message":"You exceeded your current quota.","type":"insufficient_quota","param":null,"code":"insufficient_quota"}}"#)
        }
        let (store, config) = Self.keyed(Configs.openAI())
        let report = await ConnectionTester(credentials: store, transport: LoopbackRewriteTransport(target: server.baseURL)).test(config)
        #expect(Self.kind(report) == .quotaExhausted)
    }

    @Test func invalidResponseWhenAPortalReturnsHTML() async throws {
        let server = try await FakeHTTPServer { _ in .text(200, "<html><body>Sign in to Wi-Fi</body></html>", contentType: "text/html") }
        let report = await ConnectionTester(credentials: InMemoryCredentialStore(), transport: URLSessionTransport()).test(Configs.generic(server))
        #expect(Self.kind(report) == .invalidResponse)
    }

    @Test func invalidResponseWhenTheWrongDialectStreams() async throws {
        // A chat-completions stream answered to the Responses adapter: no typed events, no terminal event.
        let server = try await FakeHTTPServer { _ in
            .sse(["data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"OK\"}}]}\n\ndata: [DONE]\n\n"])
        }
        let (store, config) = Self.keyed(Configs.openAI())
        let report = await ConnectionTester(credentials: store, transport: LoopbackRewriteTransport(target: server.baseURL)).test(config)
        #expect(Self.kind(report) == .invalidResponse)
    }

    @Test func serverErrorIsClassified() async throws {
        let server = try await FakeHTTPServer { _ in .json(529, #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#) }
        let (store, config) = Self.keyed(Configs.anthropic())
        let report = await ConnectionTester(credentials: store, transport: LoopbackRewriteTransport(target: server.baseURL)).test(config)
        #expect(Self.kind(report) == .serverError)
    }

    @Test func missingCredentialIsReportedWithoutSending() async throws {
        let server = try await FakeHTTPServer { _ in .json(200, "{}") }
        let report = await ConnectionTester(credentials: InMemoryCredentialStore(), transport: LoopbackRewriteTransport(target: server.baseURL))
            .test(Configs.openAI())
        #expect(Self.kind(report) == .credentialMissing)
        #expect(server.requests.isEmpty)
    }

    @Test func everyFailureKindHasADistinctActionableMessage() {
        var messages = Set<String>()
        for kind in FailureKind.allCases {
            let message = ProviderError(kind: kind, acceptance: .rejected, host: "example.test", httpStatus: 400).userMessage
            #expect(!message.isEmpty)
            #expect(!message.lowercased().contains("ai failed"))
            messages.insert(message)
        }
        #expect(messages.count == FailureKind.allCases.count)
    }
}
