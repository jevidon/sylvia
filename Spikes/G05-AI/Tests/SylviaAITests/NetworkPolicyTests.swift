import Foundation
import G05TestSupport
import Testing
@testable import SylviaAI

/// Brief item 4 and plan 14.1/14.3: base URL normalization, endpoint classification, the cleartext rule and
/// origin-scoped credentials with cross-origin redirects blocked (T31).
@Suite("Network policy")
struct NetworkPolicyTests {
    @Test(arguments: [
        ("http://127.0.0.1:1234/v1", "http://127.0.0.1:1234/v1/chat/completions"),
        ("http://127.0.0.1:1234/v1/", "http://127.0.0.1:1234/v1/chat/completions"),
        ("http://127.0.0.1:1234/v1/chat/completions", "http://127.0.0.1:1234/v1/chat/completions"),
        ("http://127.0.0.1:1234/v1/v1", "http://127.0.0.1:1234/v1/chat/completions"),
        ("http://127.0.0.1:1234/v1/v1/chat/completions/", "http://127.0.0.1:1234/v1/chat/completions"),
        ("  HTTPS://Gateway.Example.COM:443/api/v1  ", "https://gateway.example.com/api/v1/chat/completions"),
        ("https://gateway.example.com", "https://gateway.example.com/chat/completions"),
        ("https://gateway.example.com/openai/v2/", "https://gateway.example.com/openai/v2/chat/completions"),
        ("http://[::1]:8080/v1", "http://[::1]:8080/v1/chat/completions"),
    ])
    func baseURLNormalizationNeverProducesDoubledVersion(input: String, expected: String) throws {
        let base = try BaseURL.normalize(input)
        let endpoint = BaseURL.join(base, ProviderKind.openAICompatibleChat.endpointPath).absoluteString
        #expect(endpoint == expected)
        #expect(!endpoint.contains("/v1/v1"))
        #expect(!endpoint.contains("//chat"))
    }

    @Test func firstPartyDefaultsJoinCorrectly() {
        #expect(Configs.openAI().endpointURL.absoluteString == "https://api.openai.com/v1/responses")
        #expect(Configs.anthropic().endpointURL.absoluteString == "https://api.anthropic.com/v1/messages")
        let transcription = BaseURL.join(try! BaseURL.normalize("https://stt.example/v1/audio/transcriptions"), ProviderKind.openAICompatibleTranscription.endpointPath)
        #expect(transcription.absoluteString == "https://stt.example/v1/audio/transcriptions")
    }

    @Test func baseURLRejectsCredentialsQueriesAndOtherSchemes() {
        #expect(throws: BaseURLError.containsCredentials) { try BaseURL.normalize("https://user:pass@host.example/v1") }
        #expect(throws: BaseURLError.containsQueryOrFragment) { try BaseURL.normalize("https://host.example/v1?key=sk-abc") }
        #expect(throws: BaseURLError.containsQueryOrFragment) { try BaseURL.normalize("https://host.example/v1#frag") }
        #expect(throws: BaseURLError.unsupportedScheme("ftp")) { try BaseURL.normalize("ftp://host.example/v1") }
        #expect(throws: BaseURLError.empty) { try BaseURL.normalize("   ") }
    }

    @Test func classificationOfHosts() {
        let cases: [(String, EndpointClassification)] = [
            ("api.openai.com", .hosted), ("api.anthropic.com", .hosted),
            ("127.0.0.1", .local), ("10.0.0.5", .local), ("172.16.0.1", .local), ("172.31.255.255", .local), ("192.168.1.20", .local),
            ("169.254.10.1", .local), ("::1", .local), ("fd12:3456::1", .local), ("fe80::1", .local),
            // Names are never "local", even when they look it: resolution can be spoofed or rebound.
            ("localhost", .userManaged), ("studio.local", .userManaged), ("mac-mini", .userManaged),
            // Tailscale CGNAT and MagicDNS are routes, not proof of a local, encrypted hop (plan 14.3).
            ("100.101.102.103", .userManaged), ("box.tail1234.ts.net", .userManaged),
            ("172.32.0.1", .userManaged), ("8.8.8.8", .userManaged), ("gateway.example.com", .userManaged),
            ("0177.0.0.1", .userManaged), ("127.1", .userManaged),
        ]
        for (host, expected) in cases {
            #expect(EndpointPolicy.automaticClassification(host: host, kind: .openAICompatibleChat) == expected, "\(host)")
        }
    }

    static func config(_ url: String, allowHTTP: Bool = true, declared: EndpointClassification? = nil, kind: ProviderKind = .openAICompatibleChat) -> ProviderConfig {
        ProviderConfig(kind: kind, displayName: "x", baseURL: URL(string: url)!, model: "m", credential: nil,
                       declaredClassification: declared, allowInsecureLocalHTTP: allowHTTP)
    }

    @Test func cleartextRule() throws {
        // Allowed: explicit opt-in and a local IP literal.
        #expect(try EndpointPolicy.assess(Self.config("http://192.168.1.20:1234/v1")).usesCleartext)
        #expect(try EndpointPolicy.assess(Self.config("http://127.0.0.1:1234/v1")).effectiveClassification == .local)
        // Rejected: no opt-in.
        #expect(throws: EndpointPolicyViolation.self) { try EndpointPolicy.assess(Self.config("http://192.168.1.20:1234/v1", allowHTTP: false)) }
        // Rejected: names, including localhost and .local; CGNAT; public addresses.
        for url in ["http://localhost:1234/v1", "http://studio.local:1234/v1", "http://100.64.1.2:1234/v1", "http://8.8.8.8/v1", "http://gateway.example.com/v1"] {
            #expect(throws: EndpointPolicyViolation.self, "\(url)") { try EndpointPolicy.assess(Self.config(url)) }
        }
        // Rejected: a local address the user declared as hosted or user-managed.
        #expect(throws: EndpointPolicyViolation.self) { try EndpointPolicy.assess(Self.config("http://192.168.1.20/v1", declared: .hosted)) }
        // First-party adapters are HTTPS only.
        #expect(throws: EndpointPolicyViolation.hostedProviderRequiresHTTPS) {
            try EndpointPolicy.assess(Self.config("http://127.0.0.1:9/v1", kind: .openAIResponses))
        }
    }

    @Test func declaredClassificationCanBroadenButNeverNarrow() throws {
        #expect(try EndpointPolicy.assess(Self.config("https://gateway.example.com/v1", declared: .hosted)).effectiveClassification == .hosted)
        #expect(try EndpointPolicy.assess(Self.config("https://gateway.example.com/v1", declared: .local)).effectiveClassification == .userManaged)
        #expect(try EndpointPolicy.assess(Self.config("https://api.openai.com/v1", declared: .local, kind: .openAIResponses)).effectiveClassification == .hosted)
    }

    @Test func providerRefusesToSendToARejectedCleartextEndpoint() async throws {
        let server = try await FakeHTTPServer { _ in .json(200, "{}") }
        var config = Configs.generic(server)
        config.allowInsecureLocalHTTP = false
        let outcome = await collect(HTTPTextGenerationProvider(config: config, credentials: InMemoryCredentialStore(), transport: URLSessionTransport())
            .streamGeneration(sampleRequest))
        #expect(outcome.error?.kind == .insecureEndpointRejected)
        #expect(outcome.error?.acceptance == .notSent)
        #expect(server.requests.isEmpty)
    }

    @Test func crossOriginRedirectIsBlockedAndTheKeyNeverReachesTheTarget() async throws {
        let target = try await FakeHTTPServer { _ in
            .sse(["data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"stolen\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"])
        }
        let origin = try await FakeHTTPServer { _ in .redirect(to: target.url("/v1/chat/completions").absoluteString, status: 307) }
        let store = InMemoryCredentialStore()
        let ref = try #require(CredentialRef(for: origin.baseURL))
        try store.save(Secret(Canary.apiKey), for: ref)
        let outcome = await collect(HTTPTextGenerationProvider(config: Configs.generic(origin, credential: ref), credentials: store,
                                                               transport: URLSessionTransport()).streamGeneration(sampleRequest))
        #expect(outcome.error?.kind == .redirectBlocked)
        #expect(outcome.error?.detail == "http://127.0.0.1:\(target.port)")
        #expect(outcome.text.isEmpty)
        #expect(target.requests.isEmpty, "the redirect target received nothing: no body, no key")
        #expect(origin.requests.count == 1)
    }

    @Test(arguments: [301, 302, 303, 307, 308])
    func everyRedirectStatusToAnotherOriginIsBlocked(status: Int) async throws {
        let target = try await FakeHTTPServer { _ in .json(200, "{}") }
        let origin = try await FakeHTTPServer { _ in .redirect(to: target.url("/v1/chat/completions").absoluteString, status: status) }
        let outcome = await collect(HTTPTextGenerationProvider(config: Configs.generic(origin), credentials: InMemoryCredentialStore(),
                                                               transport: URLSessionTransport()).streamGeneration(sampleRequest))
        #expect(outcome.error?.kind == .redirectBlocked)
        #expect(target.requests.isEmpty)
    }

    @Test func redirectFromAFirstPartyHostToLoopbackIsBlocked() async throws {
        // A hosted origin redirecting to a local address must not inherit trust or the key.
        let local = try await FakeHTTPServer { _ in .json(200, "{}") }
        let hosted = try await FakeHTTPServer { _ in .redirect(to: local.url("/v1/responses").absoluteString) }
        let store = InMemoryCredentialStore()
        let ref = CredentialRef(origin: "https://api.openai.com")
        try store.save(Secret(Canary.apiKey), for: ref)
        let outcome = await collect(HTTPTextGenerationProvider(config: Configs.openAI(ref), credentials: store,
                                                               transport: LoopbackRewriteTransport(target: hosted.baseURL)).streamGeneration(sampleRequest))
        #expect(outcome.error?.kind == .redirectBlocked)
        #expect(local.requests.isEmpty)
    }

    @Test func sameOriginRedirectIsFollowed() async throws {
        let server = try await FakeHTTPServer { request in
            if request.path == "/old/chat/completions" { return .redirect(to: "/v1/chat/completions", status: 308) }
            return .sse(["data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"moved\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"])
        }
        let outcome = await collect(HTTPTextGenerationProvider(config: Configs.generic(server, path: "/old"), credentials: InMemoryCredentialStore(),
                                                               transport: URLSessionTransport()).streamGeneration(sampleRequest))
        #expect(outcome.text == "moved")
        #expect(server.requests.map(\.path) == ["/old/chat/completions", "/v1/chat/completions"])
    }
}
