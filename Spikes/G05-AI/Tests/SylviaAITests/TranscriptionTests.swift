import Foundation
import G05TestSupport
import Synchronization
import Testing
@testable import SylviaAI

final class StateLog: Sendable {
    let states = Mutex<[String]>([])
}

final class CallLog: Sendable {
    let calls = Mutex<[UUID]>([])
}

/// A queue store that refuses to record one clip as sending (a full disk, say); everything else goes to `inner`.
final class RefusingQueueStore: TranscriptionQueueStore {
    struct Refused: Error {}
    let inner: FileTranscriptionQueueStore
    let refuseSending = Mutex<UUID?>(nil)
    init(inner: FileTranscriptionQueueStore) { self.inner = inner }
    func save(_ job: StoredTranscriptionJob, clipData: Data) throws {
        if job.state == .sending, refuseSending.withLock({ $0 }) == job.clipID { throw Refused() }
        try inner.save(job, clipData: clipData)
    }
    func loadAll() throws -> [(job: StoredTranscriptionJob, clipData: Data)] { try inner.loadAll() }
    func saveConsent(_ ledger: ConsentLedger) throws { try inner.saveConsent(ledger) }
    func loadConsent() throws -> ConsentLedger { try inner.loadConsent() }
}

/// Parses a multipart/form-data body into named parts (test helper).
struct MultipartParts {
    var fields: [String: [String]] = [:]
    var files: [String: (filename: String, contentType: String, data: Data)] = [:]

    init(body: Data, contentType: String) {
        guard let boundary = contentType.components(separatedBy: "boundary=").last else { return }
        let delimiter = Data("--\(boundary)".utf8)
        var ranges: [Range<Data.Index>] = []
        var search = body.startIndex
        while let range = body.range(of: delimiter, in: search..<body.endIndex) {
            ranges.append(range)
            search = range.upperBound
        }
        for (start, end) in zip(ranges, ranges.dropFirst()) {
            var part = body[start.upperBound..<end.lowerBound]
            if part.starts(with: Data("\r\n".utf8)) { part = part.dropFirst(2) }
            if part.count >= 2, part.suffix(2) == Data("\r\n".utf8) { part = part.dropLast(2) }
            guard let split = part.range(of: Data("\r\n\r\n".utf8)) else { continue }
            let head = String(decoding: part[part.startIndex..<split.lowerBound], as: UTF8.self)
            let content = Data(part[split.upperBound...])
            let name = head.components(separatedBy: "name=\"").dropFirst().first?.components(separatedBy: "\"").first ?? ""
            if head.contains("filename=\"") {
                let filename = head.components(separatedBy: "filename=\"").last?.components(separatedBy: "\"").first ?? ""
                let type = head.components(separatedBy: "Content-Type: ").last?.components(separatedBy: "\r\n").first ?? ""
                files[name] = (filename, type, content)
            } else {
                fields[name, default: []].append(String(decoding: content, as: UTF8.self))
            }
        }
    }
}

/// Brief item 8 / plan 10.4 / T24: transcription through an OpenAI-compatible /audio/transcriptions endpoint.
@Suite("Transcription")
struct TranscriptionTests {
    static let verboseBody = #"{"task":"transcribe","language":"english","duration":180.0,"text":"Book one. From my grandfather Verus I learned good morals.","segments":[{"id":0,"start":0.0,"end":2.48,"text":"Book one."},{"id":1,"start":2.48,"end":7.125,"text":"From my grandfather Verus I learned good morals."}]}"#

    static func config(_ server: FakeHTTPServer, timestamps: Bool = true, credential: CredentialRef? = nil) -> ProviderConfig {
        ProviderConfig(kind: .openAICompatibleTranscription, displayName: "Speech", baseURL: try! BaseURL.normalize(server.baseURL.absoluteString + "/v1/audio/transcriptions"),
                       model: "speech-model", credential: credential, capabilities: ProviderCapabilities(timestamps: timestamps),
                       allowInsecureLocalHTTP: true)
    }

    static func clip() throws -> AudioClip {
        AudioClip(data: try RepoFixtures.data("audio/meditations-01-first180s.mp3"), filename: "clip.mp3", mimeType: "audio/mpeg", durationMs: 180_000)
    }

    static func coordinator(online: Bool = true, credentials: InMemoryCredentialStore = InMemoryCredentialStore(),
                            factoryCalls: CallLog? = nil, directory: URL = TestPacks.temporaryDirectory(),
                            policy: TranscriptionQueuePolicy = .manual) throws -> (TranscriptionCoordinator, FakeConnectivity) {
        let connectivity = FakeConnectivity(online: online)
        let coordinator = try TranscriptionCoordinator(store: try FileTranscriptionQueueStore(directory: directory), providerFactory: { config in
            factoryCalls?.calls.withLock { $0.append(config.providerID) }
            return OpenAICompatibleTranscriptionProvider(config: config, credentials: credentials, transport: URLSessionTransport())
        }, connectivity: connectivity, policy: policy)
        return (coordinator, connectivity)
    }

    @Test func multipartUploadWithTimingAndProvenance() async throws {
        let server = try await FakeHTTPServer { _ in .json(200, Self.verboseBody) }
        let credentials = InMemoryCredentialStore()
        let ref = try #require(CredentialRef(for: server.baseURL))
        try credentials.save(Secret(Canary.apiKey), for: ref)
        let clip = try Self.clip()
        let (coordinator, _) = try Self.coordinator(credentials: credentials)
        let config = Self.config(server, credential: ref)
        let asked = try await coordinator.request(clip, config: config)
        guard case .awaitingAudioConsent(let disclosure) = asked.state else { Issue.record("audio consent required first"); return }
        // R3-03: the request carries only the clip, so the disclosure lists only the clip (no "your question").
        #expect(disclosure.lines == [
            "Destination: 127.0.0.1 · local · speech-model",
            "What is sent: the audio clip you selected. Nothing else from your library is sent.",
            "127.0.0.1 is an address on your local network. Sylvia can't check whether that server passes requests on to another service.",
        ])
        #expect(disclosure.scopes == [.audio])
        #expect(server.requests.isEmpty, "nothing uploaded before consent")

        let job = try await coordinator.grantAudioConsent(clip.clipID)
        guard case .complete(let record) = job?.state else { Issue.record("expected completion, got \(String(describing: job?.state))"); return }
        #expect(record.rawText == "Book one. From my grandfather Verus I learned good morals.")
        #expect(record.segments == [TranscriptSegment(startMs: 0, endMs: 2480, text: "Book one."),
                                    TranscriptSegment(startMs: 2480, endMs: 7125, text: "From my grandfather Verus I learned good morals.")])
        #expect(record.language == "english")
        #expect(record.providerKind == .openAICompatibleTranscription)
        #expect(record.host == "127.0.0.1")
        #expect(record.model == "speech-model")
        #expect(record.label == "Machine transcription · may be inaccurate")
        #expect(record.correctedText == nil)

        let request = try #require(server.requests.first)
        #expect(request.path == "/v1/audio/transcriptions")
        #expect(request.headers["authorization"] == "Bearer \(Canary.apiKey)")
        let parts = MultipartParts(body: request.body, contentType: request.headers["content-type"] ?? "")
        #expect(parts.fields["model"] == ["speech-model"])
        #expect(parts.fields["response_format"] == ["verbose_json"])
        #expect(parts.fields["timestamp_granularities[]"] == ["segment"])
        let file = try #require(parts.files["file"])
        #expect(file.filename == "clip.mp3")
        #expect(file.contentType == "audio/mpeg")
        #expect(SHA256Hex.of(file.data) == "6a3b752cc744ccb310a6d71149b96a7f29d632e35ca5a6ad8abb3e46c532a1ad", "the exact retained clip, byte for byte")

        // A correction is stored beside the raw transcript, not over it.
        let corrected = try await coordinator.saveCorrection(clip.clipID, text: "Book One. From my grandfather Verus I learned good morals.")
        #expect(corrected?.rawText == record.rawText)
        #expect(corrected?.correctedText == "Book One. From my grandfather Verus I learned good morals.")
    }

    @Test func plainJSONWhenTimingIsNotConfigured() async throws {
        let server = try await FakeHTTPServer { _ in .json(200, #"{"text":"Plain transcript."}"#) }
        let provider = OpenAICompatibleTranscriptionProvider(config: Self.config(server, timestamps: false), credentials: InMemoryCredentialStore(),
                                                             transport: URLSessionTransport())
        let record = try await provider.transcribe(try Self.clip())
        #expect(record.rawText == "Plain transcript.")
        #expect(record.segments.isEmpty)
        let request = try #require(server.requests.first)
        let parts = MultipartParts(body: request.body, contentType: request.headers["content-type"] ?? "")
        #expect(parts.fields["response_format"] == ["json"])
        #expect(parts.fields["timestamp_granularities[]"] == nil)
    }

    @Test func noEndpointConfiguredSaysSoAndUploadsNothing() async throws {
        let (coordinator, _) = try Self.coordinator()
        let job = try await coordinator.request(try Self.clip(), config: nil)
        #expect(job.state == .notConfigured(actions: ["Set up transcription", "Type what you heard"]))
    }

    @Test func offlineDraftWaitsForTheUserUnderTheDefaultPolicy() async throws {
        let server = try await FakeHTTPServer { _ in .json(200, #"{"text":"Later."}"#) }
        let (coordinator, connectivity) = try Self.coordinator(online: false)
        let clip = try Self.clip()
        _ = try await coordinator.request(clip, config: Self.config(server))
        let queued = try await coordinator.grantAudioConsent(clip.clipID)
        #expect(queued?.state == .queuedOffline)
        connectivity.set(online: true)
        let autoSent = await coordinator.connectivityRestored()
        #expect(autoSent.isEmpty)
        try await Task.sleep(for: .milliseconds(100))
        #expect(server.requests.isEmpty, "manual policy: nothing is sent when connectivity returns")
        // The opt-in policy sends on reconnect.
        await coordinator.setPolicy(.sendWhenOnline)
        let sent = await coordinator.connectivityRestored()
        #expect(sent.count == 1)
        #expect(server.requests.count == 1)
    }

    /// R3-04 (plan 10.4: "Queue a local draft when offline"): a clip queued offline survives a relaunch with its clip,
    /// configuration and audio consent; after the relaunch it is still sent only by the user or under the opt-in policy,
    /// and nothing stored holds the key.
    @Test func queuedClipSurvivesARelaunchAndIsSentOnlyUnderThePolicy() async throws {
        let server = try await FakeHTTPServer { _ in .json(200, #"{"text":"After the relaunch."}"#) }
        let directory = TestPacks.temporaryDirectory()
        let credentials = InMemoryCredentialStore()
        let ref = try #require(CredentialRef(for: server.baseURL))
        try credentials.save(Secret(Canary.apiKey), for: ref)
        let config = Self.config(server, credential: ref)
        let clip = try Self.clip()
        do {
            let (before, _) = try Self.coordinator(online: false, credentials: credentials, directory: directory)
            _ = try await before.request(clip, config: config)
            #expect(try await before.grantAudioConsent(clip.clipID)?.state == .queuedOffline)
        }
        // Relaunch: a new coordinator over the same store, now online, with the default manual policy.
        let (after, _) = try Self.coordinator(online: true, credentials: credentials, directory: directory)
        let restored = try #require(await after.jobs[clip.clipID])
        #expect(restored.state == .queuedOffline)
        #expect(restored.clip == clip, "the clip's bytes and metadata are restored exactly")
        #expect(SHA256Hex.of(restored.clip.data) == SHA256Hex.of(clip.data))
        #expect(await after.connectivityRestored().isEmpty)
        try await Task.sleep(for: .milliseconds(100))
        #expect(server.requests.isEmpty, "manual policy: nothing is sent after the relaunch either")
        // The audio consent was restored: the user's send goes out without asking again, to the same endpoint.
        let sent = try await after.send(clip.clipID)
        guard case .complete(let record) = sent.state else { Issue.record("expected completion, got \(sent.state)"); return }
        #expect(record.rawText == "After the relaunch.")
        #expect(server.requests.count == 1)
        let parts = MultipartParts(body: try #require(server.requests.first).body, contentType: server.requests.first?.headers["content-type"] ?? "")
        #expect(parts.files["file"]?.data == clip.data, "the restored clip is the one uploaded")
        // The completed transcript is durable too.
        let (again, _) = try Self.coordinator(credentials: credentials, directory: directory)
        guard case .complete(let reloaded) = await again.jobs[clip.clipID]?.state else { Issue.record("transcript not restored"); return }
        #expect(reloaded.rawText == "After the relaunch." && reloaded.label == TranscriptRecord.label)
        // Nothing in the queue's files holds the key (the configuration has a credential reference only).
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let data = try Data(contentsOf: file)
            #expect(data.range(of: Data(Canary.apiKey.utf8)) == nil, "\(file.lastPathComponent)")
            #expect(data.range(of: Data("CANARY".utf8)) == nil, "\(file.lastPathComponent)")
        }
    }

    @Test func queuedClipIsSentAfterARelaunchOnlyUnderTheOptInPolicy() async throws {
        let server = try await FakeHTTPServer { _ in .json(200, #"{"text":"Sent on reconnect."}"#) }
        let directory = TestPacks.temporaryDirectory()
        let clip = try Self.clip()
        do {
            let (before, _) = try Self.coordinator(online: false, directory: directory)
            _ = try await before.request(clip, config: Self.config(server))
            _ = try await before.grantAudioConsent(clip.clipID)
        }
        let (after, _) = try Self.coordinator(online: true, directory: directory, policy: .sendWhenOnline)
        let sent = await after.connectivityRestored()
        #expect(sent.count == 1)
        guard case .complete(let record) = sent.first?.state else { Issue.record("expected completion"); return }
        #expect(record.rawText == "Sent on reconnect.")
        #expect(server.requests.count == 1)
    }

    /// Three clips queued offline with audio consent on record, under the opt-in policy, with different file names so the
    /// fake server can tell them apart. Requests are a clock tick apart, so the reconnect loop takes them in this order.
    static func threeQueuedClips(_ server: FakeHTTPServer, store: any TranscriptionQueueStore)
        async throws -> (TranscriptionCoordinator, FakeConnectivity, [AudioClip]) {
        let connectivity = FakeConnectivity(online: false)
        let clock = ManualClock()
        let coordinator = try TranscriptionCoordinator(store: store, providerFactory: { config in
            OpenAICompatibleTranscriptionProvider(config: config, credentials: InMemoryCredentialStore(), transport: URLSessionTransport())
        }, connectivity: connectivity, policy: .sendWhenOnline, clock: clock)
        let data = try Self.clip().data
        let clips = ["clip-a.mp3", "clip-b.mp3", "clip-c.mp3"].map {
            AudioClip(data: data, filename: $0, mimeType: "audio/mpeg", durationMs: 180_000)
        }
        let config = Self.config(server)
        _ = try await coordinator.request(clips[0], config: config)
        #expect(try await coordinator.grantAudioConsent(clips[0].clipID)?.state == .queuedOffline)
        for clip in clips.dropFirst() {
            clock.advance(by: 1)
            #expect(try await coordinator.request(clip, config: config).state == .queuedOffline)
        }
        #expect(server.requests.isEmpty)
        return (coordinator, connectivity, clips)
    }

    static func uploadedFilenames(_ server: FakeHTTPServer) -> [String] {
        server.requests.compactMap { MultipartParts(body: $0.body, contentType: $0.headers["content-type"] ?? "").files["file"]?.filename }
    }

    /// R5-02: the reconnect loop awaits each upload, and meanwhile the user can send another queued clip. A clip that is no
    /// longer queued when its turn comes is skipped: the loop neither stops at it (later clips are still sent, and the
    /// caller gets every result) nor uploads it again, whether the user's send failed with an uncertain 502 (resend needs
    /// confirmation) or a certain 429 (a plain Send by the user could resend it, but the policy never does).
    @Test(arguments: [502, 429])
    func reconnectLoopSendsOnlyClipsStillQueued(userSendStatus: Int) async throws {
        let server = try await FakeHTTPServer { request in
            let filename = MultipartParts(body: request.body, contentType: request.headers["content-type"] ?? "").files["file"]?.filename
            switch filename {
            case "clip-a.mp3":
                // Held back, so the user acts while the loop's first upload is in flight.
                return FakeResponse(status: 200, headers: [("Content-Type", "application/json")],
                                    steps: [.pause(milliseconds: 500), .send(Data(#"{"text":"Clip A."}"#.utf8))])
            case "clip-b.mp3":
                return .json(userSendStatus, #"{"error":{"message":"not now","type":"server_error"}}"#)
            default:
                return .json(200, #"{"text":"Clip C."}"#)
            }
        }
        let (coordinator, connectivity, clips) = try await Self.threeQueuedClips(
            server, store: try FileTranscriptionQueueStore(directory: TestPacks.temporaryDirectory()))
        connectivity.set(online: true)
        let loop = Task { await coordinator.connectivityRestored() }
        let deadline = ContinuousClock.now + .seconds(10)
        while Self.uploadedFilenames(server).isEmpty, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(Self.uploadedFilenames(server) == ["clip-a.mp3"], "the loop's first upload is in flight")

        // The user taps Send on the second queued clip; it fails.
        guard case .failed(_, _, let needsConfirmation) = try await coordinator.send(clips[1].clipID).state else {
            Issue.record("expected the user's send to fail"); return
        }
        #expect(needsConfirmation == (userSendStatus == 502))

        let results = await loop.value
        #expect(results.map(\.clip.clipID) == [clips[0].clipID, clips[2].clipID], "the changed clip was skipped, the later one sent")
        guard case .complete(let a) = results.first?.state, case .complete(let c) = results.last?.state else {
            Issue.record("expected both queued clips to complete, got \(results.map(\.state))"); return
        }
        #expect(a.rawText == "Clip A." && c.rawText == "Clip C.")
        guard case .failed = await coordinator.jobs[clips[1].clipID]?.state else { Issue.record("the failed clip changed"); return }
        #expect(Self.uploadedFilenames(server).sorted() == ["clip-a.mp3", "clip-b.mp3", "clip-c.mp3"], "each clip was uploaded once")
    }

    /// R5-02: one clip's error never stops the reconnect loop. Here the store refuses to record the first clip as sending,
    /// so that clip is not uploaded and stays queued, and the loop goes on to the others.
    @Test func reconnectLoopContinuesPastAClipThatCouldNotBeSaved() async throws {
        let server = try await FakeHTTPServer { request in
            let filename = MultipartParts(body: request.body, contentType: request.headers["content-type"] ?? "").files["file"]?.filename ?? "?"
            return .json(200, #"{"text":"Sent \#(filename)."}"#)
        }
        let store = RefusingQueueStore(inner: try FileTranscriptionQueueStore(directory: TestPacks.temporaryDirectory()))
        let (coordinator, connectivity, clips) = try await Self.threeQueuedClips(server, store: store)
        store.refuseSending.withLock { $0 = clips[0].clipID }
        connectivity.set(online: true)
        let results = await coordinator.connectivityRestored()
        #expect(results.map(\.clip.clipID) == clips.map(\.clipID))
        #expect(results.first?.state == .queuedOffline, "not durable as sending, so not sent; it keeps its state")
        #expect(results.dropFirst().allSatisfy { if case .complete = $0.state { true } else { false } })
        #expect(Self.uploadedFilenames(server) == ["clip-b.mp3", "clip-c.mp3"])
        #expect(await coordinator.jobs[clips[0].clipID]?.state == .queuedOffline)
    }

    /// A clip that was waiting for audio consent shows the same disclosure after a relaunch and uploads nothing until
    /// the user agrees.
    @Test func clipAwaitingConsentAsksAgainAfterARelaunch() async throws {
        let server = try await FakeHTTPServer { _ in .json(200, #"{"text":"With consent."}"#) }
        let directory = TestPacks.temporaryDirectory()
        let clip = try Self.clip()
        let first: Disclosure
        do {
            let (before, _) = try Self.coordinator(directory: directory)
            guard case .awaitingAudioConsent(let disclosure) = try await before.request(clip, config: Self.config(server)).state else {
                Issue.record("audio consent required first"); return
            }
            first = disclosure
        }
        let (after, _) = try Self.coordinator(directory: directory, policy: .sendWhenOnline)
        guard case .awaitingAudioConsent(let disclosure) = await after.jobs[clip.clipID]?.state else { Issue.record("consent not asked again"); return }
        #expect(disclosure == first)
        #expect(await after.connectivityRestored().isEmpty, "a clip without consent is never sent by the policy")
        #expect(server.requests.isEmpty)
        let job = try await after.grantAudioConsent(clip.clipID)
        guard case .complete = job?.state else { Issue.record("expected completion"); return }
        #expect(server.requests.count == 1)
    }

    /// A clip that was uploading when Sylvia closed may have reached the server, so after a relaunch it is a failure
    /// that says so, and it is never resent automatically, even under the opt-in policy.
    @Test func uploadCutOffByARelaunchIsNeverResentAutomatically() async throws {
        let server = try await FakeHTTPServer { _ in .json(200, #"{"text":"Should not be sent."}"#) }
        let directory = TestPacks.temporaryDirectory()
        let clip = try Self.clip()
        let config = Self.config(server)
        let store = try FileTranscriptionQueueStore(directory: directory)
        // The state a relaunch finds when the app stopped mid-upload (`sending` is written before the upload starts).
        try store.save(StoredTranscriptionJob(clipID: clip.clipID, filename: clip.filename, mimeType: clip.mimeType, durationMs: clip.durationMs,
                                              config: config, state: .sending, createdAt: Date(), updatedAt: Date()), clipData: clip.data)
        let (after, _) = try Self.coordinator(directory: directory, policy: .sendWhenOnline)
        guard case .failed(let kind, let message, let needsConfirmation) = await after.jobs[clip.clipID]?.state else {
            Issue.record("expected a failure"); return
        }
        #expect(kind == .connectionLost)
        #expect(message == "Sylvia closed while this clip was being sent. It may have reached 127.0.0.1. Send it again if you still want a transcript.")
        #expect(needsConfirmation, "the upload may have been processed")
        #expect(await after.connectivityRestored().isEmpty)
        try await Task.sleep(for: .milliseconds(100))
        #expect(server.requests.isEmpty)
        let stored = try #require(try store.loadAll().first)
        #expect(stored.job.state == .failed(kind: .connectionLost, message: message, resendNeedsConfirmation: true), "the reconciled state is durable")
        // R4-04: a plain Send, or another Transcribe, does not upload it again; only a confirmed resend does.
        await #expect(throws: TranscriptionError.resendNeedsConfirmation) { try await after.send(clip.clipID) }
        #expect(try await after.request(clip, config: config).state == .failed(kind: .connectionLost, message: message, resendNeedsConfirmation: true))
        try await Task.sleep(for: .milliseconds(100))
        #expect(server.requests.isEmpty)
        // The confirmed resend still needs audio consent on record (none was stored for this job), and then uploads.
        guard case .awaitingAudioConsent = try await after.send(clip.clipID, userConfirmedResend: true).state else {
            Issue.record("expected a consent request"); return
        }
        #expect(server.requests.isEmpty)
        guard case .complete = try await after.grantAudioConsent(clip.clipID)?.state else { Issue.record("expected completion"); return }
        #expect(server.requests.count == 1)
    }

    /// Audio consent is checked again when a queued clip is sent: a stored job whose consent is not on record asks for
    /// it and uploads nothing, even when the user taps Send or the opt-in policy runs.
    @Test func queuedClipWithoutStoredConsentAsksBeforeSending() async throws {
        let server = try await FakeHTTPServer { _ in .json(200, #"{"text":"Should wait for consent."}"#) }
        let directory = TestPacks.temporaryDirectory()
        let clip = try Self.clip()
        let store = try FileTranscriptionQueueStore(directory: directory)
        try store.save(StoredTranscriptionJob(clipID: clip.clipID, filename: clip.filename, mimeType: clip.mimeType, durationMs: clip.durationMs,
                                              config: Self.config(server), state: .queuedOffline, createdAt: Date(), updatedAt: Date()),
                       clipData: clip.data)
        let (coordinator, _) = try Self.coordinator(directory: directory, policy: .sendWhenOnline)
        #expect(await coordinator.jobs[clip.clipID]?.state == .queuedOffline)
        let sent = await coordinator.connectivityRestored()
        guard case .awaitingAudioConsent(let disclosure) = sent.first?.state else { Issue.record("expected a consent request"); return }
        #expect(disclosure.reasons == [.firstRequest])
        #expect(try await coordinator.send(clip.clipID).state == .awaitingAudioConsent(disclosure))
        try await Task.sleep(for: .milliseconds(100))
        #expect(server.requests.isEmpty, "nothing uploaded without audio consent")
    }

    /// The coordinator writes `sending` before the upload starts, so a relaunch mid-upload can tell (the case above).
    @Test func sendingIsDurableBeforeTheUploadStarts() async throws {
        let directory = TestPacks.temporaryDirectory()
        let observed = StateLog()
        let server = try await FakeHTTPServer { _ in
            let states = (try? FileTranscriptionQueueStore(directory: directory).loadAll().map { String(describing: $0.job.state) }) ?? []
            observed.states.withLock { $0 = states }
            return .json(200, #"{"text":"ok"}"#)
        }
        let (coordinator, _) = try Self.coordinator(directory: directory)
        let clip = try Self.clip()
        _ = try await coordinator.request(clip, config: Self.config(server))
        _ = try await coordinator.grantAudioConsent(clip.clipID)
        #expect(observed.states.withLock { $0 } == ["sending"], "the store said sending while the server handled the upload")
    }

    /// R4-01: two requests for one clip at once, as from a double tap on Transcribe with audio consent on record,
    /// upload it once. The second request returns the job the first one created.
    @Test func concurrentRequestsForOneClipUploadItOnce() async throws {
        let server = try await FakeHTTPServer { _ in
            // The reply is held back so the first upload is still in flight when the second request arrives.
            FakeResponse(status: 200, headers: [("Content-Type", "application/json")],
                         steps: [.pause(milliseconds: 300), .send(Data(#"{"text":"Once."}"#.utf8))])
        }
        let (coordinator, _) = try Self.coordinator()
        let config = Self.config(server)
        let first = try Self.clip()
        _ = try await coordinator.request(first, config: config)
        _ = try await coordinator.grantAudioConsent(first.clipID)  // audio consent is now on record for this endpoint
        #expect(server.requests.count == 1)

        let clip = try Self.clip()
        async let a = coordinator.request(clip, config: config)
        async let b = coordinator.request(clip, config: config)
        let results = try await [a, b]
        #expect(server.requests.count == 2, "the second clip was uploaded once, not twice")
        #expect(results.contains { if case .complete = $0.state { true } else { false } })
        guard case .complete(let record) = await coordinator.jobs[clip.clipID]?.state else { Issue.record("expected completion"); return }
        #expect(record.rawText == "Once.")
        // A third request after completion returns the transcript and uploads nothing.
        #expect(try await coordinator.request(clip, config: config).state == .complete(record))
        #expect(server.requests.count == 2)
    }

    /// R4-01 (plan 10.4, 11.1): a second request for a transcribed clip never replaces the raw transcript or the
    /// user's correction, before or after a relaunch, and uploads nothing.
    @Test func correctionSurvivesASecondRequestAndARelaunch() async throws {
        let server = try await FakeHTTPServer { request in
            .json(200, #"{"text":"Machine words number \#(request.index + 1)."}"#)
        }
        let directory = TestPacks.temporaryDirectory()
        let config = Self.config(server)
        let clip = try Self.clip()
        let (coordinator, _) = try Self.coordinator(directory: directory)
        _ = try await coordinator.request(clip, config: config)
        guard case .complete(let original) = try await coordinator.grantAudioConsent(clip.clipID)?.state else {
            Issue.record("expected completion"); return
        }
        #expect(original.rawText == "Machine words number 1.")
        let corrected = try #require(try await coordinator.saveCorrection(clip.clipID, text: "My corrected words"))

        let again = try await coordinator.request(clip, config: config)
        #expect(again.state == .complete(corrected), "the earlier transcript and the correction are kept")
        #expect(server.requests.count == 1, "nothing was uploaded again")

        let (relaunched, _) = try Self.coordinator(directory: directory, policy: .sendWhenOnline)
        guard case .complete(let restored) = await relaunched.jobs[clip.clipID]?.state else { Issue.record("transcript not restored"); return }
        #expect(restored.rawText == "Machine words number 1.")
        #expect(restored.correctedText == "My corrected words")
        #expect(try await relaunched.request(clip, config: config).state == .complete(restored))
        #expect(try await relaunched.send(clip.clipID).state == .complete(restored))
        #expect(await relaunched.connectivityRestored().isEmpty)
        try await Task.sleep(for: .milliseconds(100))
        #expect(server.requests.count == 1)
        let stored = try #require(try FileTranscriptionQueueStore(directory: directory).loadAll().first)
        guard case .complete(let storedRecord) = stored.job.state else { Issue.record("expected a stored transcript"); return }
        #expect(storedRecord.rawText == "Machine words number 1." && storedRecord.correctedText == "My corrected words",
                "the stored record still holds the raw transcript and the correction")
    }

    /// R4-04: a failure whose upload may have been processed (here a gateway's 502) is sent again only when the user
    /// confirms, as its message says; a failure that certainly was not processed (a 429) can be sent again at once.
    @Test func uncertainTranscriptionFailureIsResentOnlyOnConfirmation() async throws {
        let replies = Mutex<[FakeResponse]>([
            .json(502, #"{"error":{"message":"upstream failed","type":"server_error"}}"#),
            .json(200, #"{"text":"After confirmation."}"#),
        ])
        let server = try await FakeHTTPServer { _ in replies.withLock { $0.count > 1 ? $0.removeFirst() : $0[0] } }
        let (coordinator, _) = try Self.coordinator()
        let config = Self.config(server)
        let clip = try Self.clip()
        _ = try await coordinator.request(clip, config: config)
        guard case .failed(let kind, let message, let needsConfirmation) = try await coordinator.grantAudioConsent(clip.clipID)?.state else {
            Issue.record("expected a failure"); return
        }
        #expect(kind == .serverError)
        #expect(message == "127.0.0.1 reported a server or gateway error (HTTP 502). The request may or may not have been processed, so Sylvia won't send it again without asking.")
        #expect(needsConfirmation)
        await #expect(throws: TranscriptionError.resendNeedsConfirmation) { try await coordinator.send(clip.clipID) }
        _ = try await coordinator.request(clip, config: config)
        try await Task.sleep(for: .milliseconds(100))
        #expect(server.requests.count == 1, "neither a plain Send nor another Transcribe uploaded it again")
        guard case .complete(let record) = try await coordinator.send(clip.clipID, userConfirmedResend: true).state else {
            Issue.record("expected completion"); return
        }
        #expect(record.rawText == "After confirmation.")
        #expect(server.requests.count == 2)

        let limited = try await FakeHTTPServer { request in
            request.index == 0 ? .json(429, #"{"error":{"message":"slow down","type":"rate_limit_error"}}"#) : .json(200, #"{"text":"Retried."}"#)
        }
        let other = try Self.clip()
        let limitedConfig = Self.config(limited)
        _ = try await coordinator.request(other, config: limitedConfig)
        guard case .failed(.rateLimited, _, let confirm) = try await coordinator.grantAudioConsent(other.clipID)?.state else {
            Issue.record("expected a rate-limit failure"); return
        }
        #expect(!confirm, "a 429 was not processed")
        guard case .complete = try await coordinator.send(other.clipID).state else { Issue.record("expected completion"); return }
        #expect(limited.requests.count == 2)
    }

    @Test func failureLeavesTheClipIntactAndNeverFallsBack() async throws {
        let server = try await FakeHTTPServer { _ in .json(500, #"{"error":{"message":"decoder crashed","type":"server_error"}}"#) }
        let other = try await FakeHTTPServer { _ in .json(200, #"{"text":"fallback"}"#) }
        let calls = CallLog()
        let (coordinator, _) = try Self.coordinator(factoryCalls: calls)
        let clip = try Self.clip()
        let digest = SHA256Hex.of(clip.data)
        let primary = Self.config(server)
        _ = Self.config(other)  // a second configured service exists but is not this clip's choice
        _ = try await coordinator.request(clip, config: primary)
        let job = try await coordinator.grantAudioConsent(clip.clipID)
        guard case .failed(let kind, let message, let needsConfirmation) = job?.state else { Issue.record("expected failure"); return }
        #expect(kind == .serverError)
        // A 500 may come after the server started work, so the message says so (R2-04), and a resend needs confirmation (R4-04).
        #expect(message.contains("may or may not have been processed"))
        #expect(needsConfirmation)
        #expect(SHA256Hex.of(job!.clip.data) == digest)
        #expect(other.requests.isEmpty)
        #expect(Set(calls.calls.withLock { $0 }) == [primary.providerID])
    }

    @Test func oversizedClipIsRejectedBeforeUpload() async throws {
        let server = try await FakeHTTPServer { _ in .json(200, #"{"text":"x"}"#) }
        let provider = OpenAICompatibleTranscriptionProvider(config: Self.config(server), credentials: InMemoryCredentialStore(),
                                                             transport: URLSessionTransport(), limits: TranscriptionLimits(maxBytes: 1_000_000, maxDurationMs: 60_000))
        await #expect(throws: ProviderError.self) { try await provider.transcribe(try Self.clip()) }
        #expect(server.requests.isEmpty)
    }

    @Test func capabilityTestUploadsGeneratedSilenceOnly() async throws {
        let server = try await FakeHTTPServer { _ in .json(200, #"{"text":""}"#) }
        let provider = OpenAICompatibleTranscriptionProvider(config: Self.config(server, timestamps: false), credentials: InMemoryCredentialStore(),
                                                             transport: URLSessionTransport())
        let result = await SilentWAV.capabilityTest(provider)
        #expect((try? result.get())?.rawText == "")
        let parts = MultipartParts(body: try #require(server.requests.first).body, contentType: server.requests.first?.headers["content-type"] ?? "")
        let file = try #require(parts.files["file"])
        #expect(file.data == SilentWAV.make())
        #expect(file.data.count == 44 + 32_000)
        #expect(file.data.dropFirst(44).allSatisfy { $0 == 0 })
    }

    @Test func aTextChatConfigurationIsNeverUsedForAudio() async throws {
        let server = try await FakeHTTPServer { _ in .json(200, #"{"text":"x"}"#) }
        var chat = Self.config(server)
        chat.kind = .openAICompatibleChat
        let provider = OpenAICompatibleTranscriptionProvider(config: chat, credentials: InMemoryCredentialStore(), transport: URLSessionTransport())
        await #expect(throws: ProviderError(kind: .unsupportedDialect, acceptance: .notSent, host: "127.0.0.1",
                                            detail: "openai_compatible_chat endpoint used for transcription")) {
            try await provider.transcribe(try Self.clip())
        }
        #expect(server.requests.isEmpty, "a text-chat server is not assumed to accept audio (plan 10.4)")
    }

    /// Plan 18.1: segment times come from an untrusted server. Values that cannot be milliseconds within the clip are
    /// dropped and counted (an unchecked Double-to-Int conversion trapped on 1e300), never converted or trusted.
    @Test func hostileSegmentTimesAreDroppedNotTrapped() async throws {
        let body = #"{"text":"Book one.","segments":["#
            + #"{"start":0.0,"end":2.48,"text":"Book one."},"#
            + #"{"start":1e300,"end":1e300,"text":"huge"},"#
            + #"{"start":0.0,"end":1.7976931348623157e308,"text":"max double"},"#
            + #"{"start":-1.0,"end":2.0,"text":"negative"},"#
            + #"{"start":5.0,"end":4.0,"text":"backwards"},"#
            + #"{"start":9223372036854775807,"end":9223372036854775807,"text":"int max"},"#
            + #"{"start":179.5,"end":180.6,"text":"just past the clip, within tolerance"},"#
            + #"{"start":200.0,"end":210.0,"text":"after the clip"},"#
            + #"{"start":"1","end":"2","text":"strings"}]}"#
        let server = try await FakeHTTPServer { _ in .json(200, body) }
        let provider = OpenAICompatibleTranscriptionProvider(config: Self.config(server), credentials: InMemoryCredentialStore(),
                                                             transport: URLSessionTransport())
        let record = try await provider.transcribe(try Self.clip())  // a 180 s clip
        #expect(record.segments == [TranscriptSegment(startMs: 0, endMs: 2480, text: "Book one."),
                                    TranscriptSegment(startMs: 179_500, endMs: 180_600, text: "just past the clip, within tolerance")])
        #expect(record.discardedSegmentCount == 7)
        #expect(record.rawText == "Book one.", "the raw transcript is kept as sent")
    }

    /// Plan 14.5: the transcription response is bounded in size and time, like a text answer.
    @Test func oversizedOrTrickledTranscriptionResponsesAreRefused() async throws {
        let big = try await FakeHTTPServer { _ in .json(200, #"{"text":""# + String(repeating: "word ", count: 2_000) + #""}"#) }
        let small = OpenAICompatibleTranscriptionProvider(config: Self.config(big), credentials: InMemoryCredentialStore(), transport: URLSessionTransport(),
                                                          limits: TranscriptionLimits(maxResponseBytes: 4_000))
        await #expect(throws: ProviderError(kind: .responseSizeLimit, acceptance: .uncertain, host: "127.0.0.1", detail: "response body over the size limit")) {
            try await small.transcribe(try Self.clip())
        }
        let trickle = try await FakeHTTPServer { _ in
            FakeResponse(status: 200, headers: [("Content-Type", "application/json")],
                         steps: [.send(Data("{".utf8))] + Array(repeating: [FakeStep.pause(milliseconds: 50), .send(Data(" ".utf8))], count: 200).flatMap { $0 })
        }
        let started = ContinuousClock.now
        let slow = OpenAICompatibleTranscriptionProvider(config: Self.config(trickle), credentials: InMemoryCredentialStore(), transport: URLSessionTransport(),
                                                         limits: TranscriptionLimits(maxResponseDuration: .seconds(2)))
        await #expect(throws: ProviderError(kind: .responseTimeLimit, acceptance: .uncertain, host: "127.0.0.1", detail: "response body still arriving at the time limit")) {
            try await slow.transcribe(try Self.clip())
        }
        #expect(ContinuousClock.now - started < .seconds(8))
        #expect(big.requests.count == 1 && trickle.requests.count == 1)
    }

    @Test func hostileRetryAfterOnTheSpeechPathIsClamped() async throws {
        let server = try await FakeHTTPServer { _ in
            .json(429, #"{"error":{"message":"slow down","type":"rate_limit_error"}}"#, headers: [("Retry-After", "99999999999999999999")])
        }
        let provider = OpenAICompatibleTranscriptionProvider(config: Self.config(server), credentials: InMemoryCredentialStore(),
                                                             transport: URLSessionTransport())
        do {
            _ = try await provider.transcribe(try Self.clip())
            Issue.record("expected a rate-limit failure")
        } catch let error as ProviderError {
            #expect(error.kind == .rateLimited)
            #expect(error.retryAfter == RetryAfter.ceiling)
        }
    }

    /// ADR-0011: EndpointPolicy is enforced on the speech path too, in the provider (so no caller can skip it) and in
    /// the coordinator (so the user sees why before any consent is asked). A cleartext request to a name or a public
    /// address never leaves; the loopback rewrite would deliver it to the fake server if the policy were bypassed.
    @Test(arguments: ["http://localhost:8000/v1", "http://gateway.example.com/v1", "http://100.64.1.2:8000/v1", "http://8.8.8.8/v1"])
    func cleartextToANonLocalAddressIsRefusedOnTheSpeechPath(base: String) async throws {
        let server = try await FakeHTTPServer { _ in .json(200, #"{"text":"should never be sent"}"#) }
        var config = Self.config(server)
        config.baseURL = try BaseURL.normalize(base)
        config.allowInsecureLocalHTTP = true
        let provider = OpenAICompatibleTranscriptionProvider(config: config, credentials: InMemoryCredentialStore(),
                                                             transport: LoopbackRewriteTransport(target: server.baseURL))
        do {
            _ = try await provider.transcribe(try Self.clip())
            Issue.record("the provider must refuse \(base)")
        } catch let error as ProviderError {
            #expect(error.kind == .insecureEndpointRejected)
            #expect(error.acceptance == .notSent)
        }

        let coordinator = try TranscriptionCoordinator(store: try FileTranscriptionQueueStore(directory: TestPacks.temporaryDirectory()), providerFactory: { config in
            OpenAICompatibleTranscriptionProvider(config: config, credentials: InMemoryCredentialStore(),
                                                  transport: LoopbackRewriteTransport(target: server.baseURL))
        }, connectivity: FakeConnectivity(online: true))
        let job = try await coordinator.request(try Self.clip(), config: config)
        guard case .failed(let kind, let message, let needsConfirmation) = job.state else { Issue.record("expected refusal, got \(job.state)"); return }
        #expect(kind == .insecureEndpointRejected)
        #expect(!needsConfirmation, "nothing was sent")
        #expect(message.contains("without encryption"))
        #expect(server.requests.isEmpty, "nothing was uploaded to \(base)")
    }

    @Test func capabilityTestClassifiesATextOnlyServer() async throws {
        // A chat-only server has no transcription route: the speech test reports the dialect, not "AI failed".
        let server = try await FakeHTTPServer { _ in .json(404, #"{"error":"Unexpected endpoint or method. (POST /v1/audio/transcriptions)"}"#) }
        let provider = OpenAICompatibleTranscriptionProvider(config: Self.config(server), credentials: InMemoryCredentialStore(), transport: URLSessionTransport())
        let result = await SilentWAV.capabilityTest(provider)
        guard case .failure(let error) = result else { Issue.record("expected failure"); return }
        #expect(error.kind == .unsupportedDialect)
    }
}
