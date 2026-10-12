import Foundation
import G05TestSupport
import Testing
@testable import SylviaAI

/// Live smoke tests against real endpoints: OpenAI, Anthropic, a user's own OpenAI-compatible server or gateway
/// (LM Studio, Hermes, …) and an OpenAI-compatible transcription endpoint. Each runs only when all of its
/// environment variables are set: the explicit opt-in `SYLVIA_LIVE_PROVIDER_TESTS=1` (so a key that happens to be
/// in a shell never causes a paid request during CI), the endpoint's key where it needs one, and the model to test
/// (no model name is assumed). Otherwise the test is reported as skipped with the reason. Keys come only from the
/// environment at test time and are never written anywhere (CLAUDE.md). All of these are pending-human in the G0.5
/// report (Docs/Stage0/device-checklists/G05-AI.md steps 5-8). Only fixed public-domain text and the committed
/// public-domain audio fixture are sent.
///
///   SYLVIA_LIVE_PROVIDER_TESTS=1 OPENAI_API_KEY=… SYLVIA_LIVE_OPENAI_MODEL=<model> swift test --filter LiveProviderTests
///   SYLVIA_LIVE_PROVIDER_TESTS=1 ANTHROPIC_API_KEY=… SYLVIA_LIVE_ANTHROPIC_MODEL=<model> swift test --filter LiveProviderTests
///   SYLVIA_LIVE_PROVIDER_TESTS=1 SYLVIA_LIVE_COMPAT_BASE_URL=http://192.168.1.20:1234/v1 SYLVIA_LIVE_COMPAT_MODEL=<model> \
///     [SYLVIA_LIVE_COMPAT_API_KEY=…] swift test --filter LiveProviderTests
///   SYLVIA_LIVE_PROVIDER_TESTS=1 SYLVIA_LIVE_TRANSCRIPTION_BASE_URL=https://api.openai.com/v1 SYLVIA_LIVE_TRANSCRIPTION_MODEL=<model> \
///     [SYLVIA_LIVE_TRANSCRIPTION_API_KEY=…] [SYLVIA_LIVE_TRANSCRIPTION_TIMESTAMPS=1] swift test --filter LiveProviderTests
///
/// The grounded answer uses the output limit a real question to that configuration gets: the configured maximum output
/// (`SYLVIA_LIVE_MAX_OUTPUT_TOKENS`, as set in provider settings) or the default reserve of 1,024 tokens. A smaller
/// budget would make a model that reasons before answering stop at the limit before any answer text (report F14, F18),
/// and the test would then fail for its own budget rather than the adapter's behaviour.
@Suite("Live provider smoke tests")
struct LiveProviderSmokeTests {
    static let environment = ProcessInfo.processInfo.environment
    static func isSet(_ name: String) -> Bool { !(environment[name] ?? "").isEmpty }
    static var optedIn: Bool { environment["SYLVIA_LIVE_PROVIDER_TESTS"] == "1" }
    static var openAIReady: Bool { optedIn && isSet("OPENAI_API_KEY") && isSet("SYLVIA_LIVE_OPENAI_MODEL") }
    static var anthropicReady: Bool { optedIn && isSet("ANTHROPIC_API_KEY") && isSet("SYLVIA_LIVE_ANTHROPIC_MODEL") }
    static var compatibleReady: Bool { optedIn && isSet("SYLVIA_LIVE_COMPAT_BASE_URL") && isSet("SYLVIA_LIVE_COMPAT_MODEL") }
    static var transcriptionReady: Bool { optedIn && isSet("SYLVIA_LIVE_TRANSCRIPTION_BASE_URL") && isSet("SYLVIA_LIVE_TRANSCRIPTION_MODEL") }

    /// The configured maximum output, when the person running the test set one for this endpoint.
    static var configuredMaxOutputTokens: Int? {
        environment["SYLVIA_LIVE_MAX_OUTPUT_TOKENS"].flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
    }

    /// The grounded question with the output limit real questions to `config` get: its maximum output, or the default
    /// reserve (`ConnectionTester.defaultProbeOutputTokens`, equal to `BuilderSettings.defaultOutputReserveTokens`).
    static func request(for config: ProviderConfig) -> GenerationRequest {
        GenerationRequest(
            system: PromptTemplate.systemText,
            messages: [.init(role: .user, text: PromptTemplate.userMessage(
                question: "What is being described here? Cite the evidence.",
                evidence: [("c1", "source_text", "Walden, Where I Lived", "I went to the woods because I wished to live deliberately, to front only the essential facts of life.")],
                scope: .selectedPassage, coverage: .excerptOnly, history: []))],
            maxOutputTokens: config.maxOutputTokens ?? ConnectionTester.defaultProbeOutputTokens)
    }

    /// A credential store holding the key from `variable`, if that variable is set, bound to `baseURL`'s origin.
    static func store(keyFrom variable: String, for baseURL: URL) throws -> (InMemoryCredentialStore, CredentialRef?) {
        let store = InMemoryCredentialStore()
        guard let key = environment[variable], !key.isEmpty else { return (store, nil) }
        let ref = try #require(CredentialRef(for: baseURL))
        try store.save(Secret(key), for: ref)
        return (store, ref)
    }

    struct LiveResult {
        var text = ""
        var refusal = ""
        var finish: FinishReason?
        var statuses: [GenerationStatus] = []
        var textEvents = 0
        var maxOutputTokens = 0
    }

    static func run(_ config: ProviderConfig, credentials: any CredentialStore) async throws -> LiveResult {
        let provider = HTTPTextGenerationProvider(config: config, credentials: credentials, transport: URLSessionTransport())
        var result = LiveResult()
        result.maxOutputTokens = request(for: config).maxOutputTokens
        for try await event in provider.streamGeneration(request(for: config)) {
            switch event {
            case .text(let delta):
                result.text += delta
                result.textEvents += 1
            case .refusal(let text): result.refusal += text
            case .finished(let reason): result.finish = reason
            case .status(let status): result.statuses.append(status)
            case .usage: break
            }
        }
        return result
    }

    /// Checks what the adapter guarantees and prints what a person records (device checklist steps 5, 6 and 8):
    /// whether the answer streamed, how it finished, its citations, and whether reasoning was withheld. Whether the
    /// model chose to cite is model behaviour, recorded rather than asserted; a citation that does not resolve is an
    /// adapter or prompt failure and fails the test.
    static func expectGroundedAnswer(_ result: LiveResult, label: String, model: String) {
        let resolved = CitationResolver.resolve(result.text, allowlist: ["c1"])
        let streamed = result.statuses.contains(.delivery(streamed: true))
        print("LIVE-\(label) model=\(model) max-output=\(result.maxOutputTokens) finish=\(result.finish.map { "\($0)" } ?? "none") streamed=\(streamed) "
              + "text-events=\(result.textEvents) characters=\(result.text.count) citations=\(resolved.citations.count) unresolved=\(resolved.unresolved.count) "
              + "reasoning-omitted=\(result.statuses.contains(.reasoningOmitted)) refusal=\(!result.refusal.isEmpty) start=\(result.text.prefix(80))")
        if result.finish == .outputLimit {
            // The model used the whole output budget (often on reasoning) before finishing: a configuration matter, not an
            // adapter failure. The checklist (step 6) says to raise the maximum output and run again.
            print("LIVE-\(label) finish=outputLimit at max-output=\(result.maxOutputTokens): set SYLVIA_LIVE_MAX_OUTPUT_TOKENS higher and run again")
        }
        #expect(result.finish == .complete)
        #expect(!result.text.isEmpty)
        #expect(streamed && result.textEvents > 1, "the answer arrived as a stream of deltas")
        #expect(!result.text.contains("<think>"), "provider-internal reasoning never reaches the answer")
        #expect(resolved.unresolved.isEmpty, "every citation resolves to the one supplied passage")
    }

    @Test(.enabled(if: openAIReady, "live OpenAI Responses smoke test skipped: needs SYLVIA_LIVE_PROVIDER_TESTS=1, OPENAI_API_KEY and SYLVIA_LIVE_OPENAI_MODEL"))
    func openAIResponsesStreamsAGroundedAnswer() async throws {
        let model = try #require(Self.environment["SYLVIA_LIVE_OPENAI_MODEL"])
        let (credentials, ref) = try Self.store(keyFrom: "OPENAI_API_KEY", for: ProviderKind.openAIResponses.defaultBaseURL!)
        let config = ProviderConfig(kind: .openAIResponses, displayName: "OpenAI", baseURL: ProviderKind.openAIResponses.defaultBaseURL!,
                                    model: model, credential: ref, maxOutputTokens: Self.configuredMaxOutputTokens)
        Self.expectGroundedAnswer(try await Self.run(config, credentials: credentials), label: "OPENAI", model: model)
    }

    @Test(.enabled(if: anthropicReady, "live Anthropic Messages smoke test skipped: needs SYLVIA_LIVE_PROVIDER_TESTS=1, ANTHROPIC_API_KEY and SYLVIA_LIVE_ANTHROPIC_MODEL"))
    func anthropicMessagesStreamsAGroundedAnswer() async throws {
        let model = try #require(Self.environment["SYLVIA_LIVE_ANTHROPIC_MODEL"])
        let (credentials, ref) = try Self.store(keyFrom: "ANTHROPIC_API_KEY", for: ProviderKind.anthropicMessages.defaultBaseURL!)
        let config = ProviderConfig(kind: .anthropicMessages, displayName: "Anthropic", baseURL: ProviderKind.anthropicMessages.defaultBaseURL!,
                                    model: model, credential: ref, maxOutputTokens: Self.configuredMaxOutputTokens)
        Self.expectGroundedAnswer(try await Self.run(config, credentials: credentials), label: "ANTHROPIC", model: model)
    }

    /// A real local model server or gateway through the generic adapter (device checklist steps 5 and 8).
    /// Cleartext is opted into only when the base URL is http; EndpointPolicy still requires a local IP literal.
    @Test(.enabled(if: compatibleReady, "live OpenAI-compatible endpoint test skipped: needs SYLVIA_LIVE_PROVIDER_TESTS=1, SYLVIA_LIVE_COMPAT_BASE_URL and SYLVIA_LIVE_COMPAT_MODEL"))
    func openAICompatibleEndpointPassesTheConnectionTestAndStreams() async throws {
        let base = try BaseURL.normalize(try #require(Self.environment["SYLVIA_LIVE_COMPAT_BASE_URL"]))
        let model = try #require(Self.environment["SYLVIA_LIVE_COMPAT_MODEL"])
        let (credentials, ref) = try Self.store(keyFrom: "SYLVIA_LIVE_COMPAT_API_KEY", for: base)
        let config = ProviderConfig(kind: .openAICompatibleChat, displayName: "Compatible", baseURL: base, model: model, credential: ref,
                                    capabilities: ProviderCapabilities(streaming: true), maxOutputTokens: Self.configuredMaxOutputTokens,
                                    allowInsecureLocalHTTP: base.scheme == "http")
        let report = await ConnectionTester(credentials: credentials, transport: URLSessionTransport()).test(config)
        print("LIVE-COMPAT \(report.userMessage) reported-model=\(report.reportedModel ?? "-") streamed=\(report.streamed)")
        #expect(report.outcome == .passed, "\(report.userMessage)")
        Self.expectGroundedAnswer(try await Self.run(config, credentials: credentials), label: "COMPAT-ANSWER", model: model)
    }

    /// A real OpenAI-compatible /audio/transcriptions endpoint (device checklist step 7): the capability test with
    /// generated silence, then the committed public-domain LibriVox excerpt.
    @Test(.enabled(if: transcriptionReady, "live transcription test skipped: needs SYLVIA_LIVE_PROVIDER_TESTS=1, SYLVIA_LIVE_TRANSCRIPTION_BASE_URL and SYLVIA_LIVE_TRANSCRIPTION_MODEL"))
    func transcriptionEndpointTranscribesTheFixtureClip() async throws {
        let base = try BaseURL.normalize(try #require(Self.environment["SYLVIA_LIVE_TRANSCRIPTION_BASE_URL"]))
        let model = try #require(Self.environment["SYLVIA_LIVE_TRANSCRIPTION_MODEL"])
        let (credentials, ref) = try Self.store(keyFrom: "SYLVIA_LIVE_TRANSCRIPTION_API_KEY", for: base)
        let config = ProviderConfig(kind: .openAICompatibleTranscription, displayName: "Speech", baseURL: base, model: model, credential: ref,
                                    capabilities: ProviderCapabilities(timestamps: Self.environment["SYLVIA_LIVE_TRANSCRIPTION_TIMESTAMPS"] == "1"),
                                    allowInsecureLocalHTTP: base.scheme == "http")
        let provider = OpenAICompatibleTranscriptionProvider(config: config, credentials: credentials, transport: URLSessionTransport())
        let capability = await SilentWAV.capabilityTest(provider)
        #expect((try? capability.get()) != nil, "capability test: \(capability)")
        let clip = AudioClip(data: try RepoFixtures.data("audio/meditations-02-first150s.mp3"), filename: "clip.mp3",
                             mimeType: "audio/mpeg", durationMs: 150_000)
        let record = try await provider.transcribe(clip)
        let timestamps = config.capabilities.timestamps
        print("LIVE-TRANSCRIPTION host=\(record.host) model=\(record.model) timestamps-requested=\(timestamps) segments=\(record.segments.count) "
              + "discarded-segments=\(record.discardedSegmentCount) last-segment-end-ms=\(record.segments.last?.endMs ?? -1) start=\(record.rawText.prefix(80))")
        #expect(!record.rawText.isEmpty)
        if timestamps {
            #expect(!record.segments.isEmpty, "timing was requested and the endpoint is configured for it")
            #expect(record.segments.allSatisfy { $0.startMs >= 0 && $0.endMs >= $0.startMs && $0.endMs <= 151_000 })
        }
        #expect(record.label == "Machine transcription · may be inaccurate")
    }
}
