import Foundation
import Synchronization

/// Provider-neutral text generation (plan 14.1). Model listing and token counting are optional and are not
/// part of this protocol, so a custom endpoint can be configured without them.
public protocol TextGenerationProvider: Sendable {
    var config: ProviderConfig { get }
    func streamGeneration(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, any Error>
}

/// Builds the dialect-specific HTTP request for a provider-neutral request.
enum DialectRequestBuilder {
    static let anthropicVersion = "2023-06-01"

    static func build(_ request: GenerationRequest, config: ProviderConfig, secret: Secret?) throws -> HTTPRequestSpec {
        var headers = ["Content-Type": "application/json"]
        let body: [String: Any]
        let streaming = config.kind == .openAICompatibleChat ? config.capabilities.streaming : true
        headers["Accept"] = streaming ? "text/event-stream" : "application/json"
        switch config.kind {
        case .openAIResponses:
            if let secret { headers["Authorization"] = "Bearer " + secret.revealForAuthorizationHeader() }
            body = [
                "model": config.model,
                "instructions": request.system,
                "input": request.messages.map { ["role": $0.role.rawValue, "content": $0.text] },
                "stream": true,
                // The Responses API stores responses by default; Sylvia opts out (ADR-0011).
                "store": false,
                "max_output_tokens": request.maxOutputTokens,
            ]
        case .anthropicMessages:
            if let secret { headers["x-api-key"] = secret.revealForAuthorizationHeader() }
            headers["anthropic-version"] = anthropicVersion
            body = [
                "model": config.model,
                "max_tokens": request.maxOutputTokens,
                "system": request.system,
                "messages": request.messages.map { ["role": $0.role.rawValue, "content": $0.text] },
                "stream": true,
            ]
        case .openAICompatibleChat:
            if let secret { headers["Authorization"] = "Bearer " + secret.revealForAuthorizationHeader() }
            var messages: [[String: String]] = [["role": "system", "content": request.system]]
            messages += request.messages.map { ["role": $0.role.rawValue, "content": $0.text] }
            var chat: [String: Any] = [
                "model": config.model,
                "messages": messages,
                "stream": streaming,
                // Widely supported by compatible servers; OpenAI's own API prefers max_completion_tokens.
                "max_tokens": request.maxOutputTokens,
            ]
            if streaming && config.capabilities.streamUsage { chat["stream_options"] = ["include_usage": true] }
            body = chat
        case .openAICompatibleTranscription:
            throw ProviderError(kind: .unsupportedDialect, acceptance: .notSent, host: config.baseURL.host() ?? "",
                                detail: "transcription endpoint used for text generation")
        }
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let timeout = TimeInterval(config.requestTimeoutMs ?? 60_000) / 1000
        return HTTPRequestSpec(url: config.endpointURL, headers: headers, body: data, timeout: timeout)
    }
}

/// Bounds on one response body at the transport level (plan 14.5). The SSE parser already bounds each line and
/// event; these bound the whole body and its duration, so a server that streams without end (including one that sends
/// only keepalive comments, which never reach the coordinator as events) is stopped. URLRequest's timeout is an idle
/// timeout and does not do this.
public struct StreamLimits: Sendable, Equatable {
    /// Body bytes accepted per requested output token. Streaming formats wrap each token or two in a JSON event of
    /// roughly 100-300 bytes, so 1 KiB per token is generous for any honest server.
    public var bytesPerOutputToken: Int
    public var minimumBytes: Int
    /// Wall-clock limit from the start of the request to the end of the body.
    public var maxDuration: Duration

    public init(bytesPerOutputToken: Int = 1_024, minimumBytes: Int = 4 << 20, maxDuration: Duration = .seconds(600)) {
        self.bytesPerOutputToken = bytesPerOutputToken
        self.minimumBytes = minimumBytes
        self.maxDuration = maxDuration
    }

    public func maxBytes(forOutputTokens tokens: Int) -> Int {
        let (product, overflow) = max(0, tokens).multipliedReportingOverflow(by: bytesPerOutputToken)
        return max(minimumBytes, overflow ? Int.max : product)
    }
}

/// One adapter type for all three text dialects; the dialect selects the request builder and stream decoder.
public struct HTTPTextGenerationProvider: TextGenerationProvider {
    public let config: ProviderConfig
    let credentials: any CredentialStore
    let transport: any HTTPTransport
    let log: any AILogSink
    let inspector: any NetworkPathInspector
    let limits: StreamLimits

    public init(config: ProviderConfig, credentials: any CredentialStore, transport: any HTTPTransport,
                log: any AILogSink = NullLogSink(), inspector: any NetworkPathInspector = SystemNetworkPathInspector(),
                limits: StreamLimits = StreamLimits()) {
        self.config = config
        self.credentials = credentials
        self.transport = transport
        self.log = log
        self.inspector = inspector
        self.limits = limits
    }

    public func streamGeneration(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, any Error> {
        let config = config, credentials = credentials, transport = transport, log = log, inspector = inspector, limits = limits
        return AsyncThrowingStream { continuation in
            // Wall-clock limit for the whole request (plan 14.5). The checks in `run` act when bytes arrive; this
            // watchdog also ends a response that delivers nothing to Sylvia while the connection stays busy (for
            // example a body trickled below URLSession's content-sniffing threshold, which never trips the idle
            // timeout). It cancels the work and reports the time limit.
            let timedOut = Mutex(false)
            let task = Task {
                do {
                    try await Self.run(request, config: config, credentials: credentials, transport: transport,
                                       log: log, inspector: inspector, limits: limits) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    if timedOut.withLock({ $0 }) {
                        continuation.finish(throwing: ProviderError(kind: .responseTimeLimit, acceptance: .uncertain,
                                                                    host: config.baseURL.host() ?? "", detail: "request still running at the time limit"))
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
            let watchdog = Task {
                try await Task.sleep(for: limits.maxDuration)
                timedOut.withLock { $0 = true }
                task.cancel()
            }
            continuation.onTermination = { _ in
                task.cancel()
                watchdog.cancel()
            }
        }
    }

    static func run(_ request: GenerationRequest, config: ProviderConfig, credentials: any CredentialStore,
                    transport: any HTTPTransport, log: any AILogSink, inspector: any NetworkPathInspector,
                    limits: StreamLimits = StreamLimits(), emit: (GenerationEvent) -> Void) async throws {
        let deadline = ContinuousClock.now + limits.maxDuration
        let maxBytes = limits.maxBytes(forOutputTokens: request.maxOutputTokens)
        let assessment: EndpointAssessment
        do { assessment = try EndpointPolicy.assess(config) } catch {
            throw ProviderError(kind: .insecureEndpointRejected, acceptance: .notSent, host: config.baseURL.host() ?? "",
                                detail: error.userMessage)
        }
        let host = assessment.origin.host
        let secret = try Self.secret(for: config, origin: assessment.origin, credentials: credentials)
        let redactor = Redactor(knownSecrets: secret.map { [$0] } ?? [])
        let spec = try DialectRequestBuilder.build(request, config: config, secret: secret)
        log.record(AILogEvent("ai.request.start", ["kind": config.kind.rawValue, "host": host,
                                                    "classification": assessment.effectiveClassification.rawValue]))
        let response: HTTPStreamResponse
        do {
            response = try await transport.send(spec)
        } catch {
            let classified = ErrorClassifier.classify(error, host: host, bodyMayHaveBeenSent: true, inspector: inspector)
            log.record(AILogEvent("ai.request.failed", ["kind": classified.kind.rawValue, "host": host]))
            throw classified
        }
        guard (200..<300).contains(response.status) else {
            let body = await response.collectBody()
            let classified = ErrorClassifier.classifyHTTP(status: response.status, headers: response.headers, body: body,
                                                          host: host, redactor: redactor,
                                                          classification: assessment.effectiveClassification)
            log.record(AILogEvent("ai.request.failed", ["kind": classified.kind.rawValue, "host": host,
                                                         "http": String(response.status)]))
            throw classified
        }
        let contentType = response.headers["content-type"]?.lowercased() ?? ""
        do {
            if config.kind == .openAICompatibleChat && contentType.contains("application/json") {
                // Non-streaming endpoint, or a server that ignored stream: true.
                emit(.status(.delivery(streamed: false)))
                let (body, end) = await response.readBody(limit: min(maxBytes, 8 << 20), deadline: deadline)
                try Self.requireComplete(end, host: host)
                var decoder = ChatCompletionsDecoder(host: host, redactor: redactor)
                for event in try decoder.decodeNonStreaming(body) { emit(event) }
            } else {
                guard contentType.contains("text/event-stream") else {
                    throw ProviderError(kind: .invalidResponse, acceptance: .uncertain, host: host,
                                        detail: "unexpected content type \(redactor.scrub(contentType))")
                }
                emit(.status(.delivery(streamed: true)))
                try await decodeStream(response.body, kind: config.kind, host: host, redactor: redactor, maxBytes: maxBytes,
                                       deadline: deadline, emit: emit)
            }
        } catch {
            let classified = ErrorClassifier.classify(error, host: host, bodyMayHaveBeenSent: true, inspector: inspector)
            log.record(AILogEvent("ai.stream.failed", ["kind": classified.kind.rawValue, "host": host]))
            throw classified
        }
        log.record(AILogEvent("ai.stream.end", ["host": host]))
    }

    /// The key for a request to `origin`, read only when the configuration's credential was entered for that origin
    /// (plan 18.1). A key bound to another origin is never read or sent: the request stops before it leaves.
    static func secret(for config: ProviderConfig, origin: Origin, credentials: any CredentialStore) throws(ProviderError) -> Secret? {
        guard let ref = config.credential else { return nil }
        guard ref.origin == origin.description else {
            throw ProviderError(kind: .credentialMissing, acceptance: .notSent, host: origin.host, detail: ProviderError.credentialForAnotherOrigin)
        }
        do { return try credentials.secret(for: ref) } catch {
            throw ProviderError(kind: .credentialMissing, acceptance: .notSent, host: origin.host)
        }
    }

    /// Turns a bounded body read that hit a limit into the classified failure (plan 14.5).
    static func requireComplete(_ end: HTTPStreamResponse.BodyEnd, host: String) throws(ProviderError) {
        switch end {
        case .complete: return
        case .sizeLimit: throw ProviderError(kind: .responseSizeLimit, acceptance: .uncertain, host: host, detail: "response body over the size limit")
        case .timeLimit: throw ProviderError(kind: .responseTimeLimit, acceptance: .uncertain, host: host, detail: "response body still arriving at the time limit")
        }
    }

    static func decodeStream(_ body: AsyncThrowingStream<Data, any Error>, kind: ProviderKind, host: String,
                             redactor: Redactor, maxBytes: Int = StreamLimits().minimumBytes,
                             deadline: ContinuousClock.Instant = .now + StreamLimits().maxDuration,
                             emit: (GenerationEvent) -> Void) async throws {
        var received = 0
        var parser = SSEParser()
        var decoder: any StreamDecoder = switch kind {
        case .openAIResponses: OpenAIResponsesDecoder(host: host, redactor: redactor)
        case .anthropicMessages: AnthropicMessagesDecoder(host: host, redactor: redactor)
        default: ChatCompletionsDecoder(host: host, redactor: redactor)
        }
        do {
            for try await chunk in body {
                received += chunk.count
                if received > maxBytes {
                    throw ProviderError(kind: .responseSizeLimit, acceptance: .uncertain, host: host, detail: "body over \(maxBytes) bytes")
                }
                if ContinuousClock.now > deadline {
                    throw ProviderError(kind: .responseTimeLimit, acceptance: .uncertain, host: host, detail: "body still arriving at the time limit")
                }
                let events: [SSEEvent]
                do { events = try parser.feed(chunk) } catch {
                    throw ProviderError(kind: .invalidResponse, acceptance: .uncertain, host: host, detail: "\(error)")
                }
                for event in events {
                    for generationEvent in try decoder.decode(event) { emit(generationEvent) }
                }
                if decoder.hasTerminated { return }
            }
        } catch let error as ProviderError {
            throw error
        } catch {
            // Transport ended abnormally mid-stream: acceptance is uncertain.
            let classified = ErrorClassifier.classify(error, host: host, bodyMayHaveBeenSent: true)
            throw classified
        }
        _ = parser.finish()
        for generationEvent in try decoder.finish() { emit(generationEvent) }
    }
}
