import Foundation

public enum AskError: Error, Equatable, Sendable {
    case notFound
    case invalidState(AskState)
    case consentRequired
    case resubmitNeedsConfirmation
    /// The configuration is refused by EndpointPolicy (the message says why).
    case endpointRejected(String)
    /// The ContextPack names a different destination than the configuration the request would go to, so the
    /// disclosure and the audit record would be wrong (plan 11.2, 14.2). Rebuild the pack for this configuration.
    case endpointMismatch
    /// The ContextPack holds text after its own spoiler boundary (plan 13.3, 20.3); it is never stored or sent.
    case packViolatesSpoilerBoundary
    /// The ContextPack resends an earlier turn that went to a different destination, or one still carrying a citation
    /// marker from its own pack (`ContextPack.historyViolations`); it is never stored or sent.
    case packHistoryInvalid
    /// A record already exists for this pack's request ID, holding a different pack. A request ID names one question
    /// and its pack; the stored record is kept unchanged. Build a new pack (it gets a new request ID) to ask again.
    case requestAlreadyExists
}

/// Client-side bounds on one streamed answer (plan 14.5: cap output sizes rather than allow unbounded jobs). A buggy
/// or hostile endpoint, including any server on the user's network, could otherwise stream without end; each
/// checkpoint rewrites the record, so unbounded text would also mean unbounded storage writes.
public struct OutputLimits: Sendable, Equatable {
    /// Answer plus refusal characters accepted per requested output token. Real tokens average about four characters
    /// of English, so 16 leaves a wide margin for any honest model while still bounding a runaway stream.
    public var charactersPerOutputToken: Int
    /// Floor for small output budgets.
    public var minimumCharacters: Int
    /// Wall-clock limit for one attempt, measured on the coordinator's clock from the moment the request leaves.
    public var maxAttemptDuration: TimeInterval

    public init(charactersPerOutputToken: Int = 16, minimumCharacters: Int = 32_768, maxAttemptDuration: TimeInterval = 600) {
        self.charactersPerOutputToken = charactersPerOutputToken
        self.minimumCharacters = minimumCharacters
        self.maxAttemptDuration = maxAttemptDuration
    }

    public func maxCharacters(forOutputTokens tokens: Int) -> Int {
        let (product, overflow) = max(0, tokens).multipliedReportingOverflow(by: charactersPerOutputToken)
        return max(minimumCharacters, overflow ? Int.max : product)
    }
}

public struct CheckpointPolicy: Sendable, Equatable {
    /// Persist partial output after this many new characters…
    public var characters: Int
    /// …or after this much time since the last checkpoint, whichever comes first.
    public var interval: TimeInterval

    public init(characters: Int = 400, interval: TimeInterval = 1.0) {
        self.characters = characters
        self.interval = interval
    }
}

public enum StopReason: Sendable, Equatable {
    /// The user tapped Cancel.
    case user
    /// The app is being suspended or the view went away; foreground-only work stops (plan 14.4).
    case suspension
}

/// Runs one question through the lifecycle (plan 14.4):
/// draft → awaiting_consent → ready → sending → streaming → complete, or cancelled, interrupted,
/// failed_retryable, failed_final.
///
/// Guarantees exercised by tests:
/// - The question and ContextPack are persisted (state draft) before anything is sent, and the record is
///   persisted again in `sending` before the request leaves.
/// - Partial output is checkpointed during streaming; a record found in `sending`/`streaming` after a relaunch
///   becomes `interrupted` ("Interrupted · partial answer") or `failed_retryable`.
/// - Transient failures that certainly were not accepted are retried with capped backoff and Retry-After;
///   a generation whose acceptance is uncertain is never replayed without the user's confirmation.
/// - Retries reuse the same record: the question is stored and sent once per attempt, never duplicated.
/// - A request ID has one record. `createDraft` for a request that already has one returns it unchanged, so a second
///   tap on Ask never resets an answered, failed or in-flight request to "Draft · not sent" (plan 11.1, 14.4, 14.5).
/// - Offline submission leaves a draft ("Draft · not sent"); nothing is sent later without the user.
/// - There is exactly one provider per record. Nothing falls back to another provider.
public actor AskCoordinator {
    let store: any AskStore
    let providerFactory: @Sendable (ProviderConfig) -> any TextGenerationProvider
    let connectivity: any ConnectivityProbe
    let sleeper: any Sleeper
    let clock: any AIClock
    let retry: RetryPolicy
    let checkpoint: CheckpointPolicy
    let outputLimits: OutputLimits
    let log: any AILogSink
    let random: @Sendable () -> Double

    public private(set) var consent: ConsentLedger
    var records: [UUID: AskRecord] = [:]
    var pendingDisclosures: [UUID: Disclosure] = [:]
    var running: [UUID: Task<Void, Never>] = [:]
    /// Backoff waits in progress, so a stop during the wait takes effect.
    var waiting: [UUID: Task<Void, any Error>] = [:]
    var stopReasons: [UUID: StopReason] = [:]
    /// Records with a `send` in progress. A second `send` for the same record is refused, so a double tap or a
    /// retry racing the first call can never put the question on the wire twice.
    var inFlight: Set<UUID> = []
    /// Drafts being created. A second `createDraft` for the same request waits for the first instead of writing.
    var drafting: [UUID: Task<AskRecord, any Error>] = [:]
    var lastCheckpoint: [UUID: (Date, Int)] = [:]

    public init(store: any AskStore, consent: ConsentLedger = ConsentLedger(),
                providerFactory: @escaping @Sendable (ProviderConfig) -> any TextGenerationProvider,
                connectivity: any ConnectivityProbe, sleeper: any Sleeper = TaskSleeper(), clock: any AIClock = SystemClock(),
                retry: RetryPolicy = RetryPolicy(), checkpoint: CheckpointPolicy = CheckpointPolicy(), outputLimits: OutputLimits = OutputLimits(),
                log: any AILogSink = NullLogSink(), random: @escaping @Sendable () -> Double = { Double.random(in: 0...1) }) {
        self.store = store
        self.consent = consent
        self.providerFactory = providerFactory
        self.connectivity = connectivity
        self.sleeper = sleeper
        self.clock = clock
        self.retry = retry
        self.checkpoint = checkpoint
        self.outputLimits = outputLimits
        self.log = log
        self.random = random
    }

    // MARK: Draft and consent

    /// The destination `config` resolves to. Disclosure, consent and the stored pack all use this identity, so the
    /// origin the user approved is the origin the request goes to.
    static func destination(_ config: ProviderConfig) throws(AskError) -> EndpointIdentity {
        do { return try EndpointIdentity.of(config) } catch { throw AskError.endpointRejected(error.userMessage) }
    }

    /// Refuses a record whose pack does not describe the request that would be sent: a different destination than
    /// its configuration, text after its own spoiler boundary, or an earlier turn that went elsewhere or still carries
    /// a citation marker. Checked when the draft is created and again before consent and before sending, because
    /// records are reloaded from storage.
    static func validate(pack: ContextPack, config: ProviderConfig) throws(AskError) {
        guard pack.endpoint == (try destination(config)) else { throw AskError.endpointMismatch }
        guard pack.spoilerBoundaryViolations.isEmpty else { throw AskError.packViolatesSpoilerBoundary }
        guard pack.historyViolations.isEmpty else { throw AskError.packHistoryInvalid }
    }

    /// Persists the question and ContextPack as a draft. Nothing is sent.
    ///
    /// The pack's request ID is the request's identity (A.4: `AIService.send(contextPack, …)`). If a record already
    /// exists for it, in memory or on disk and in any state, that record is returned unchanged: an answered request
    /// keeps its answer and attempts, and a request that may already be on the wire never reads "Draft · not sent"
    /// (after a relaunch such a draft could be sent again without the confirmation an uncertain generation needs). A
    /// different pack under an existing request ID is refused (`requestAlreadyExists`). The in-memory checks run
    /// before the first suspension point and concurrent calls for one request share one creation, so two calls never
    /// both write.
    public func createDraft(pack: ContextPack, config: ProviderConfig) async throws -> AskRecord {
        try Self.validate(pack: pack, config: config)
        let id = pack.requestID
        let creation: Task<AskRecord, any Error>
        if let pending = drafting[id] {
            creation = pending
        } else if let cached = records[id] {
            return try existingRecord(cached, for: pack)
        } else {
            creation = Task { try await self.storeDraftIfNew(pack: pack, config: config) }
            drafting[id] = creation
        }
        let result = await creation.result
        if drafting[id] == creation { drafting[id] = nil }
        return try existingRecord(try result.get(), for: pack)
    }

    /// The record for `pack.requestID`: the stored one if there is one, otherwise a new draft, durable before it is
    /// returned. Runs once per request at a time (`drafting`).
    func storeDraftIfNew(pack: ContextPack, config: ProviderConfig) async throws -> AskRecord {
        let id = pack.requestID
        if let stored = try await store.load(id) {
            // A `send` may have loaded and changed it meanwhile; the cached copy is then the current one.
            if let cached = records[id] { return cached }
            records[id] = stored
            return stored
        }
        if let cached = records[id] { return cached }
        let now = clock.now()
        let record = AskRecord(id: id, conversationID: pack.conversationID, question: pack.question, pack: pack, config: config,
                               state: .draft, answerText: "", refusalText: "", outcome: nil, usage: nil, attempts: [], failure: nil,
                               queuedOffline: false, reasoningOmitted: false, toolCallRejected: false, checkpointCount: 0,
                               createdAt: now, updatedAt: now)
        do {
            try await persist(record)
        } catch {
            // Not durable: forget it, so nothing treats an unsaved draft as stored.
            if records[id]?.state == .draft, records[id]?.attempts.isEmpty == true { records[id] = nil }
            throw error
        }
        log.record(AILogEvent("ask.draft", ["scope": pack.scope.rawValue, "evidence": String(pack.evidence.count)]))
        return records[id] ?? record
    }

    /// An existing record is returned unchanged for the same pack; a different pack under its request ID is refused.
    func existingRecord(_ record: AskRecord, for pack: ContextPack) throws(AskError) -> AskRecord {
        guard record.pack == pack else { throw AskError.requestAlreadyExists }
        return record
    }

    /// Checks consent for the record's destination and scope: `ready`, or `awaiting_consent` with a disclosure.
    public func prepare(_ id: UUID) async throws -> AskRecord {
        var record = try await load(id)
        guard [.draft, .awaitingConsent, .ready].contains(record.state) else { throw AskError.invalidState(record.state) }
        try Self.validate(pack: record.pack, config: record.config)
        switch consent.evaluate(pack: record.pack, providerID: record.config.providerID) {
        case .granted:
            record.state = .ready
            pendingDisclosures[id] = nil
        case .required(let disclosure):
            record.state = .awaitingConsent
            pendingDisclosures[id] = disclosure
        }
        try await persist(record)
        return record
    }

    public func disclosure(for id: UUID) -> Disclosure? { pendingDisclosures[id] }

    /// The user confirmed the disclosure shown for this record.
    public func grantConsent(_ id: UUID) async throws -> AskRecord {
        var record = try await load(id)
        guard record.state == .awaitingConsent, let disclosure = pendingDisclosures[id] else { throw AskError.invalidState(record.state) }
        consent.grant(disclosure, providerID: record.config.providerID, at: clock.now())
        pendingDisclosures[id] = nil
        record.state = .ready
        try await persist(record)
        return record
    }

    // MARK: Sending

    /// Sends a ready record and runs it to a terminal state (or back to draft when offline).
    /// From `failed_retryable`, `interrupted` or `cancelled`, `userConfirmedResubmit` is required whenever the
    /// last attempt may have been accepted or produced output.
    @discardableResult
    public func send(_ id: UUID, userConfirmedResubmit: Bool = false) async throws -> AskRecord {
        // Claimed before the first suspension point, so a concurrent call sees it.
        guard !inFlight.contains(id) else { throw AskError.invalidState(.sending) }
        inFlight.insert(id)
        stopReasons[id] = nil
        defer {
            inFlight.remove(id)
            stopReasons[id] = nil
        }
        var record = try await load(id)
        switch record.state {
        case .ready, .draft:
            break
        case .awaitingConsent:
            throw AskError.consentRequired
        case .failedRetryable, .interrupted, .cancelled:
            let uncertain = record.failure?.resubmitNeedsConfirmation ?? false
            if (uncertain || !record.answerText.isEmpty || record.state == .interrupted) && !userConfirmedResubmit {
                throw AskError.resubmitNeedsConfirmation
            }
        default:
            throw AskError.invalidState(record.state)
        }
        // The pack must still describe this request, and consent is re-checked at send time: a draft may never have
        // been prepared, and the destination or scope may have changed since prepare.
        try Self.validate(pack: record.pack, config: record.config)
        if case .required(let disclosure) = consent.evaluate(pack: record.pack, providerID: record.config.providerID) {
            pendingDisclosures[id] = disclosure
            record.state = .awaitingConsent
            try await persist(record)
            throw AskError.consentRequired
        }
        guard connectivity.isOnline else {
            record.state = .draft
            record.queuedOffline = true
            try await persist(record)
            log.record(AILogEvent("ask.offline_draft"))
            return record
        }
        record.queuedOffline = false
        if !record.answerText.isEmpty, let last = record.attempts.indices.last {
            record.attempts[last].supersededPartialText = record.answerText
        }
        record.answerText = ""
        record.refusalText = ""
        record.outcome = nil
        record.failure = nil

        let maxOutput = record.pack.budget.outputReserveTokens
        let request = PromptTemplate.request(for: record.pack, maxOutputTokens: maxOutput)
        var autoAttempt = 0
        while true {
            autoAttempt += 1
            record.attempts.append(AttemptRecord(number: record.attempts.count + 1, startedAt: clock.now()))
            record.state = .sending
            try await persist(record)  // durable before the request leaves
            // A stop that arrived while the record was being written: the request has not left the device.
            if let stop = stopReasons.removeValue(forKey: id) {
                let host = record.pack.endpoint.host
                record.state = stop == .user ? .cancelled : .failedRetryable
                record.failure = FailureSummary(kind: .cancelled, acceptance: .notSent,
                                                userMessage: stop == .user ? "Cancelled before sending. Nothing was sent to \(host)."
                                                    : "Stopped before sending. Nothing was sent to \(host).",
                                                retryAfterMs: nil, resubmitNeedsConfirmation: false)
                closeAttempt(&record, failure: ProviderError(kind: .cancelled, acceptance: .notSent, host: host))
                try await persist(record)
                return record
            }
            log.record(AILogEvent("ask.sending", ["attempt": String(record.attempts.count), "host": record.pack.endpoint.host]))

            let provider = providerFactory(record.config)
            let stream = provider.streamGeneration(request)
            let task = Task { await self.consume(id, stream) }
            running[id] = task
            await task.value
            running[id] = nil
            record = records[id] ?? record

            if let stop = stopReasons[id] {
                stopReasons[id] = nil
                record.state = stop == .user ? .cancelled : .interrupted
                if record.outcome == nil { record.outcome = record.hasAnswerText ? .partial : nil }
                if !record.hasAnswerText {
                    // No output, but the request may already have left: never show "Draft · not sent" here, and
                    // ask before resubmitting (the provider may have accepted and billed it).
                    record.state = stop == .user ? .cancelled : .failedRetryable
                    record.failure = FailureSummary(kind: .cancelled, acceptance: .uncertain,
                                                    userMessage: stop == .user
                                                        ? "Cancelled before an answer arrived. The request may have reached \(record.pack.endpoint.host)."
                                                        : "Stopped before an answer arrived. The request may have reached \(record.pack.endpoint.host).",
                                                    retryAfterMs: nil, resubmitNeedsConfirmation: true)
                }
                closeAttempt(&record, failure: nil)
                try await persist(record)
                return record
            }
            if record.state.isTerminal {
                // A final event that ended without an answer (`apply`) records its failure on the attempt too.
                let host = record.pack.endpoint.host
                let ended = record.failure.map { ProviderError(kind: $0.kind, acceptance: $0.acceptance, host: host) }
                closeAttempt(&record, failure: ended)
                try await persist(record)
                return record
            }
            // The stream ended without a terminal state: an error was recorded in `failure`.
            guard let failure = record.failure else {
                record.state = record.hasAnswerText ? .interrupted : .failedRetryable
                record.failure = FailureSummary(kind: .invalidResponse, acceptance: .uncertain,
                                                userMessage: "The answer stopped without a final event.", retryAfterMs: nil,
                                                resubmitNeedsConfirmation: true)
                closeAttempt(&record, failure: nil)
                try await persist(record)
                return record
            }
            let error = lastErrors[id]
            lastErrors[id] = nil
            if let error, error.isTransient, record.answerText.isEmpty,
               let delay = retry.delay(afterAttempt: autoAttempt, retryAfter: error.retryAfter, random: random()) {
                closeAttempt(&record, failure: error)
                record.failure = nil
                record.state = .sending
                try await persist(record)
                log.record(AILogEvent("ask.retry_wait", ["ms": String(delay.wholeMilliseconds)]))
                // The wait can be stopped by the user (stop(_:reason:)) or by cancelling the caller. A stop that
                // arrived while the record was being written skips the wait.
                var slept = false
                if stopReasons[id] == nil {
                    let sleeper = sleeper
                    let wait = Task { try await sleeper.sleep(for: delay) }
                    waiting[id] = wait
                    do {
                        try await withTaskCancellationHandler { try await wait.value } onCancel: { wait.cancel() }
                        slept = true
                    } catch {
                        slept = false
                    }
                    waiting[id] = nil
                }
                let stop = stopReasons.removeValue(forKey: id)
                if stop != nil || !slept {
                    // Every earlier attempt was refused before generating, so nothing is pending at the provider.
                    record.state = stop == .user ? .cancelled : .failedRetryable
                    record.failure = FailureSummary(kind: .cancelled, acceptance: .notSent,
                                                    userMessage: "Retry stopped. \(record.pack.endpoint.host) refused the earlier attempt before answering, so nothing is pending.",
                                                    retryAfterMs: nil, resubmitNeedsConfirmation: false)
                    try await persist(record)
                    return record
                }
                continue
            }
            record.state = Self.terminalState(for: failure, hasOutput: record.hasAnswerText)
            if record.hasAnswerText { record.outcome = .partial }
            closeAttempt(&record, failure: error)
            try await persist(record)
            return record
        }
    }

    var lastErrors: [UUID: ProviderError] = [:]

    static func terminalState(for failure: FailureSummary, hasOutput: Bool) -> AskState {
        if hasOutput { return .interrupted }
        switch failure.kind {
        case .dns, .hostUnreachable, .offline, .rateLimited, .serverError, .timeout, .connectionLost, .localNetworkPermissionDenied,
             .providerStreamError, .invalidResponse, .cancelled, .responseSizeLimit, .responseTimeLimit:
            return .failedRetryable
        default:
            return .failedFinal
        }
    }

    func closeAttempt(_ record: inout AskRecord, failure: ProviderError?) {
        guard let last = record.attempts.indices.last else { return }
        record.attempts[last].endedAt = clock.now()
        if let failure {
            record.attempts[last].failureKind = failure.kind
            record.attempts[last].acceptance = failure.acceptance
            record.attempts[last].httpStatus = failure.httpStatus
        }
    }

    /// Consumes one attempt's stream, updating the cached record and checkpointing.
    func consume(_ id: UUID, _ stream: AsyncThrowingStream<GenerationEvent, any Error>) async {
        guard var record = records[id] else { return }
        let started = clock.now()
        lastCheckpoint[id] = (started, 0)
        let maxCharacters = outputLimits.maxCharacters(forOutputTokens: record.pack.budget.outputReserveTokens)
        var receivedCharacters = 0
        // Output caps (plan 14.5): stop reading a runaway stream; what arrived within the caps is kept and labelled
        // partial, and nothing is resent automatically (the provider may have generated and billed it).
        func stopAtCap(_ kind: FailureKind) {
            let error = ProviderError(kind: kind, acceptance: .uncertain, host: record.pack.endpoint.host)
            lastErrors[id] = error
            record.failure = FailureSummary(kind: error.kind, acceptance: error.acceptance, userMessage: error.userMessage,
                                            retryAfterMs: nil, resubmitNeedsConfirmation: true)
            log.record(AILogEvent("ask.output_cap", ["kind": error.kind.rawValue, "characters": String(receivedCharacters)]))
        }
        do {
            for try await event in stream {
                if stopReasons[id] != nil { break }
                // Size: text that would take the answer past the cap is not stored.
                if case .text(let text) = event { receivedCharacters += text.count }
                if case .refusal(let text) = event { receivedCharacters += text.count }
                if receivedCharacters > maxCharacters {
                    stopAtCap(.responseSizeLimit)
                    break
                }
                switch event {
                case .status(.accepted):
                    if record.state == .sending { record.state = .streaming; records[id] = record; try? await persist(record) }
                case .status(.reasoningOmitted):
                    record.reasoningOmitted = true
                case .status(.toolCallRejected):
                    record.toolCallRejected = true
                case .status(.finishReasonMissing), .status(.delivery):
                    break
                case .text(let text):
                    if record.state == .sending { record.state = .streaming }
                    record.answerText += text
                    records[id] = record
                    await checkpointIfDue(id, &record)
                case .refusal(let text):
                    if record.state == .sending { record.state = .streaming }
                    record.refusalText += text
                case .usage(let usage):
                    record.usage = usage
                case .finished(let reason):
                    apply(reason, to: &record)
                }
                records[id] = record
                // Duration: checked as each event arrives, after it is kept (it arrived before Sylvia stopped
                // reading). Silence is bounded by the transport's idle timeout, and the HTTP adapter applies its own
                // whole-body deadline even to keepalive comments that never become events (StreamLimits).
                if !record.state.isTerminal, clock.now().timeIntervalSince(started) > outputLimits.maxAttemptDuration {
                    stopAtCap(.responseTimeLimit)
                    break
                }
            }
        } catch {
            let classified = ErrorClassifier.classify(error, host: record.pack.endpoint.host, bodyMayHaveBeenSent: true)
            if stopReasons[id] == nil && classified.kind != .cancelled {
                lastErrors[id] = classified
                record.failure = FailureSummary(kind: classified.kind, acceptance: classified.acceptance, userMessage: classified.userMessage,
                                                retryAfterMs: classified.retryAfter.map(\.wholeMilliseconds),
                                                resubmitNeedsConfirmation: classified.acceptance == .uncertain)
            }
        }
        records[id] = record
    }

    /// Maps the provider's final event to the record's state and outcome (I-04): only a normal end with answer text is
    /// complete; a stop after some answer text is a labelled partial answer; a stop before any answer text is shown
    /// neither as an answer nor as a partial one.
    func apply(_ reason: FinishReason, to record: inout AskRecord) {
        let host = record.pack.endpoint.host
        let hasAnswer = record.hasAnswerText
        let hasRefusal = AskRecord.isVisibleText(record.refusalText)
        // The provider ended the generation, so it may have been billed: a resend needs the user's confirmation.
        func fail(_ state: AskState, _ outcome: AnswerOutcome, _ kind: FailureKind, _ message: String) {
            record.state = state
            record.outcome = outcome
            record.failure = FailureSummary(kind: kind, acceptance: .uncertain, userMessage: message, retryAfterMs: nil,
                                            resubmitNeedsConfirmation: true)
        }
        switch reason {
        case .complete:
            if hasAnswer {
                record.state = .complete
                record.outcome = .answer
            } else if hasRefusal {
                record.state = .complete
                record.outcome = .refusal
            } else {
                // A normal end with no answer text: reasoning only, a `<think>` block only, or `[DONE]` alone.
                fail(.failedRetryable, .noAnswerText, .invalidResponse, record.reasoningOmitted
                     ? "\(host) sent only its reasoning and no answer text. Models that reason first may need a larger maximum output for this endpoint."
                     : "\(host) ended its reply without any answer text. If the model reasons first, it may need a larger maximum output for this endpoint.")
            }
        case .refused:
            // Text before a refusal stop is cut off where the provider stopped it: a partial answer.
            record.state = hasAnswer ? .interrupted : .complete
            record.outcome = .refusal
        case .contentFiltered:
            // The provider omitted content, so any text before the stop is truncated.
            record.state = hasAnswer ? .interrupted : .complete
            record.outcome = .contentFiltered
        case .outputLimit:
            if hasAnswer {
                record.state = .interrupted
                record.outcome = .outputLimit
            } else {
                fail(.failedRetryable, .outputLimit, .invalidResponse,
                     "\(host) reached the maximum output for this endpoint before any answer text. Models that reason first may need a larger maximum output.")
            }
        case .contextWindowExceeded:
            if hasAnswer {
                record.state = .interrupted
                record.outcome = .contextWindowExceeded
            } else {
                fail(.failedFinal, .contextWindowExceeded, .contextTooLong,
                     ProviderError(kind: .contextTooLong, acceptance: .uncertain, host: host).userMessage)
            }
        case .toolCallRejected:
            fail(.failedFinal, .toolCallRejected, .invalidResponse,
                 "The model asked to run a tool. Sylvia doesn't run tools, so the answer stopped there.")
        case .incomplete:
            if hasAnswer {
                record.state = .interrupted
                record.outcome = .incomplete
            } else {
                fail(.failedRetryable, .incomplete, .invalidResponse, "\(host) stopped before sending any answer text.")
            }
        }
    }

    func checkpointIfDue(_ id: UUID, _ record: inout AskRecord) async {
        let (lastTime, lastLength) = lastCheckpoint[id] ?? (clock.now(), 0)
        let grown = record.answerText.count - lastLength
        guard grown >= checkpoint.characters || clock.now().timeIntervalSince(lastTime) >= checkpoint.interval else { return }
        record.checkpointCount += 1
        records[id] = record
        try? await persist(record)
        lastCheckpoint[id] = (clock.now(), record.answerText.count)
    }

    // MARK: Stopping and recovery

    /// Stops a request whose `send` is in progress, at whatever point it has reached: before the request leaves,
    /// while streaming, or during a backoff wait. Partial output is kept and labelled; nothing is retried
    /// automatically. A stop for a record with no `send` in progress does nothing.
    public func stop(_ id: UUID, reason: StopReason) {
        guard inFlight.contains(id) else { return }
        stopReasons[id] = reason
        running[id]?.cancel()
        waiting[id]?.cancel()
    }

    /// Stops every request whose `send` is in progress (plan 14.4: AI requests are foreground work). The app calls
    /// this with `.suspension` when its scene leaves the foreground, inside a background task so the interrupted
    /// records are written before the process is suspended. Returns the ids it stopped.
    @discardableResult
    public func stopAll(reason: StopReason) -> [UUID] {
        let ids = inFlight.sorted { $0.uuidString < $1.uuidString }
        for id in ids { stop(id, reason: reason) }
        log.record(AILogEvent("ask.stop_all", ["reason": reason == .user ? "user" : "suspension", "count": String(ids.count)]))
        return ids
    }

    /// Waits until no `send` is in progress (bounded by `timeout`), so a caller that stopped everything can end its
    /// background task once the records are durable. Returns false if work is still running at the timeout.
    public func waitUntilIdle(timeout: Duration = .seconds(5)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !inFlight.isEmpty {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    /// After a relaunch, a record left in `sending` or `streaming` is reconciled: with partial output it becomes
    /// `interrupted`; without, `failed_retryable` with resubmission needing confirmation (acceptance uncertain).
    public func reconcileAfterLaunch() async throws -> [AskRecord] {
        var changed: [AskRecord] = []
        for var record in try await store.all() where record.state == .sending || record.state == .streaming {
            if !record.hasAnswerText {
                record.state = .failedRetryable
                record.failure = FailureSummary(kind: .connectionLost, acceptance: .uncertain,
                                                userMessage: "Sylvia closed before an answer arrived. The request may have reached \(record.pack.endpoint.host).",
                                                retryAfterMs: nil, resubmitNeedsConfirmation: true)
            } else {
                record.state = .interrupted
                record.outcome = .partial
            }
            try await persist(record)
            changed.append(record)
        }
        return changed
    }

    public func record(_ id: UUID) async throws -> AskRecord { try await load(id) }

    func load(_ id: UUID) async throws -> AskRecord {
        if let cached = records[id] { return cached }
        guard let stored = try await store.load(id) else { throw AskError.notFound }
        records[id] = stored
        return stored
    }

    func persist(_ record: AskRecord) async throws {
        var record = record
        record.updatedAt = clock.now()
        records[record.id] = record
        try await store.save(record)
    }
}

extension Duration {
    /// Whole milliseconds, rounded down (Retry-After values and log fields).
    var wholeMilliseconds: Int {
        Int(components.seconds) * 1000 + Int(components.attoseconds / 1_000_000_000_000_000)
    }
}
