import Foundation
import G05TestSupport
import Testing
@testable import SylviaAI

/// Brief item 4 / plan 14.2, 18.1 / T49: provider keys never appear in errors, logs, request bodies, URLs or
/// persisted models. Uses a canary key and searches every output for it and for fragments of it.
@Suite("Credential safety")
struct CredentialSafetyTests {
    static let fragments = [Canary.apiKey, String(Canary.apiKey.prefix(14)), String(Canary.apiKey.suffix(10)), "CANARY"]

    static func assertClean(_ text: String, _ what: String, sourceLocation: SourceLocation = #_sourceLocation) {
        for fragment in fragments {
            #expect(!text.contains(fragment), "\(what) contains a key fragment", sourceLocation: sourceLocation)
        }
    }

    @Test func secretHasNoTextualRepresentation() {
        let secret = Secret(Canary.apiKey)
        Self.assertClean(String(describing: secret), "description")
        Self.assertClean(String(reflecting: secret), "debugDescription")
        Self.assertClean("\(secret)", "interpolation")
        var dumped = ""
        dump(secret, to: &dumped)
        Self.assertClean(dumped, "dump")
        Self.assertClean(String(describing: Mirror(reflecting: secret).children.map(\.value)), "mirror")
        #expect(secret.revealForAuthorizationHeader() == Canary.apiKey)
    }

    @Test func providerConfigAndPacksCarryOnlyACredentialReference() throws {
        let ref = CredentialRef(origin: "https://api.openai.com")
        let config = ProviderConfig(kind: .openAIResponses, displayName: "OpenAI", baseURL: URL(string: "https://api.openai.com/v1")!,
                                    model: "m", credential: ref)
        let json = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
        #expect(json.contains(ref.account.uuidString))
        #expect(json.contains("\"store\":\"keychain\""))
        for forbidden in ["api_key", "apiKey", "secret", "authorization", "bearer"] {
            #expect(!json.lowercased().contains(forbidden.lowercased()), "\(forbidden) in provider config JSON")
        }
    }

    @Test func redactorRemovesFullAndPartialEchoes() {
        let redactor = Redactor(knownSecrets: [Secret(Canary.apiKey)])
        let partial = String(Canary.apiKey.prefix(12)) + "***" + String(Canary.apiKey.suffix(6))
        let inputs = [
            "Incorrect API key provided: \(partial).",
            "Authorization: Bearer \(Canary.apiKey)",
            "{\"x-api-key\": \"\(Canary.anthropicKey)\"}",
            "key=\(Canary.apiKey)&x=1",
            "unrelated sk-live-abcdef0123456789 token",
        ]
        for input in inputs {
            let output = redactor.scrub(input)
            Self.assertClean(output, "scrubbed output")
            #expect(!output.contains("sk-live-abcdef"), "key-shaped tokens are removed even when unknown")
            #expect(!output.contains(String(Canary.anthropicKey.suffix(10))))
        }
        #expect(redactor.scrub(String(repeating: "a", count: 1000)).count <= 301)
    }

    @Test func fullFlowLeaksNothingIntoLogsErrorsOrStoredRecords() async throws {
        let echo = "Incorrect API key provided: \(Canary.apiKey) (\(String(Canary.apiKey.prefix(12)))***)"
        let server = try await FakeHTTPServer { request in
            request.index == 0
                ? .json(401, #"{"error":{"message":"\#(echo)","type":"invalid_request_error","code":"invalid_api_key"}}"#)
                : .sse(["data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"ok [c1]\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"])
        }
        let credentials = InMemoryCredentialStore()
        let ref = try #require(CredentialRef(for: server.baseURL))
        try credentials.save(Secret(Canary.apiKey), for: ref)
        let config = Configs.generic(server, credential: ref)
        let log = CapturingLogSink()
        let directory = TestPacks.temporaryDirectory()
        let coordinator = AskCoordinator(store: try FileAskStore(directory: directory),
                                         providerFactory: { HTTPTextGenerationProvider(config: $0, credentials: credentials, transport: URLSessionTransport(), log: log) },
                                         connectivity: FakeConnectivity(online: true), sleeper: RecordingSleeper(), retry: RetryPolicy(jitter: false), log: log)

        // First question: 401 with the key echoed back.
        let first = TestPacks.make(config: config)
        _ = try await coordinator.createDraft(pack: first, config: config)
        _ = try await coordinator.prepare(first.requestID)
        _ = try await coordinator.grantConsent(first.requestID)
        let failed = try await coordinator.send(first.requestID)
        #expect(failed.state == .failedFinal)
        Self.assertClean(failed.statusPhrase, "status phrase")
        Self.assertClean(String(describing: failed.failure as Any), "failure summary")

        // Second question: success.
        let second = TestPacks.make(question: "And a second question?", config: config)
        _ = try await coordinator.createDraft(pack: second, config: config)
        _ = try await coordinator.prepare(second.requestID)
        let completed = try await coordinator.send(second.requestID)
        #expect(completed.state == .complete)

        // The key went only in the Authorization header of requests to its own origin.
        for request in server.requests {
            #expect(request.headers["authorization"] == "Bearer \(Canary.apiKey)")
            Self.assertClean(request.bodyText, "request body")
            Self.assertClean(request.path, "request path")
        }
        // Logs: no key, and no content (question, evidence, answer).
        for line in log.renderedLines {
            Self.assertClean(line, "log line")
            #expect(!line.contains("deliberately") && !line.contains("second question") && !line.contains("ok [c1]"), "log line has content: \(line)")
        }
        #expect(!log.renderedLines.isEmpty)
        // Persisted records on disk.
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            Self.assertClean(try String(contentsOf: file, encoding: .utf8), "stored record \(file.lastPathComponent)")
        }
    }

    @Test func connectionTestErrorsAreScrubbed() async throws {
        let server = try await FakeHTTPServer { _ in
            .json(403, #"{"type":"error","error":{"type":"permission_error","message":"key \#(Canary.apiKey) lacks access"}}"#)
        }
        let credentials = InMemoryCredentialStore()
        let ref = CredentialRef(origin: "https://api.anthropic.com")
        try credentials.save(Secret(Canary.apiKey), for: ref)
        let log = CapturingLogSink()
        let report = await ConnectionTester(credentials: credentials, transport: LoopbackRewriteTransport(target: server.baseURL), log: log)
            .test(Configs.anthropic(ref))
        guard case .failed(let error) = report.outcome else { Issue.record("expected failure"); return }
        #expect(error.kind == .authentication)
        Self.assertClean("\(error) \(error.detail ?? "") \(error.userMessage) \(report.userMessage)", "connection test error")
        for line in log.renderedLines { Self.assertClean(line, "log line") }
    }

    /// R4-02 (plan 18.1: endpoint credentials are origin-scoped; T31). A key is bound to the origin it was entered for.
    /// When the configuration's base URL is edited to another origin (here a second loopback server on another port),
    /// the key never reaches it: the text path, the connection test (which asks for no consent) and the speech path all
    /// stop before anything leaves, with a message saying to enter the key for this address. An imported configuration
    /// that relabels the reference with the new origin finds no key, because the origin is part of the stored item's
    /// identity too.
    @Test func aStoredKeyNeverReachesAnotherOrigin() async throws {
        let reply = "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"OK\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
        let first = try await FakeHTTPServer { _ in .sse([reply]) }
        let second = try await FakeHTTPServer { request in
            request.path.hasSuffix("/audio/transcriptions") ? .json(200, #"{"text":"should never be sent"}"#) : .sse([reply])
        }
        let store = InMemoryCredentialStore()
        let ref = try #require(CredentialRef(for: first.baseURL))
        try store.save(Secret(Canary.apiKey), for: ref)
        let config = Configs.generic(first, credential: ref)
        #expect(config.credentialMatchesOrigin)
        let own = await collect(HTTPTextGenerationProvider(config: config, credentials: store, transport: URLSessionTransport()).streamGeneration(sampleRequest))
        #expect(own.error == nil && own.finish == .complete)
        #expect(first.requests.first?.headers["authorization"] == "Bearer \(Canary.apiKey)", "the key goes to the origin it was entered for")

        var moved = config
        moved.baseURL = try BaseURL.normalize(second.baseURL.absoluteString + "/v1")
        #expect(!moved.credentialMatchesOrigin)
        let expected = ProviderError(kind: .credentialMissing, acceptance: .notSent, host: "127.0.0.1", detail: ProviderError.credentialForAnotherOrigin)
        #expect(expected.userMessage
                == "The key stored for this provider was entered for a different address, so Sylvia won't send it to 127.0.0.1. Enter the key for this address in provider settings.")
        let text = await collect(HTTPTextGenerationProvider(config: moved, credentials: store, transport: URLSessionTransport()).streamGeneration(sampleRequest))
        #expect(text.error == expected)
        let report = await ConnectionTester(credentials: store, transport: URLSessionTransport()).test(moved)
        #expect(report.outcome == .failed(expected))
        Self.assertClean(report.userMessage, "connection test message")

        var speech = moved
        speech.kind = .openAICompatibleTranscription
        await #expect(throws: expected) {
            try await OpenAICompatibleTranscriptionProvider(config: speech, credentials: store, transport: URLSessionTransport())
                .transcribe(AudioClip(data: SilentWAV.make(), filename: "clip.wav", mimeType: "audio/wav", durationMs: 1_000))
        }

        var relabelled = moved
        relabelled.credential = CredentialRef(account: ref.account, origin: try #require(CredentialRef(for: second.baseURL)).origin)
        #expect(relabelled.credentialMatchesOrigin)
        let imported = await collect(HTTPTextGenerationProvider(config: relabelled, credentials: store, transport: URLSessionTransport()).streamGeneration(sampleRequest))
        #expect(imported.error == ProviderError(kind: .credentialMissing, acceptance: .notSent, host: "127.0.0.1"))

        #expect(second.requests.isEmpty, "nothing, and so no key, reached the second origin")
        #expect(first.requests.count == 1)
    }
}
