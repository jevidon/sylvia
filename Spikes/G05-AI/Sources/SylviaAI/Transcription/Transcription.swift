import Foundation

/// A bounded local audio clip (a retained excerpt, never the source audiobook; plan 10.4).
public struct AudioClip: Sendable, Equatable {
    public var clipID: UUID
    public var data: Data
    public var filename: String
    public var mimeType: String
    public var durationMs: Int

    public init(clipID: UUID = UUID(), data: Data, filename: String, mimeType: String, durationMs: Int) {
        self.clipID = clipID
        self.data = data
        self.filename = filename
        self.mimeType = mimeType
        self.durationMs = durationMs
    }
}

public struct TranscriptSegment: Codable, Sendable, Equatable {
    public var startMs: Int
    public var endMs: Int
    public var text: String

    enum CodingKeys: String, CodingKey {
        case startMs = "start_ms"
        case endMs = "end_ms"
        case text
    }
}

/// A machine transcript with provenance (plan 10.4: raw transcript, provider/model, timestamps and user
/// corrections preserved separately; labelled as potentially inaccurate).
public struct TranscriptRecord: Codable, Sendable, Equatable {
    public static let label = "Machine transcription · may be inaccurate"

    public var clipID: UUID
    public var rawText: String
    public var segments: [TranscriptSegment]
    public var language: String?
    public var providerKind: ProviderKind
    public var host: String
    public var model: String
    public var createdAt: Date
    /// The user's corrected wording, kept apart from the raw machine text.
    public var correctedText: String?
    public var label: String = TranscriptRecord.label
    /// Segments the server sent with unusable timing (not finite, negative, backwards or past the clip); dropped.
    public var discardedSegmentCount: Int = 0

    public init(clipID: UUID, rawText: String, segments: [TranscriptSegment], language: String?, providerKind: ProviderKind,
                host: String, model: String, createdAt: Date, correctedText: String?, discardedSegmentCount: Int = 0) {
        self.clipID = clipID
        self.rawText = rawText
        self.segments = segments
        self.language = language
        self.providerKind = providerKind
        self.host = host
        self.model = model
        self.createdAt = createdAt
        self.correctedText = correctedText
        self.discardedSegmentCount = discardedSegmentCount
    }

    enum CodingKeys: String, CodingKey {
        case clipID = "clip_id"
        case rawText = "raw_text"
        case segments, language
        case providerKind = "provider_kind"
        case host, model
        case createdAt = "created_at"
        case correctedText = "corrected_text"
        case label
        case discardedSegmentCount = "discarded_segment_count"
    }
}

public struct TranscriptionLimits: Sendable, Equatable {
    /// OpenAI documents a 25 MB upload limit; other endpoints are configured, not assumed.
    public var maxBytes: Int
    public var maxDurationMs: Int
    /// Largest transcription response accepted. A five-minute clip's verbose JSON is tens of kilobytes.
    public var maxResponseBytes: Int
    /// Longest Sylvia keeps reading a response body once it has started.
    public var maxResponseDuration: Duration

    public init(maxBytes: Int = 25_000_000, maxDurationMs: Int = 5 * 60_000, maxResponseBytes: Int = 4 << 20,
                maxResponseDuration: Duration = .seconds(300)) {
        self.maxBytes = maxBytes
        self.maxDurationMs = maxDurationMs
        self.maxResponseBytes = maxResponseBytes
        self.maxResponseDuration = maxResponseDuration
    }
}

/// Speech-to-text, separate from text generation (plan 14.1).
public protocol SpeechTranscriptionProvider: Sendable {
    var config: ProviderConfig { get }
    func transcribe(_ clip: AudioClip) async throws -> TranscriptRecord
}

/// OpenAI-compatible `POST {base}/audio/transcriptions` (multipart/form-data). Requests segment timing with
/// `response_format=verbose_json` and `timestamp_granularities[]=segment` only when the endpoint is configured
/// with the timestamps capability; otherwise asks for `json` (text only). Timing is converted to milliseconds.
public struct OpenAICompatibleTranscriptionProvider: SpeechTranscriptionProvider {
    public let config: ProviderConfig
    let credentials: any CredentialStore
    let transport: any HTTPTransport
    let limits: TranscriptionLimits
    let clock: any AIClock

    public init(config: ProviderConfig, credentials: any CredentialStore, transport: any HTTPTransport,
                limits: TranscriptionLimits = TranscriptionLimits(), clock: any AIClock = SystemClock()) {
        self.config = config
        self.credentials = credentials
        self.transport = transport
        self.limits = limits
        self.clock = clock
    }

    public func transcribe(_ clip: AudioClip) async throws -> TranscriptRecord {
        // A text-chat endpoint is not assumed to accept audio (plan 10.4): only a transcription configuration is used.
        guard config.kind == .openAICompatibleTranscription else {
            throw ProviderError(kind: .unsupportedDialect, acceptance: .notSent, host: config.baseURL.host() ?? "",
                                detail: "\(config.kind.rawValue) endpoint used for transcription")
        }
        let assessment: EndpointAssessment
        do { assessment = try EndpointPolicy.assess(config) } catch {
            throw ProviderError(kind: .insecureEndpointRejected, acceptance: .notSent, host: config.baseURL.host() ?? "", detail: error.userMessage)
        }
        let host = assessment.origin.host
        guard clip.data.count <= limits.maxBytes, clip.durationMs <= limits.maxDurationMs else {
            throw ProviderError(kind: .badRequest, acceptance: .notSent, host: host, detail: "clip exceeds the configured size or duration limit")
        }
        let secret = try HTTPTextGenerationProvider.secret(for: config, origin: assessment.origin, credentials: credentials)
        var form = MultipartForm()
        form.field("model", config.model)
        form.field("response_format", config.capabilities.timestamps ? "verbose_json" : "json")
        if config.capabilities.timestamps { form.field("timestamp_granularities[]", "segment") }
        form.file("file", filename: clip.filename, contentType: clip.mimeType, data: clip.data)
        var headers = ["Content-Type": form.contentType, "Accept": "application/json"]
        if let secret { headers["Authorization"] = "Bearer " + secret.revealForAuthorizationHeader() }
        let spec = HTTPRequestSpec(url: BaseURL.join(config.baseURL, ProviderKind.openAICompatibleTranscription.endpointPath),
                                   headers: headers, body: form.body(), timeout: TimeInterval(config.requestTimeoutMs ?? 120_000) / 1000)
        let redactor = Redactor(knownSecrets: secret.map { [$0] } ?? [])
        let response: HTTPStreamResponse
        do { response = try await transport.send(spec) } catch {
            throw ErrorClassifier.classify(error, host: host, bodyMayHaveBeenSent: true)
        }
        guard (200..<300).contains(response.status) else {
            let body = await response.collectBody()
            throw ErrorClassifier.classifyHTTP(status: response.status, headers: response.headers, body: body, host: host, redactor: redactor,
                                               classification: assessment.effectiveClassification)
        }
        // A transcript of a clip within the upload limits is small; a larger or endless body is refused (plan 14.5).
        let (body, end) = await response.readBody(limit: limits.maxResponseBytes, deadline: .now + limits.maxResponseDuration)
        try HTTPTextGenerationProvider.requireComplete(end, host: host)
        guard let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any], let text = object["text"] as? String else {
            throw ProviderError(kind: .invalidResponse, acceptance: .uncertain, host: host, detail: "transcription body has no text field")
        }
        let rawSegments = object["segments"] as? [[String: Any]] ?? []
        let segments = rawSegments.compactMap { Self.segment($0, clipDurationMs: clip.durationMs) }
        return TranscriptRecord(clipID: clip.clipID, rawText: text, segments: segments, language: object["language"] as? String,
                                providerKind: config.kind, host: host, model: config.model, createdAt: clock.now(), correctedText: nil,
                                discardedSegmentCount: rawSegments.count - segments.count)
    }

    /// Timing the server reports beyond the clip by more than this is not trusted.
    static let segmentToleranceMs = 1_000

    /// Converts one server segment (seconds) to milliseconds. Times come from an untrusted server, so a segment whose
    /// start or end is not a finite number, is negative, runs backwards or lies past the clip (plus a small tolerance)
    /// is dropped and counted, never converted unchecked.
    static func segment(_ segment: [String: Any], clipDurationMs: Int) -> TranscriptSegment? {
        guard let start = (segment["start"] as? NSNumber)?.doubleValue, let end = (segment["end"] as? NSNumber)?.doubleValue,
              let text = segment["text"] as? String, start.isFinite, end.isFinite, start >= 0, end >= start else { return nil }
        let limitMs = Double(max(0, clipDurationMs)) + Double(segmentToleranceMs)
        let startMs = (start * 1000).rounded(), endMs = (end * 1000).rounded()
        guard endMs <= limitMs, let startValue = Int(exactly: startMs), let endValue = Int(exactly: endMs) else { return nil }
        return TranscriptSegment(startMs: startValue, endMs: endValue, text: text)
    }
}

/// multipart/form-data encoder (RFC 7578).
public struct MultipartForm: Sendable {
    public let boundary: String
    private var parts: [Data] = []

    public init(boundary: String = "sylvia-\(UUID().uuidString)") { self.boundary = boundary }

    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    static func quoted(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "%22")
            .replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
    }

    public mutating func field(_ name: String, _ value: String) {
        parts.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(Self.quoted(name))\"\r\n\r\n\(value)\r\n".utf8))
    }

    public mutating func file(_ name: String, filename: String, contentType: String, data: Data) {
        var part = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(Self.quoted(name))\"; filename=\"\(Self.quoted(filename))\"\r\nContent-Type: \(contentType)\r\n\r\n".utf8)
        part.append(data)
        part.append(Data("\r\n".utf8))
        parts.append(part)
    }

    public func body() -> Data {
        var data = Data()
        parts.forEach { data.append($0) }
        data.append(Data("--\(boundary)--\r\n".utf8))
        return data
    }
}

/// When a transcription request made offline is sent (plan 10.4).
public enum TranscriptionQueuePolicy: String, Codable, Sendable {
    /// Default: the draft waits until the user sends it.
    case manual
    /// Opt-in: send automatically when connectivity returns.
    case sendWhenOnline = "send_when_online"
}

/// Why a transcription request was not sent again.
public enum TranscriptionError: Error, Equatable, Sendable {
    /// The last upload of this clip may have reached the server and been processed (and billed), so it is sent again
    /// only when the user confirms (`send(_:userConfirmedResend:)`), as for an uncertain text generation (plan 14.4).
    case resendNeedsConfirmation
}

public struct TranscriptionJob: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        /// No speech service configured: the capture detail offers these actions instead.
        case notConfigured(actions: [String])
        case awaitingAudioConsent(Disclosure)
        /// Saved on this device, not sent.
        case queuedOffline
        case sending
        case complete(TranscriptRecord)
        /// `resendNeedsConfirmation` is true when the upload may have reached the server and been processed (its
        /// acceptance is uncertain): sending it again needs the user's confirmation.
        case failed(kind: FailureKind, message: String, resendNeedsConfirmation: Bool)
    }

    public var clip: AudioClip
    public var state: State
}

/// A transcription job as stored on this device: the clip's metadata (its bytes are stored beside it), the
/// configuration it is for (no secret: a credential reference only) and its state. A pending audio-consent disclosure
/// is not stored; it is rebuilt from the configuration and the stored consent after a relaunch.
public struct StoredTranscriptionJob: Codable, Sendable, Equatable {
    public enum State: Codable, Sendable, Equatable {
        case awaitingAudioConsent
        case queuedOffline
        case sending
        case complete(TranscriptRecord)
        case failed(kind: FailureKind, message: String, resendNeedsConfirmation: Bool)
    }

    public var clipID: UUID
    public var filename: String
    public var mimeType: String
    public var durationMs: Int
    public var config: ProviderConfig
    public var state: State
    public var createdAt: Date
    public var updatedAt: Date

    public init(clipID: UUID, filename: String, mimeType: String, durationMs: Int, config: ProviderConfig, state: State,
                createdAt: Date, updatedAt: Date) {
        self.clipID = clipID
        self.filename = filename
        self.mimeType = mimeType
        self.durationMs = durationMs
        self.config = config
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case clipID = "clip_id"
        case filename
        case mimeType = "mime_type"
        case durationMs = "duration_ms"
        case config, state
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Durable storage for the transcription queue and the audio consent it was granted under (plan 10.4: "Queue a local
/// draft when offline"; a queued clip must survive a relaunch and is sent only under the user's policy).
public protocol TranscriptionQueueStore: Sendable {
    /// Writes the job; the clip's bytes are written with the first save of that clip and never rewritten.
    func save(_ job: StoredTranscriptionJob, clipData: Data) throws
    /// Every stored job with its clip's bytes, oldest first.
    func loadAll() throws -> [(job: StoredTranscriptionJob, clipData: Data)]
    func saveConsent(_ ledger: ConsentLedger) throws
    /// The stored audio consent, or an empty ledger when none was ever granted.
    func loadConsent() throws -> ConsentLedger
}

/// One JSON file per job and the clip's bytes beside it, written atomically (the clip before the job, so a stored job
/// never names a missing clip), with complete-until-first-authentication protection on iOS like the spike's ask store.
/// A stand-in: the production store follows the persistence decision from G0.5 recovery (report Q7).
public struct FileTranscriptionQueueStore: TranscriptionQueueStore {
    public let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func jobURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).job.json") }
    func clipURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).clip") }
    var consentURL: URL { directory.appendingPathComponent("audio-consent.json") }

    static func write(_ data: Data, to url: URL) throws {
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try data.write(to: url, options: options)
    }

    public func save(_ job: StoredTranscriptionJob, clipData: Data) throws {
        if !FileManager.default.fileExists(atPath: clipURL(job.clipID).path) { try Self.write(clipData, to: clipURL(job.clipID)) }
        try Self.write(ContextPack.encoder().encode(job), to: jobURL(job.clipID))
    }

    public func loadAll() throws -> [(job: StoredTranscriptionJob, clipData: Data)] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".job.json") }
            .map { url -> (job: StoredTranscriptionJob, clipData: Data) in
                let job = try ContextPack.decoder().decode(StoredTranscriptionJob.self, from: Data(contentsOf: url))
                return (job, try Data(contentsOf: clipURL(job.clipID)))
            }
            .sorted { ($0.job.createdAt, $0.job.clipID.uuidString) < ($1.job.createdAt, $1.job.clipID.uuidString) }
    }

    public func saveConsent(_ ledger: ConsentLedger) throws {
        try Self.write(ContextPack.encoder().encode(ledger), to: consentURL)
    }

    public func loadConsent() throws -> ConsentLedger {
        guard FileManager.default.fileExists(atPath: consentURL.path) else { return ConsentLedger() }
        return try ContextPack.decoder().decode(ConsentLedger.self, from: Data(contentsOf: consentURL))
    }
}

/// Coordinates optional short-clip transcription: explicit audio consent (separate from text consent), an offline
/// draft queue that sends only under the user's policy, no fallback provider, and transcripts preserved raw with
/// provenance. A failure never touches the clip or its capture.
///
/// The queue is durable: every job with a configuration is written to `store` at each state change (`sending` before
/// the upload starts), and audio consent is stored when granted. A new coordinator over the same store restores the
/// queue: queued clips stay queued (sent by the user, or on reconnect only under the opt-in policy), a clip awaiting
/// consent shows its disclosure again, and a clip that was uploading when Sylvia closed becomes a failure saying it may
/// have reached the server; it is never resent automatically.
///
/// One clip has at most one job. `request` for a clip that already has one returns that job unchanged: a clip being
/// sent, queued or awaiting consent is never uploaded a second time (a double tap on Transcribe), and a finished
/// transcript, with any correction, is never replaced (plan 10.4, 11.1: the raw transcript and the user's correction
/// are kept). A failed job whose upload may have been processed is sent again only through `send` with the user's
/// confirmation; any other failed job may be requested again, for example after the endpoint was fixed.
public actor TranscriptionCoordinator {
    public static let notConfiguredActions = ["Set up transcription", "Type what you heard"]

    let store: any TranscriptionQueueStore
    let providerFactory: @Sendable (ProviderConfig) -> any SpeechTranscriptionProvider
    let connectivity: any ConnectivityProbe
    let clock: any AIClock
    public private(set) var consent: ConsentLedger
    public var policy: TranscriptionQueuePolicy
    public private(set) var jobs: [UUID: TranscriptionJob] = [:]
    var configs: [UUID: ProviderConfig] = [:]
    var createdAt: [UUID: Date] = [:]

    /// Restores the stored queue and audio consent. `policy` is the user's setting (the app keeps it with its other
    /// settings); the default sends nothing without the user.
    public init(store: any TranscriptionQueueStore, providerFactory: @escaping @Sendable (ProviderConfig) -> any SpeechTranscriptionProvider,
                connectivity: any ConnectivityProbe, policy: TranscriptionQueuePolicy = .manual, clock: any AIClock = SystemClock()) throws {
        let consent = try store.loadConsent()
        var jobs: [UUID: TranscriptionJob] = [:]
        var configs: [UUID: ProviderConfig] = [:]
        var created: [UUID: Date] = [:]
        for (stored, data) in try store.loadAll() {
            var restored = stored
            if case .sending = stored.state {
                // The upload may have reached the server (and been billed): never resent without the user.
                let host = stored.config.baseURL.host() ?? ""
                restored.state = .failed(kind: .connectionLost,
                                         message: "Sylvia closed while this clip was being sent. It may have reached \(host). Send it again if you still want a transcript.",
                                         resendNeedsConfirmation: true)
                restored.updatedAt = clock.now()
                try store.save(restored, clipData: data)
            }
            let clip = AudioClip(clipID: stored.clipID, data: data, filename: stored.filename, mimeType: stored.mimeType, durationMs: stored.durationMs)
            jobs[stored.clipID] = TranscriptionJob(clip: clip, state: Self.state(restored.state, config: stored.config, consent: consent))
            configs[stored.clipID] = stored.config
            created[stored.clipID] = stored.createdAt
        }
        self.store = store
        self.providerFactory = providerFactory
        self.connectivity = connectivity
        self.consent = consent
        self.policy = policy
        self.clock = clock
        self.jobs = jobs
        self.configs = configs
        self.createdAt = created
    }

    /// The live state for a stored one. A pending disclosure is rebuilt from the configuration and the stored consent;
    /// if consent was granted since (for another clip to the same destination), the clip waits in the queue.
    static func state(_ stored: StoredTranscriptionJob.State, config: ProviderConfig, consent: ConsentLedger) -> TranscriptionJob.State {
        switch stored {
        case .awaitingAudioConsent:
            do {
                if case .required(let disclosure) = consent.evaluate(try endpoint(config), providerID: config.providerID, scopes: [.audio],
                                                                     content: .audioClip) {
                    return .awaitingAudioConsent(disclosure)
                }
                return .queuedOffline
            } catch {
                return .failed(kind: .insecureEndpointRejected, message: error.userMessage, resendNeedsConfirmation: false)
            }
        case .queuedOffline: return .queuedOffline
        case .sending: return .sending
        case .complete(let record): return .complete(record)
        case .failed(let kind, let message, let confirm): return .failed(kind: kind, message: message, resendNeedsConfirmation: confirm)
        }
    }

    public func setPolicy(_ policy: TranscriptionQueuePolicy) { self.policy = policy }

    static func endpoint(_ config: ProviderConfig) throws(EndpointPolicyViolation) -> EndpointIdentity {
        try EndpointIdentity.of(config)
    }

    /// Writes the job's current state. A clip with no configured service is not queued, so it is not stored.
    func persist(_ clipID: UUID) throws {
        guard let job = jobs[clipID], let config = configs[clipID] else { return }
        let stored: StoredTranscriptionJob.State
        switch job.state {
        case .notConfigured: return
        case .awaitingAudioConsent: stored = .awaitingAudioConsent
        case .queuedOffline: stored = .queuedOffline
        case .sending: stored = .sending
        case .complete(let record): stored = .complete(record)
        case .failed(let kind, let message, let confirm): stored = .failed(kind: kind, message: message, resendNeedsConfirmation: confirm)
        }
        let now = clock.now()
        let created = createdAt[clipID] ?? now
        createdAt[clipID] = created
        try store.save(StoredTranscriptionJob(clipID: clipID, filename: job.clip.filename, mimeType: job.clip.mimeType,
                                              durationMs: job.clip.durationMs, config: config, state: stored, createdAt: created,
                                              updatedAt: now),
                       clipData: job.clip.data)
    }

    /// The user asked to transcribe a clip. Throws only when the request can't be saved on this device.
    ///
    /// A clip that already has a job is not requested again: the existing job is returned unchanged while it is
    /// awaiting consent, queued or being sent (so a second tap never uploads the clip twice), once it is complete (so the
    /// raw transcript and any correction are never replaced), and after a failure whose upload may have been processed
    /// (sent again only by `send(_:userConfirmedResend:)`). Re-transcribing a finished clip, keeping the earlier
    /// transcript and correction as revisions, is not part of the spike.
    @discardableResult
    public func request(_ clip: AudioClip, config: ProviderConfig?) async throws -> TranscriptionJob {
        // Checked before any suspension point, so a concurrent second request sees the first one's job.
        if let existing = jobs[clip.clipID] {
            switch existing.state {
            case .notConfigured, .failed(_, _, resendNeedsConfirmation: false): break
            case .awaitingAudioConsent, .queuedOffline, .sending, .complete, .failed(_, _, resendNeedsConfirmation: true): return existing
            }
        }
        guard let config else {
            let job = TranscriptionJob(clip: clip, state: .notConfigured(actions: Self.notConfiguredActions))
            jobs[clip.clipID] = job
            return job
        }
        configs[clip.clipID] = config
        let endpoint: EndpointIdentity
        do {
            endpoint = try Self.endpoint(config)
        } catch {
            jobs[clip.clipID] = TranscriptionJob(clip: clip, state: .failed(kind: .insecureEndpointRejected, message: error.userMessage,
                                                                            resendNeedsConfirmation: false))
            try persist(clip.clipID)
            return jobs[clip.clipID]!
        }
        if case .required(let disclosure) = consent.evaluate(endpoint, providerID: config.providerID, scopes: [.audio], content: .audioClip) {
            jobs[clip.clipID] = TranscriptionJob(clip: clip, state: .awaitingAudioConsent(disclosure))
            try persist(clip.clipID)
            return jobs[clip.clipID]!
        }
        jobs[clip.clipID] = TranscriptionJob(clip: clip, state: .queuedOffline)
        try persist(clip.clipID)
        return try await send(clip.clipID)
    }

    public func grantAudioConsent(_ clipID: UUID) async throws -> TranscriptionJob? {
        guard var job = jobs[clipID], case .awaitingAudioConsent(let disclosure) = job.state, let config = configs[clipID] else { return jobs[clipID] }
        consent.grant(disclosure, providerID: config.providerID, at: clock.now())
        try store.saveConsent(consent)
        job.state = .queuedOffline
        jobs[clipID] = job
        try persist(clipID)
        return try await send(clipID)
    }

    /// Sends a queued or failed clip now (an explicit user action, or the opt-in policy on reconnect, which sends only
    /// queued clips). A failed clip whose last upload may have been processed (`resendNeedsConfirmation`) is sent only
    /// with `userConfirmedResend`; otherwise this throws `TranscriptionError.resendNeedsConfirmation` and sends nothing.
    @discardableResult
    public func send(_ clipID: UUID, userConfirmedResend: Bool = false) async throws -> TranscriptionJob {
        guard var job = jobs[clipID], let config = configs[clipID] else {
            return jobs[clipID] ?? TranscriptionJob(clip: AudioClip(data: Data(), filename: "", mimeType: "", durationMs: 0),
                                                    state: .failed(kind: .badRequest, message: "Unknown clip.", resendNeedsConfirmation: false))
        }
        switch job.state {
        case .queuedOffline: break
        case .failed(_, _, let needsConfirmation):
            if needsConfirmation && !userConfirmedResend { throw TranscriptionError.resendNeedsConfirmation }
        default: return job
        }
        // Audio consent is checked again at send time, as text consent is: a stored job may outlive the consent it
        // was queued under, and nothing is uploaded without it.
        let endpoint: EndpointIdentity
        do {
            endpoint = try Self.endpoint(config)
        } catch {
            job.state = .failed(kind: .insecureEndpointRejected, message: error.userMessage, resendNeedsConfirmation: false)
            jobs[clipID] = job
            try persist(clipID)
            return job
        }
        if case .required(let disclosure) = consent.evaluate(endpoint, providerID: config.providerID, scopes: [.audio], content: .audioClip) {
            job.state = .awaitingAudioConsent(disclosure)
            jobs[clipID] = job
            try persist(clipID)
            return job
        }
        guard connectivity.isOnline else {
            job.state = .queuedOffline
            jobs[clipID] = job
            try persist(clipID)
            return job
        }
        let before = jobs[clipID]
        job.state = .sending
        jobs[clipID] = job
        do {
            try persist(clipID)  // durable before the upload starts
        } catch {
            // Not durable, so not sent: the clip keeps the state it had.
            jobs[clipID] = before
            throw error
        }
        do {
            let record = try await providerFactory(config).transcribe(job.clip)
            job.state = .complete(record)
        } catch {
            let classified = ErrorClassifier.classify(error, host: config.baseURL.host() ?? "", bodyMayHaveBeenSent: true)
            // An upload whose acceptance is uncertain (a server or gateway error, a timeout or a dropped connection after
            // sending, an unreadable or oversized reply) may have been processed and billed: it is sent again only on the
            // user's confirmation, as its message says.
            job.state = classified.kind == .offline ? .queuedOffline
                : .failed(kind: classified.kind, message: classified.userMessage, resendNeedsConfirmation: classified.acceptance == .uncertain)
        }
        jobs[clipID] = job
        try persist(clipID)
        return job
    }

    /// Connectivity returned. Under the default manual policy nothing is sent. Under the opt-in policy each clip that is
    /// still queued when its turn comes is sent, oldest first; returns each job the loop tried to send, in its state
    /// afterwards, in that order.
    ///
    /// Each upload is awaited, and meanwhile the user can act on other clips (send one, which may fail), so the policy
    /// and each clip's state are checked again just before that clip is sent, with no suspension point between the
    /// check and `send` marking it as sending. A clip that is no longer queued (being sent, sent, failed, awaiting
    /// consent) is skipped: the policy sends only queued clips and never resends a failed one. One clip's error (a store
    /// write that failed, so the clip was not sent and keeps its state) never stops the loop.
    public func connectivityRestored() async -> [TranscriptionJob] {
        guard policy == .sendWhenOnline else { return [] }
        let queued = jobs.filter { $0.value.state == .queuedOffline }.keys
            .sorted { (createdAt[$0] ?? .distantPast, $0.uuidString) < (createdAt[$1] ?? .distantPast, $1.uuidString) }
        var sent: [TranscriptionJob] = []
        for id in queued {
            guard policy == .sendWhenOnline, jobs[id]?.state == .queuedOffline else { continue }
            do {
                sent.append(try await send(id))
            } catch {
                if let job = jobs[id] { sent.append(job) }
            }
        }
        return sent
    }

    /// Stores the user's corrected wording beside the raw machine transcript.
    public func saveCorrection(_ clipID: UUID, text: String) throws -> TranscriptRecord? {
        guard var job = jobs[clipID], case .complete(var record) = job.state else { return nil }
        record.correctedText = text
        job.state = .complete(record)
        jobs[clipID] = job
        try persist(clipID)
        return record
    }
}

/// A short generated silent WAV (16 kHz, mono, 16-bit PCM) for the transcription capability test, so the test
/// never uploads the user's audio.
public enum SilentWAV {
    public static func make(milliseconds: Int = 1_000, sampleRate: Int = 16_000) -> Data {
        let samples = sampleRate * milliseconds / 1000
        let dataBytes = samples * 2
        var data = Data()
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(Data("RIFF".utf8)); append32(UInt32(36 + dataBytes)); data.append(Data("WAVE".utf8))
        data.append(Data("fmt ".utf8)); append32(16); append16(1); append16(1); append32(UInt32(sampleRate)); append32(UInt32(sampleRate * 2))
        append16(2); append16(16)
        data.append(Data("data".utf8)); append32(UInt32(dataBytes))
        data.append(Data(count: dataBytes))
        return data
    }

    /// Capability test: uploads one second of generated silence and expects a JSON body with a `text` field.
    public static func capabilityTest(_ provider: any SpeechTranscriptionProvider) async -> Result<TranscriptRecord, ProviderError> {
        do {
            return .success(try await provider.transcribe(AudioClip(data: make(), filename: "sylvia-capability-test.wav", mimeType: "audio/wav", durationMs: 1_000)))
        } catch {
            return .failure(ErrorClassifier.classify(error, host: provider.config.baseURL.host() ?? "", bodyMayHaveBeenSent: true))
        }
    }
}
