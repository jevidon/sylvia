import Foundation
import G05TestSupport
import Synchronization
import Testing
@testable import SylviaAI

/// Brief item 3 / plan 14.4 / T33: request lifecycle, persistence before sending, checkpoints, retries,
/// interruption, offline drafts and no fallback.
@Suite("Request lifecycle")
struct LifecycleTests {
    static let localConfig = ProviderConfig(kind: .openAICompatibleChat, displayName: "Local", baseURL: URL(string: "http://127.0.0.1:1234/v1")!,
                                            model: "local-model", credential: nil, allowInsecureLocalHTTP: true)

    struct Harness {
        let directory: URL
        let store: FileAskStore
        let provider: ScriptedProvider
        let coordinator: AskCoordinator
        let sleeper: RecordingSleeper
        let clock: ManualClock
        let connectivity: FakeConnectivity

        init(scripts: [[ScriptedProvider.Step]], online: Bool = true, consent: ConsentLedger = ConsentLedger(),
             retry: RetryPolicy = RetryPolicy(jitter: false), checkpoint: CheckpointPolicy = CheckpointPolicy(characters: 10, interval: 60),
             clock: ManualClock = ManualClock(), outputLimits: OutputLimits = OutputLimits(),
             directory: URL = TestPacks.temporaryDirectory()) throws {
            self.directory = directory
            store = try FileAskStore(directory: directory)
            let provider = ScriptedProvider(config: LifecycleTests.localConfig, scripts: scripts)
            self.provider = provider
            sleeper = RecordingSleeper()
            self.clock = clock
            connectivity = FakeConnectivity(online: online)
            coordinator = AskCoordinator(store: store, consent: consent, providerFactory: { _ in provider }, connectivity: connectivity,
                                         sleeper: sleeper, clock: clock, retry: retry, checkpoint: checkpoint, outputLimits: outputLimits)
        }

        /// Draft, prepare, grant consent; returns the record id ready to send.
        func ready(_ pack: ContextPack = TestPacks.make(config: LifecycleTests.localConfig)) async throws -> UUID {
            _ = try await coordinator.createDraft(pack: pack, config: LifecycleTests.localConfig)
            let prepared = try await coordinator.prepare(pack.requestID)
            if prepared.state == .awaitingConsent { _ = try await coordinator.grantConsent(pack.requestID) }
            return pack.requestID
        }

        func reloaded(_ id: UUID) async throws -> AskRecord? { try await FileAskStore(directory: directory).load(id) }
    }

    static func text(_ s: String) -> ScriptedProvider.Step { .event(.text(s)) }
    static let accepted = ScriptedProvider.Step.event(.status(.accepted(responseID: "r1", model: "local-model")))
    static let done = ScriptedProvider.Step.event(.finished(.complete))

    static func countOccurrences(_ needle: String, in request: GenerationRequest) -> Int {
        request.messages.map { $0.text.components(separatedBy: needle).count - 1 }.reduce(0, +)
    }

    @Test func draftPersistsQuestionAndPackAndSendsNothing() async throws {
        let h = try Harness(scripts: [])
        let pack = TestPacks.make(config: Self.localConfig)
        let draft = try await h.coordinator.createDraft(pack: pack, config: Self.localConfig)
        #expect(draft.state == .draft)
        #expect(draft.statusPhrase == "Draft · not sent")
        let stored = try #require(try await h.reloaded(pack.requestID))
        #expect(stored.question == pack.question)
        #expect(stored.pack == pack)
        #expect(stored.pack.digestIsValid)
        #expect(h.provider.requests.isEmpty)
    }

    @Test func consentIsRequiredBeforeTheFirstRequest() async throws {
        let h = try Harness(scripts: [[Self.accepted, Self.text("Answer [c1]."), Self.done]])
        let pack = TestPacks.make(config: Self.localConfig)
        _ = try await h.coordinator.createDraft(pack: pack, config: Self.localConfig)
        let prepared = try await h.coordinator.prepare(pack.requestID)
        #expect(prepared.state == .awaitingConsent)
        let disclosure = try #require(await h.coordinator.disclosure(for: pack.requestID))
        #expect(disclosure.reasons == [.firstRequest])
        #expect(disclosure.lines[0] == "Destination: 127.0.0.1 · local · local-model")
        #expect(disclosure.lines[1] == "What is sent: your question, 1 selected passage from Walden. Nothing else from your library is sent.")
        #expect(!disclosure.lines.joined().contains("Secure") && !disclosure.lines.joined().contains("Private"))
        await #expect(throws: AskError.consentRequired) { try await h.coordinator.send(pack.requestID) }
        #expect(h.provider.requests.isEmpty, "nothing is sent before consent")
        _ = try await h.coordinator.grantConsent(pack.requestID)
        let done = try await h.coordinator.send(pack.requestID)
        #expect(done.state == .complete)
        #expect(done.outcome == .answer)
        #expect(done.answerText == "Answer [c1].")
        #expect(done.statusPhrase == "Complete")
    }

    /// T31 / I-07: `send` accepts a record still in `draft`. For a draft that was never prepared, the send-time consent
    /// check is the only thing between the user's question and the network, so it is tested on its own.
    @Test func draftSentWithoutPrepareNeedsConsentAndSendsNothing() async throws {
        let h = try Harness(scripts: [[Self.accepted, Self.text("Answer [c1]."), Self.done]])
        let pack = TestPacks.make(config: Self.localConfig)
        _ = try await h.coordinator.createDraft(pack: pack, config: Self.localConfig)
        await #expect(throws: AskError.consentRequired) { try await h.coordinator.send(pack.requestID) }
        #expect(h.provider.requests.isEmpty, "no unapproved content transmission")
        #expect(try await h.reloaded(pack.requestID)?.state == .awaitingConsent)
        let disclosure = try #require(await h.coordinator.disclosure(for: pack.requestID))
        #expect(disclosure.reasons == [.firstRequest])
        #expect(disclosure.lines[0] == "Destination: 127.0.0.1 · local · local-model")
        _ = try await h.coordinator.grantConsent(pack.requestID)
        #expect(try await h.coordinator.send(pack.requestID).state == .complete)
        #expect(h.provider.requests.count == 1)
    }

    /// T31: consent given at prepare time does not survive a change of destination before the send. Here the same
    /// provider entry is moved to another address (and that change approved for another request) between prepare and
    /// send of the first request; the first request now needs consent for its own destination again.
    @Test func destinationChangeBetweenPrepareAndSendNeedsConsentAgain() async throws {
        let h = try Harness(scripts: [[Self.accepted, Self.text("ok"), Self.done]])
        let first = TestPacks.make(config: Self.localConfig)
        _ = try await h.ready(first)
        #expect(try await h.coordinator.record(first.requestID).state == .ready)

        var moved = Self.localConfig
        moved.baseURL = URL(string: "http://192.168.1.20:1234/v1")!
        let second = TestPacks.make(config: moved)
        _ = try await h.coordinator.createDraft(pack: second, config: moved)
        #expect(try await h.coordinator.prepare(second.requestID).state == .awaitingConsent)
        _ = try await h.coordinator.grantConsent(second.requestID)

        await #expect(throws: AskError.consentRequired) { try await h.coordinator.send(first.requestID) }
        #expect(h.provider.requests.isEmpty, "the ready record is not sent on a consent given for another destination")
        #expect(try await h.reloaded(first.requestID)?.state == .awaitingConsent)
        let disclosure = try #require(await h.coordinator.disclosure(for: first.requestID))
        #expect(disclosure.reasons.contains(.destinationChanged(previousOrigin: "http://192.168.1.20:1234")))
        #expect(disclosure.endpoint.origin == "http://127.0.0.1:1234")
    }

    /// The origin the user approves is the origin the request goes to: a pack naming one destination cannot be sent
    /// with a configuration for another (plan 11.2, 14.2). Checked at draft time and again before consent and sending,
    /// because records are reloaded from storage.
    @Test func packWhoseEndpointDiffersFromTheConfigurationIsRefused() async throws {
        let h = try Harness(scripts: [[Self.accepted, Self.text("ok"), Self.done]])
        var other = Self.localConfig
        other.baseURL = URL(string: "http://10.0.0.9:8080/v1")!
        let pack = TestPacks.make(config: Self.localConfig)
        await #expect(throws: AskError.endpointMismatch) { try await h.coordinator.createDraft(pack: pack, config: other) }
        #expect(try await h.store.all().isEmpty, "nothing is stored for a mismatched pack")

        var otherModel = Self.localConfig
        otherModel.model = "another-model"
        await #expect(throws: AskError.endpointMismatch) { try await h.coordinator.createDraft(pack: pack, config: otherModel) }

        // A record whose stored configuration was changed underneath it (or written by another version).
        let draft = try await h.coordinator.createDraft(pack: pack, config: Self.localConfig)
        var tampered = draft
        tampered.config = other
        try await h.store.save(tampered)
        let fresh = AskCoordinator(store: try FileAskStore(directory: h.directory), providerFactory: { _ in h.provider },
                                   connectivity: h.connectivity, sleeper: h.sleeper, clock: h.clock)
        await #expect(throws: AskError.endpointMismatch) { try await fresh.prepare(pack.requestID) }
        await #expect(throws: AskError.endpointMismatch) { try await fresh.send(pack.requestID) }
        #expect(h.provider.requests.isEmpty)

        var refused = Self.localConfig
        refused.baseURL = URL(string: "http://gateway.example.com/v1")!
        await #expect(throws: AskError.self) { try await h.coordinator.createDraft(pack: pack, config: refused) }
    }

    @Test func packWithTextAfterItsOwnSpoilerBoundaryIsNeverStored() async throws {
        let h = try Harness(scripts: [[Self.accepted, Self.text("ok"), Self.done]])
        var pack = TestPacks.make(config: Self.localConfig)  // evidence at paragraph 40
        pack.spoilerBoundary = SpoilerBoundary(enabled: true, maxOrdinal: 39, basis: .userConfirmedPosition)
        pack.packSHA256 = pack.computeDigest()
        #expect(pack.spoilerBoundaryViolations.count == 1)
        await #expect(throws: AskError.packViolatesSpoilerBoundary) { try await h.coordinator.createDraft(pack: pack, config: Self.localConfig) }
        #expect(try await h.store.all().isEmpty)
        #expect(h.provider.requests.isEmpty)
    }

    /// R4-06: the coordinator's boundary check covers saved thoughts. A restricted pack holding a note on this work from
    /// after the position, or one whose place is unknown, is never stored or sent.
    @Test func packWithALaterThoughtIsNeverStored() async throws {
        let h = try Harness(scripts: [[Self.accepted, Self.text("ok"), Self.done]])
        let base = TestPacks.make(config: Self.localConfig, evidence: [(TestPacks.waldenPassage, .sourceText), ("A note on the ending.", .userNote)])
        for position in [EvidencePosition(resourceHref: "text/conclusion.xhtml", firstOrdinal: 900, lastOrdinal: 900), nil] {
            var pack = base
            pack.evidence[1].workID = pack.work?.workID
            pack.evidence[1].editionID = position == nil ? nil : pack.work?.editionID
            pack.evidence[1].position = position
            pack.spoilerBoundary = SpoilerBoundary(enabled: true, maxOrdinal: 45, basis: .userConfirmedPosition)
            pack.packSHA256 = pack.computeDigest()
            #expect(pack.spoilerBoundaryViolations.count == 1)
            await #expect(throws: AskError.packViolatesSpoilerBoundary) { try await h.coordinator.createDraft(pack: pack, config: Self.localConfig) }
        }
        #expect(try await h.store.all().isEmpty)
        #expect(h.provider.requests.isEmpty)
    }

    /// ADR-0011: partial output is checkpointed every 400 characters *or* 1 s. The character threshold is set out of
    /// reach here, so only the time-based checkpoint can make the slow trickle durable.
    @Test func slowOutputIsCheckpointedByTimeNotOnlyByLength() async throws {
        let directory = TestPacks.temporaryDirectory()
        let clock = ManualClock()
        let pack = TestPacks.make(config: Self.localConfig)
        let beforeInterval = Mutex<String?>(nil)
        let afterInterval = Mutex<String?>(nil)
        @Sendable func onDisk() async -> String? { try? await FileAskStore(directory: directory).load(pack.requestID)?.answerText }
        @Sendable func waitForDisk(_ text: String) async -> String? {
            let deadline = ContinuousClock.now + .seconds(5)
            while ContinuousClock.now < deadline {
                if await onDisk() == text { return text }
                try? await Task.sleep(for: .milliseconds(10))
            }
            return await onDisk()
        }
        let observed = ObservedRecord()
        let h = try Harness(scripts: [[
            Self.accepted, Self.text("Slow "),
            .hook { await observed.waitForAnswer("Slow ") },
            .hook { let text = await onDisk(); beforeInterval.withLock { $0 = text } },
            .hook { clock.advance(by: 1.5) },
            Self.text("trickle"),
            .hook { let text = await waitForDisk("Slow trickle"); afterInterval.withLock { $0 = text } },
            Self.done,
        ]], checkpoint: CheckpointPolicy(characters: 100_000, interval: 1.0), clock: clock, directory: directory)
        observed.watch(h.coordinator, pack.requestID)
        _ = try await h.ready(pack)
        let record = try await h.coordinator.send(pack.requestID)
        #expect(record.state == .complete)
        #expect(beforeInterval.withLock { $0 } == "", "no checkpoint before the interval elapsed")
        #expect(afterInterval.withLock { $0 } == "Slow trickle", "the time-based checkpoint made the partial text durable mid-stream")
        #expect(record.checkpointCount >= 1)
    }

    /// Plan 14.5: a runaway stream is stopped at the output cap; what arrived is kept, labelled partial, and nothing
    /// is resent automatically (the provider may have billed it).
    @Test func outputBeyondTheCapIsStoppedAndLabelledPartial() async throws {
        let line = String(repeating: "word ", count: 8)  // 40 characters
        let h = try Harness(scripts: [[Self.accepted, Self.text(line), Self.text(line), Self.text(line), .waitForCancellation]],
                            outputLimits: OutputLimits(charactersPerOutputToken: 0, minimumCharacters: 60))
        let id = try await h.ready()
        let record = try await h.coordinator.send(id)
        #expect(record.state == .interrupted)
        #expect(record.outcome == .partial)
        #expect(record.statusPhrase == "Interrupted · partial answer")
        #expect(record.failure?.kind == .responseSizeLimit)
        #expect(record.failure?.resubmitNeedsConfirmation == true)
        #expect(record.answerText == line, "text up to the cap is kept; nothing past it is stored")
        #expect(h.provider.requests.count == 1)
        #expect(h.sleeper.sleeps.isEmpty)
    }

    @Test func outputBeyondTheTimeLimitIsStoppedAndLabelledPartial() async throws {
        let clock = ManualClock()
        let observed = ObservedRecord()
        let pack = TestPacks.make(config: Self.localConfig)
        // The clock passes the 600 s limit after "Still " was taken in; "going" arrives after the limit, is kept (it
        // arrived before Sylvia stopped reading), and the stream is then abandoned although the server would go on.
        let h = try Harness(scripts: [[Self.accepted, Self.text("Still "),
                                       .hook { await observed.waitForAnswer("Still "); clock.advance(by: 601) },
                                       Self.text("going"), Self.text(" on and on"), .waitForCancellation]],
                            clock: clock)
        observed.watch(h.coordinator, pack.requestID)
        let id = try await h.ready(pack)
        let record = try await h.coordinator.send(id)
        #expect(record.state == .interrupted)
        #expect(record.outcome == .partial)
        #expect(record.statusPhrase == "Interrupted · partial answer")
        #expect(record.failure?.kind == .responseTimeLimit)
        #expect(record.failure?.resubmitNeedsConfirmation == true)
        #expect(record.answerText == "Still going")
        #expect(record.failure?.userMessage.contains("time limit") == true)
        #expect(h.provider.requests.count == 1)
        #expect(h.sleeper.sleeps.isEmpty, "no automatic retry")
    }

    /// Within the limits nothing is cut: a long answer that finishes before the time limit is complete.
    @Test func outputWithinTheLimitsIsUntouched() async throws {
        let clock = ManualClock()
        let observed = ObservedRecord()
        let pack = TestPacks.make(config: Self.localConfig)
        let h = try Harness(scripts: [[Self.accepted, Self.text(String(repeating: "a", count: 59)),
                                       .hook { await observed.waitForAnswer(String(repeating: "a", count: 59)); clock.advance(by: 599) },
                                       Self.text("b"), Self.done]],
                            clock: clock, outputLimits: OutputLimits(charactersPerOutputToken: 0, minimumCharacters: 60))
        observed.watch(h.coordinator, pack.requestID)
        let record = try await h.coordinator.send(try await h.ready(pack))
        #expect(record.state == .complete)
        #expect(record.answerText.count == 60)
        #expect(record.failure == nil)
    }

    @Test func recordIsDurableInSendingBeforeTheRequestLeaves() async throws {
        let observed = Mutex<AskRecord?>(nil)
        let directory = TestPacks.temporaryDirectory()
        let pack = TestPacks.make(config: Self.localConfig)
        let h = try Harness(scripts: [[
            .hook { observed.withLock { _ in } ; let r = try? await FileAskStore(directory: directory).load(pack.requestID); observed.withLock { $0 = r } },
            Self.accepted, Self.text("ok"), Self.done,
        ]], directory: directory)
        _ = try await h.ready(pack)
        _ = try await h.coordinator.send(pack.requestID)
        let snapshot = try #require(observed.withLock { $0 })
        #expect(snapshot.state == .sending)
        #expect(snapshot.question == pack.question)
        #expect(snapshot.attempts.count == 1)
        #expect(snapshot.pack.evidence.map(\.text) == pack.evidence.map(\.text))
    }

    @Test func partialOutputIsCheckpointedAndRelaunchShowsInterruptedPartialAnswer() async throws {
        let directory = TestPacks.temporaryDirectory()
        let reachedMiddle = Mutex(false)
        let pack = TestPacks.make(config: Self.localConfig)
        let h = try Harness(scripts: [[
            Self.accepted, Self.text("The first part "), Self.text("of the answer, "), Self.text("which keeps going"),
            .hook { reachedMiddle.withLock { $0 = true } },
            .waitForCancellation,
        ]], directory: directory)
        _ = try await h.ready(pack)
        // The first coordinator "crashes": it is abandoned mid-stream while the provider waits.
        let crashed = Task { try await h.coordinator.send(pack.requestID) }
        while !reachedMiddle.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(5)) }
        // Wait (bounded) until the last checkpoint of the streamed text is durable, then "crash".
        let fullText = "The first part of the answer, which keeps going"
        let deadline = ContinuousClock.now + .seconds(10)
        while try await h.reloaded(pack.requestID)?.answerText != fullText, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        let onDisk = try #require(try await h.reloaded(pack.requestID))
        #expect(onDisk.answerText == fullText)
        #expect(onDisk.state == .streaming)
        #expect(onDisk.checkpointCount >= 2)
        #expect(onDisk.answerText.hasPrefix("The first part "))

        // Relaunch: a new coordinator over the same store reconciles.
        let relaunched = AskCoordinator(store: try FileAskStore(directory: directory), providerFactory: { _ in h.provider },
                                        connectivity: h.connectivity, sleeper: h.sleeper, clock: h.clock)
        let reconciled = try await relaunched.reconcileAfterLaunch()
        #expect(reconciled.count == 1)
        #expect(reconciled[0].state == .interrupted)
        #expect(reconciled[0].statusPhrase == "Interrupted · partial answer")
        #expect(reconciled[0].answerText == onDisk.answerText)
        #expect(reconciled[0].question == pack.question)
        await h.coordinator.stop(pack.requestID, reason: .suspension)
        _ = try? await crashed.value
    }

    @Test func relaunchWithoutOutputIsFailedRetryableNeedingConfirmation() async throws {
        let directory = TestPacks.temporaryDirectory()
        let pack = TestPacks.make(config: Self.localConfig)
        var record = AskRecord(id: pack.requestID, conversationID: pack.conversationID, question: pack.question, pack: pack, config: Self.localConfig,
                               state: .sending, answerText: "", refusalText: "", outcome: nil, usage: nil, attempts: [], failure: nil,
                               queuedOffline: false, reasoningOmitted: false, toolCallRejected: false, checkpointCount: 0, createdAt: Date(), updatedAt: Date())
        record.attempts = [AttemptRecord(number: 1, startedAt: Date())]
        try await FileAskStore(directory: directory).save(record)
        let h = try Harness(scripts: [], directory: directory)
        let reconciled = try await h.coordinator.reconcileAfterLaunch()
        #expect(reconciled.first?.state == .failedRetryable)
        #expect(reconciled.first?.failure?.resubmitNeedsConfirmation == true)
        await #expect(throws: AskError.resubmitNeedsConfirmation) { try await h.coordinator.send(pack.requestID) }
        #expect(h.provider.requests.isEmpty)
    }

    @Test func midStreamFailureIsInterruptedAndNeverReplayedAutomatically() async throws {
        let lost = ProviderError(kind: .connectionLost, acceptance: .uncertain, host: "127.0.0.1")
        let h = try Harness(scripts: [
            [Self.accepted, Self.text("Half an "), .fail(lost)],
            [Self.accepted, Self.text("Whole answer."), Self.done],
        ])
        let id = try await h.ready()
        let first = try await h.coordinator.send(id)
        #expect(first.state == .interrupted)
        #expect(first.outcome == .partial)
        #expect(first.answerText == "Half an ")
        #expect(first.statusPhrase == "Interrupted · partial answer")
        #expect(h.provider.requests.count == 1, "no automatic replay of an uncertain generation")
        #expect(h.sleeper.sleeps.isEmpty)

        await #expect(throws: AskError.resubmitNeedsConfirmation) { try await h.coordinator.send(id) }
        let second = try await h.coordinator.send(id, userConfirmedResubmit: true)
        #expect(second.state == .complete)
        #expect(second.answerText == "Whole answer.")
        #expect(second.attempts.count == 2)
        #expect(second.attempts[0].supersededPartialText == "Half an ")
        #expect(second.attempts[0].failureKind == .connectionLost)
        // The question is stored once and sent once per attempt: no duplicated question or conversation.
        for request in h.provider.requests {
            #expect(Self.countOccurrences(PromptTemplate.escape(second.question), in: request) == 1)
            #expect(request.messages.count == 1)
        }
        #expect(try await h.store.all().count == 1)
    }

    @Test func transientFailuresRetryWithCappedBackoffAndRetryAfter() async throws {
        let h = try Harness(scripts: [
            [.fail(ProviderError(kind: .serverError, acceptance: .rejected, host: "h", httpStatus: 503))],
            [.fail(ProviderError(kind: .rateLimited, acceptance: .rejected, host: "h", httpStatus: 429, retryAfter: .seconds(7)))],
            [Self.accepted, Self.text("Third time."), Self.done],
        ])
        let id = try await h.ready()
        let record = try await h.coordinator.send(id)
        #expect(record.state == .complete)
        #expect(record.answerText == "Third time.")
        #expect(h.sleeper.sleeps == [.seconds(1), .seconds(7)], "exponential base for the 503, Retry-After for the 429")
        #expect(record.attempts.map(\.failureKind) == [.serverError, .rateLimited, nil])
        #expect(h.provider.requests.count == 3)
        #expect(h.provider.requests.allSatisfy { $0 == h.provider.requests[0] }, "every attempt sends the identical request")
    }

    @Test func backoffIsCappedAndAttemptsAreBounded() async throws {
        let fail = ScriptedProvider.Step.fail(ProviderError(kind: .hostUnreachable, acceptance: .notSent, host: "h"))
        let h = try Harness(scripts: [[fail], [fail], [fail], [fail], [fail]],
                            retry: RetryPolicy(maxAttempts: 4, initialDelay: .seconds(2), multiplier: 3, maxDelay: .seconds(10), jitter: false))
        let id = try await h.ready()
        let record = try await h.coordinator.send(id)
        #expect(record.state == .failedRetryable)
        #expect(h.sleeper.sleeps == [.seconds(2), .seconds(6), .seconds(10)])
        #expect(h.provider.requests.count == 4)
        #expect(record.failure?.resubmitNeedsConfirmation == false)
    }

    @Test func jitterStaysWithinHalfToFullDelay() {
        let policy = RetryPolicy(maxAttempts: 5, initialDelay: .seconds(4), jitter: true)
        #expect(policy.delay(afterAttempt: 1, retryAfter: nil, random: 0) == .seconds(2))
        #expect(policy.delay(afterAttempt: 1, retryAfter: nil, random: 1) == .seconds(4))
        #expect(policy.delay(afterAttempt: 5, retryAfter: nil, random: 1) == nil)
    }

    @Test func retryAfterLongerThanTheCapIsNotWaitedOut() async throws {
        let h = try Harness(scripts: [[.fail(ProviderError(kind: .rateLimited, acceptance: .rejected, host: "h", httpStatus: 429, retryAfter: .seconds(600)))]])
        let id = try await h.ready()
        let record = try await h.coordinator.send(id)
        #expect(record.state == .failedRetryable)
        #expect(h.sleeper.sleeps.isEmpty)
        #expect(record.failure?.retryAfterMs == 600_000)
        #expect(record.statusPhrase.contains("about 600 seconds"))
    }

    @Test func uncertainFailureWithoutOutputIsNotRetried() async throws {
        let h = try Harness(scripts: [[.fail(ProviderError(kind: .timeout, acceptance: .uncertain, host: "h"))]])
        let id = try await h.ready()
        let record = try await h.coordinator.send(id)
        #expect(record.state == .failedRetryable)
        #expect(record.failure?.resubmitNeedsConfirmation == true)
        #expect(h.provider.requests.count == 1)
        #expect(h.sleeper.sleeps.isEmpty)
    }

    @Test func configurationFailureIsFinal() async throws {
        let h = try Harness(scripts: [[.fail(ProviderError(kind: .authentication, acceptance: .rejected, host: "h", httpStatus: 401))]])
        let id = try await h.ready()
        let record = try await h.coordinator.send(id)
        #expect(record.state == .failedFinal)
        #expect(record.statusPhrase.contains("rejected the key"))
        #expect(h.provider.requests.count == 1)
    }

    @Test func offlineSubmissionStaysADraftAndIsNeverSentAutomatically() async throws {
        let h = try Harness(scripts: [[Self.accepted, Self.text("x"), Self.done]], online: false)
        let id = try await h.ready()
        let record = try await h.coordinator.send(id)
        #expect(record.state == .draft)
        #expect(record.queuedOffline)
        #expect(record.statusPhrase == "Draft · not sent")
        h.connectivity.set(online: true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(h.provider.requests.isEmpty, "connectivity returning does not send anything")
        let sent = try await h.coordinator.send(id)
        #expect(sent.state == .complete)
    }

    @Test func userCancelKeepsPartialOutputLabelled() async throws {
        let streaming = Mutex(false)
        let h = try Harness(scripts: [[Self.accepted, Self.text("Some words"), .hook { streaming.withLock { $0 = true } }, .waitForCancellation]])
        let id = try await h.ready()
        let task = Task { try await h.coordinator.send(id) }
        while !streaming.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(5)) }
        while try await h.coordinator.record(id).answerText.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        await h.coordinator.stop(id, reason: .user)
        let record = try await task.value
        #expect(record.state == .cancelled)
        #expect(record.answerText == "Some words")
        #expect(record.outcome == .partial)
        #expect(record.statusPhrase == "Interrupted · partial answer")
        #expect(try await h.reloaded(id)?.state == .cancelled)
    }

    @Test func suspensionInterruptsForegroundWork() async throws {
        let streaming = Mutex(false)
        let h = try Harness(scripts: [[Self.accepted, Self.text("Before suspension"), .hook { streaming.withLock { $0 = true } }, .waitForCancellation]])
        let id = try await h.ready()
        let task = Task { try await h.coordinator.send(id) }
        while !streaming.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(5)) }
        while try await h.coordinator.record(id).answerText.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        await h.coordinator.stop(id, reason: .suspension)
        let record = try await task.value
        #expect(record.state == .interrupted)
        #expect(record.statusPhrase == "Interrupted · partial answer")
    }

    /// What the app does when its scene leaves the foreground: every in-flight request stops, each keeps its partial
    /// output labelled, the records are durable before the call returns, and nothing is resent afterwards.
    @Test func leavingTheForegroundStopsEveryInFlightRequest() async throws {
        let observed = ObservedRecord()
        let h = try Harness(scripts: [[Self.accepted, Self.text("First partial"), .waitForCancellation],
                                      [Self.accepted, .waitForCancellation]])
        let first = TestPacks.make(question: "First question?", config: Self.localConfig)
        let second = TestPacks.make(question: "Second question?", config: Self.localConfig)
        observed.watch(h.coordinator, first.requestID)
        _ = try await h.ready(first)
        _ = try await h.ready(second)
        let firstTask = Task { try await h.coordinator.send(first.requestID) }
        await observed.waitForAnswer("First partial")
        let secondTask = Task { try await h.coordinator.send(second.requestID) }
        while h.provider.requests.count < 2 { try await Task.sleep(for: .milliseconds(5)) }
        let stopped = await h.coordinator.stopAll(reason: .suspension)
        #expect(Set(stopped) == [first.requestID, second.requestID])
        #expect(await h.coordinator.waitUntilIdle())
        let one = try await firstTask.value, two = try await secondTask.value
        #expect(one.state == .interrupted && one.statusPhrase == "Interrupted · partial answer" && one.answerText == "First partial")
        #expect(two.state == .failedRetryable && two.failure?.resubmitNeedsConfirmation == true, "no output, but the request may have left")
        #expect(try await h.reloaded(first.requestID)?.state == .interrupted)
        #expect(try await h.reloaded(second.requestID)?.state == .failedRetryable)
        #expect(await h.coordinator.stopAll(reason: .suspension).isEmpty, "nothing left in flight")
        #expect(h.provider.requests.count == 2, "each question sent once; nothing resent")
    }

    @Test func userCancelBeforeAnyOutputNeverClaimsNotSent() async throws {
        let waiting = Mutex(false)
        let h = try Harness(scripts: [[.hook { waiting.withLock { $0 = true } }, .waitForCancellation],
                                      [Self.accepted, Self.text("Answer."), Self.done]])
        let id = try await h.ready()
        let task = Task { try await h.coordinator.send(id) }
        while !waiting.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(5)) }
        await h.coordinator.stop(id, reason: .user)
        let record = try await task.value
        #expect(record.state == .cancelled)
        #expect(record.answerText.isEmpty)
        #expect(record.statusPhrase != "Draft · not sent", "the request may already have left the device")
        #expect(record.statusPhrase.contains("may have reached 127.0.0.1"))
        #expect(record.failure?.resubmitNeedsConfirmation == true)
        await #expect(throws: AskError.resubmitNeedsConfirmation) { try await h.coordinator.send(id) }
        #expect(h.provider.requests.count == 1)
        let resent = try await h.coordinator.send(id, userConfirmedResubmit: true)
        #expect(resent.state == .complete)
        #expect(h.provider.requests.count == 2)
    }

    /// A sleeper that blocks until cancelled, recording that a wait started.
    final class BlockingSleeper: Sleeper {
        let started = Mutex(0)
        func sleep(for duration: Duration) async throws {
            started.withLock { $0 += 1 }
            while true {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(5))
            }
        }
    }

    @Test func stopDuringBackoffWaitTakesEffectAndSendsNothingMore() async throws {
        let provider = ScriptedProvider(config: Self.localConfig, scripts: [
            [.fail(ProviderError(kind: .serverError, acceptance: .rejected, host: "127.0.0.1", httpStatus: 503))],
            [Self.accepted, Self.text("Should never be requested."), Self.done],
        ])
        let sleeper = BlockingSleeper()
        let coordinator = AskCoordinator(store: try FileAskStore(directory: TestPacks.temporaryDirectory()), providerFactory: { _ in provider },
                                         connectivity: FakeConnectivity(online: true), sleeper: sleeper, retry: RetryPolicy(jitter: false))
        let pack = TestPacks.make(config: Self.localConfig)
        _ = try await coordinator.createDraft(pack: pack, config: Self.localConfig)
        _ = try await coordinator.prepare(pack.requestID)
        _ = try await coordinator.grantConsent(pack.requestID)
        let task = Task { try await coordinator.send(pack.requestID) }
        while sleeper.started.withLock({ $0 }) == 0 { try await Task.sleep(for: .milliseconds(5)) }
        await coordinator.stop(pack.requestID, reason: .user)
        let record = try await task.value
        #expect(record.state == .cancelled)
        #expect(record.failure?.acceptance == .notSent)
        #expect(record.failure?.resubmitNeedsConfirmation == false)
        #expect(provider.requests.count == 1, "the retry never went out")
        #expect(record.attempts.count == 1)
        #expect(record.attempts[0].failureKind == .serverError)
    }

    /// Delegates to a FileAskStore and runs a hook before writing a record in a given state, or delays loads.
    actor HookedStore: AskStore {
        let inner: FileAskStore
        var onSave: (@Sendable (AskRecord) async -> Void)?
        let loadDelay: Duration
        init(directory: URL, loadDelay: Duration = .zero) throws {
            inner = try FileAskStore(directory: directory)
            self.loadDelay = loadDelay
        }
        func setOnSave(_ hook: (@Sendable (AskRecord) async -> Void)?) { onSave = hook }
        func save(_ record: AskRecord) async throws {
            if let onSave { await onSave(record) }
            try await inner.save(record)
        }
        func load(_ id: UUID) async throws -> AskRecord? {
            if loadDelay > .zero { try await Task.sleep(for: loadDelay) }
            return try await inner.load(id)
        }
        func all() async throws -> [AskRecord] { try await inner.all() }
    }

    @Test func stopWhileTheSendingRecordIsBeingWrittenSendsNothing() async throws {
        let provider = ScriptedProvider(config: Self.localConfig, scripts: [[Self.accepted, Self.text("Should never be requested."), Self.done]])
        let store = try HookedStore(directory: TestPacks.temporaryDirectory())
        let coordinator = AskCoordinator(store: store, providerFactory: { _ in provider }, connectivity: FakeConnectivity(online: true),
                                         sleeper: RecordingSleeper(), retry: RetryPolicy(jitter: false))
        let pack = TestPacks.make(config: Self.localConfig)
        _ = try await coordinator.createDraft(pack: pack, config: Self.localConfig)
        _ = try await coordinator.prepare(pack.requestID)
        _ = try await coordinator.grantConsent(pack.requestID)
        // The user taps Cancel while the coordinator is suspended writing the `sending` record, before any stream exists.
        let stopped = Mutex(false)
        await store.setOnSave { record in
            guard record.state == .sending, !stopped.withLock({ $0 }) else { return }
            stopped.withLock { $0 = true }
            await coordinator.stop(pack.requestID, reason: .user)
        }
        let record = try await coordinator.send(pack.requestID)
        #expect(stopped.withLock { $0 })
        #expect(provider.requests.isEmpty, "the stop took effect before the request left")
        #expect(record.state == .cancelled)
        #expect(record.failure?.acceptance == .notSent)
        #expect(record.failure?.resubmitNeedsConfirmation == false)
        #expect(record.statusPhrase == "Cancelled before sending. Nothing was sent to 127.0.0.1.")
        #expect(record.attempts.count == 1)
        #expect(record.attempts[0].failureKind == .cancelled && record.attempts[0].acceptance == .notSent)
        let stored = try #require(try await store.load(pack.requestID))
        #expect(stored.state == .cancelled, "the cancelled state is durable")
    }

    @Test func concurrentSendsOfOneRecordPutTheQuestionOnTheWireOnce() async throws {
        let directory = TestPacks.temporaryDirectory()
        let provider = ScriptedProvider(config: Self.localConfig, scripts: [[Self.accepted, Self.text("One answer."), Self.done],
                                                                            [Self.accepted, Self.text("Duplicate."), Self.done]])
        let pack = TestPacks.make(config: Self.localConfig)
        // Prepare the record with one coordinator, then send from a fresh one so the record is not cached and
        // both calls suspend in the (delayed) load: the window in which a double tap could slip through.
        let setup = AskCoordinator(store: try FileAskStore(directory: directory), providerFactory: { _ in provider },
                                   connectivity: FakeConnectivity(online: true))
        _ = try await setup.createDraft(pack: pack, config: Self.localConfig)
        _ = try await setup.prepare(pack.requestID)
        _ = try await setup.grantConsent(pack.requestID)
        let consent = await setup.consent
        let store = try HookedStore(directory: directory, loadDelay: .milliseconds(50))
        let coordinator = AskCoordinator(store: store, consent: consent, providerFactory: { _ in provider },
                                         connectivity: FakeConnectivity(online: true), sleeper: RecordingSleeper())
        @Sendable func attempt() async -> Result<AskRecord, any Error> {
            do { return .success(try await coordinator.send(pack.requestID)) } catch { return .failure(error) }
        }
        async let first = attempt()
        async let second = attempt()
        let results = await [first, second]
        let completed = results.compactMap { try? $0.get() }
        let refused = results.compactMap { result -> AskError? in
            if case .failure(let error) = result { return error as? AskError }
            return nil
        }
        #expect(completed.count == 1)
        #expect(completed.first?.state == .complete)
        #expect(refused == [.invalidState(.sending)])
        #expect(provider.requests.count == 1, "the question went out once")
        #expect(completed.first?.attempts.count == 1)
    }

    /// R5-01 (plan 11.1, 14.4, 14.5): a request ID has one record. A second `createDraft` for an answered request returns
    /// the answered record: the answer and its attempt stay on disk, a plain Send puts nothing on the wire, and the same
    /// holds after a relaunch, when nothing is cached. A different pack under that request ID is refused.
    @Test func secondDraftForAnAnsweredRequestKeepsTheAnswer() async throws {
        let h = try Harness(scripts: [[Self.accepted, Self.text("Answer [c1]."), Self.done],
                                      [Self.accepted, Self.text("Second answer [c1]."), Self.done]])
        let pack = TestPacks.make(config: Self.localConfig)
        let id = try await h.ready(pack)
        let answered = try await h.coordinator.send(id)
        #expect(answered.state == .complete && answered.answerText == "Answer [c1].")

        let again = try await h.coordinator.createDraft(pack: pack, config: Self.localConfig)
        #expect(again.state == .complete)
        #expect(again.answerText == "Answer [c1].")
        #expect(again.attempts.count == 1)
        #expect(again.statusPhrase == "Complete")
        let stored = try #require(try await h.reloaded(id))
        #expect(stored.state == .complete && stored.answerText == "Answer [c1]." && stored.attempts.count == 1, "the answer is kept on disk")
        await #expect(throws: AskError.invalidState(.complete)) { try await h.coordinator.send(id) }
        #expect(h.provider.requests.count == 1, "the question was not sent again")

        let relaunched = AskCoordinator(store: try FileAskStore(directory: h.directory), consent: await h.coordinator.consent,
                                        providerFactory: { _ in h.provider }, connectivity: h.connectivity, sleeper: h.sleeper, clock: h.clock)
        let afterRelaunch = try await relaunched.createDraft(pack: pack, config: Self.localConfig)
        #expect(afterRelaunch.state == .complete && afterRelaunch.answerText == "Answer [c1]." && afterRelaunch.attempts.count == 1)
        await #expect(throws: AskError.invalidState(.complete)) { try await relaunched.send(id) }
        #expect(h.provider.requests.count == 1)
        #expect(try await h.reloaded(id)?.answerText == "Answer [c1].")

        var other = TestPacks.make(question: "A different question?", config: Self.localConfig)
        other.requestID = id
        await #expect(throws: AskError.requestAlreadyExists) { try await h.coordinator.createDraft(pack: other, config: Self.localConfig) }
        await #expect(throws: AskError.requestAlreadyExists) { try await relaunched.createDraft(pack: other, config: Self.localConfig) }
        let kept = try #require(try await h.reloaded(id))
        #expect(kept.question == pack.question && kept.state == .complete)
    }

    /// R5-01: a second `createDraft` while the request is on the wire (a double tap on Ask) leaves the record alone. The
    /// store never reads "Draft · not sent", and after a relaunch the record is reconciled as a request that may have
    /// reached the provider, sent again only on the user's confirmation.
    @Test func secondDraftWhileTheRequestIsOnTheWireLeavesItAlone() async throws {
        let directory = TestPacks.temporaryDirectory()
        let onTheWire = Mutex(false)
        let pack = TestPacks.make(config: Self.localConfig)
        let h = try Harness(scripts: [[.hook { onTheWire.withLock { $0 = true } }, .waitForCancellation]], directory: directory)
        let id = try await h.ready(pack)
        let first = Task { try await h.coordinator.send(id) }
        let deadline = ContinuousClock.now + .seconds(10)
        while !onTheWire.withLock({ $0 }), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(onTheWire.withLock { $0 }, "the request reached the provider")

        let second = try await h.coordinator.createDraft(pack: pack, config: Self.localConfig)
        #expect(second.state == .sending)
        #expect(second.statusPhrase != "Draft · not sent")
        let stored = try #require(try await h.reloaded(id))
        #expect(stored.state == .sending && stored.attempts.count == 1, "the store still says the request may have left")
        // Another coordinator over the same store (nothing cached) finds the stored record and leaves it too.
        let uncached = AskCoordinator(store: try FileAskStore(directory: directory), providerFactory: { _ in h.provider },
                                      connectivity: h.connectivity, sleeper: h.sleeper, clock: h.clock)
        #expect(try await uncached.createDraft(pack: pack, config: Self.localConfig).state == .sending)
        #expect(try await h.reloaded(id)?.state == .sending)

        // Relaunch from this state: the request may have reached the provider, so a plain Send is refused.
        let relaunched = AskCoordinator(store: try FileAskStore(directory: directory), consent: await h.coordinator.consent,
                                        providerFactory: { _ in h.provider }, connectivity: h.connectivity, sleeper: h.sleeper, clock: h.clock)
        let reconciled = try await relaunched.reconcileAfterLaunch()
        #expect(reconciled.map(\.id) == [id])
        #expect(reconciled.first?.state == .failedRetryable)
        #expect(reconciled.first?.failure?.resubmitNeedsConfirmation == true)
        #expect(reconciled.first?.statusPhrase != "Draft · not sent")
        await #expect(throws: AskError.resubmitNeedsConfirmation) { try await relaunched.send(id) }
        #expect(h.provider.requests.count == 1, "the question went out once")
        await h.coordinator.stop(id, reason: .suspension)
        _ = try? await first.value
    }

    /// R5-01: two `createDraft` calls for one request at once, both suspended in a slow store, write the draft once and
    /// return the same record.
    @Test func concurrentDraftsOfOneRequestWriteItOnce() async throws {
        let store = try HookedStore(directory: TestPacks.temporaryDirectory(), loadDelay: .milliseconds(50))
        let saves = Mutex(0)
        await store.setOnSave { _ in saves.withLock { $0 += 1 } }
        let coordinator = AskCoordinator(store: store, providerFactory: { _ in ScriptedProvider(config: Self.localConfig, scripts: []) },
                                         connectivity: FakeConnectivity(online: true), sleeper: RecordingSleeper())
        let pack = TestPacks.make(config: Self.localConfig)
        async let a = coordinator.createDraft(pack: pack, config: Self.localConfig)
        async let b = coordinator.createDraft(pack: pack, config: Self.localConfig)
        let results = try await [a, b]
        #expect(results.allSatisfy { $0.state == .draft })
        #expect(results[0] == results[1])
        #expect(saves.withLock { $0 } == 1, "the draft was written once")
        let stored = try #require(try await store.load(pack.requestID))
        #expect(stored.state == .draft && stored.pack == pack)
    }

    /// I-04: after some answer text, every final event other than a normal end leaves a labelled partial answer (a refusal
    /// stop or a content filter cuts the text off where the provider stopped it), never "Complete".
    @Test func finishReasonsMapToHonestStates() async throws {
        let cases: [(FinishReason, AskState, AnswerOutcome, status: String, detail: String)] = [
            (.refused, .interrupted, .refusal, "Interrupted · partial answer",
             "127.0.0.1 stopped partway and declined to continue. What arrived before that is kept as a partial answer."),
            (.contentFiltered, .interrupted, .contentFiltered, "Interrupted · partial answer",
             "127.0.0.1's content filter cut the answer off. What arrived before that is kept as a partial answer."),
            (.outputLimit, .interrupted, .outputLimit, "Interrupted · partial answer",
             "The answer reached the maximum output for this endpoint and stopped. Raise the maximum output in provider settings for longer answers."),
            (.contextWindowExceeded, .interrupted, .contextWindowExceeded, "Interrupted · partial answer",
             "The answer stopped because the model's context window was full. Choose a narrower context and try again."),
            (.toolCallRejected, .failedFinal, .toolCallRejected,
             "The model asked to run a tool. Sylvia doesn't run tools, so the answer stopped there.",
             "The model asked to run a tool. Sylvia doesn't run tools, so the answer stopped there."),
            (.incomplete("pause_turn"), .interrupted, .incomplete, "Interrupted · partial answer", "127.0.0.1 stopped the answer before it finished."),
        ]
        for (reason, state, outcome, status, detail) in cases {
            let h = try Harness(scripts: [[Self.accepted, Self.text("Some text"), .event(.finished(reason))]])
            let id = try await h.ready()
            let record = try await h.coordinator.send(id)
            #expect(record.state == state, "\(reason)")
            #expect(record.outcome == outcome, "\(reason)")
            #expect(record.statusPhrase == status, "\(reason)")
            #expect(record.outcomeMessage == detail, "\(reason)")
            #expect(record.answerText == "Some text", "the partial text is kept")
            let stored = try #require(try await h.reloaded(id))
            #expect(stored.statusPhrase == status, "the stored record reads the same after a relaunch")
            await #expect(throws: AskError.self, "\(reason): never resent without the user") { try await h.coordinator.send(id) }
            #expect(h.provider.requests.count == 1)
        }
        // Only a normal end with answer text reads "Complete".
        let h = try Harness(scripts: [[Self.accepted, Self.text("Some text"), Self.done]])
        let record = try await h.coordinator.send(try await h.ready())
        #expect(record.state == .complete && record.outcome == .answer && record.statusPhrase == "Complete")
        #expect(record.outcomeMessage == nil)
    }

    /// R3-01 and R3-02 (I-04): a final event with no answer text is never shown as an answer, as "Complete" or as a
    /// partial answer. A normal end with nothing to show (reasoning only, a think block only, `[DONE]` alone) is a
    /// failure whose acceptance is uncertain: the generation may have been billed, so it is resent only when the user
    /// confirms. A refusal or a content filter with no text is a classified, final reply.
    @Test func finalEventsWithoutAnswerTextAreNeverAnAnswer() async throws {
        let cases: [(steps: [ScriptedProvider.Step], state: AskState, outcome: AnswerOutcome, status: String, failure: FailureKind?)] = [
            ([.event(.status(.reasoningOmitted)), Self.done], .failedRetryable, .noAnswerText,
             "127.0.0.1 sent only its reasoning and no answer text. Models that reason first may need a larger maximum output for this endpoint.", .invalidResponse),
            ([Self.done], .failedRetryable, .noAnswerText,
             "127.0.0.1 ended its reply without any answer text. If the model reasons first, it may need a larger maximum output for this endpoint.", .invalidResponse),
            ([Self.text("\n\n  "), Self.done], .failedRetryable, .noAnswerText,
             "127.0.0.1 ended its reply without any answer text. If the model reasons first, it may need a larger maximum output for this endpoint.", .invalidResponse),
            ([.event(.status(.reasoningOmitted)), .event(.finished(.outputLimit))], .failedRetryable, .outputLimit,
             "127.0.0.1 reached the maximum output for this endpoint before any answer text. Models that reason first may need a larger maximum output.", .invalidResponse),
            ([.event(.finished(.incomplete("pause_turn")))], .failedRetryable, .incomplete, "127.0.0.1 stopped before sending any answer text.", .invalidResponse),
            ([.event(.finished(.contextWindowExceeded))], .failedFinal, .contextWindowExceeded,
             "The question and its passages are too long for this model. Choose a narrower context and try again.", .contextTooLong),
            ([.event(.refusal("I can't help with that.")), .event(.finished(.refused))], .complete, .refusal,
             "127.0.0.1 declined to answer this question. Its reply is shown apart from answers.", nil),
            ([.event(.refusal("I can't help with that.")), Self.done], .complete, .refusal,
             "127.0.0.1 declined to answer this question. Its reply is shown apart from answers.", nil),
            // R4-05: a refusal with no text has no reply to show, and says so.
            ([.event(.finished(.refused))], .complete, .refusal, "127.0.0.1 declined to answer this question and gave no reply to show.", nil),
            ([.event(.refusal(" \n ")), .event(.finished(.refused))], .complete, .refusal,
             "127.0.0.1 declined to answer this question and gave no reply to show.", nil),
            ([.event(.finished(.contentFiltered))], .complete, .contentFiltered,
             "127.0.0.1's content filter withheld the answer, so there is nothing to show.", nil),
        ]
        for (index, item) in cases.enumerated() {
            let h = try Harness(scripts: [[Self.accepted] + item.steps])
            let id = try await h.ready()
            let record = try await h.coordinator.send(id)
            #expect(record.state == item.state, "case \(index)")
            #expect(record.outcome == item.outcome, "case \(index)")
            #expect(record.statusPhrase == item.status, "case \(index)")
            #expect(record.statusPhrase != "Complete" && record.statusPhrase != "Interrupted · partial answer", "case \(index)")
            #expect(record.failure?.kind == item.failure, "case \(index)")
            if item.failure != nil {
                #expect(record.failure?.acceptance == .uncertain, "case \(index)")
                #expect(record.failure?.resubmitNeedsConfirmation == true, "case \(index)")
                #expect(record.attempts.last?.failureKind == item.failure, "case \(index): the attempt records why it ended")
                #expect(record.attempts.last?.acceptance == .uncertain, "case \(index)")
            }
            #expect(h.sleeper.sleeps.isEmpty, "case \(index): no automatic retry")
            await #expect(throws: AskError.self, "case \(index): never resent without the user") { try await h.coordinator.send(id) }
            #expect(h.provider.requests.count == 1, "case \(index)")
            let stored = try #require(try await h.reloaded(id))
            #expect(stored.statusPhrase == item.status, "case \(index): durable")
        }
    }

    /// R4-05 (F5): a failed record never reads "Draft · not sent", because the request may already have left the device.
    /// Every path that fails a record sets its classified failure; without one the status is neutral.
    @Test func failedStatesNeverFallBackToDraftNotSent() async throws {
        let h = try Harness(scripts: [])
        let pack = TestPacks.make(config: Self.localConfig)
        var record = try await h.coordinator.createDraft(pack: pack, config: Self.localConfig)
        #expect(record.statusPhrase == "Draft · not sent")
        record.failure = nil
        for state in [AskState.failedRetryable, .failedFinal] {
            record.state = state
            #expect(record.statusPhrase == "No answer", "\(state)")
        }
        record.state = .complete
        record.outcome = .noAnswerText
        #expect(record.statusPhrase == "No answer")
    }

    /// The question is not duplicated when the user confirms a resend after an empty reply.
    @Test func emptyReplyIsResentOnlyWhenTheUserConfirms() async throws {
        let h = try Harness(scripts: [[Self.accepted, .event(.status(.reasoningOmitted)), Self.done],
                                      [Self.accepted, Self.text("Answer [c1]."), Self.done]])
        let id = try await h.ready()
        let first = try await h.coordinator.send(id)
        #expect(first.state == .failedRetryable && first.outcome == .noAnswerText)
        await #expect(throws: AskError.resubmitNeedsConfirmation) { try await h.coordinator.send(id) }
        let confirmed = try await h.coordinator.send(id, userConfirmedResubmit: true)
        #expect(confirmed.state == .complete && confirmed.statusPhrase == "Complete")
        #expect(confirmed.attempts.count == 2)
        #expect(confirmed.attempts[0].failureKind == .invalidResponse)
        #expect(h.provider.requests.count == 2)
        for request in h.provider.requests { #expect(Self.countOccurrences("living deliberately?", in: request) == 1) }
    }

    @Test func refusalTextIsKeptApartFromTheAnswer() async throws {
        let h = try Harness(scripts: [[Self.accepted, .event(.refusal("I can't help with that.")), .event(.finished(.refused))]])
        let id = try await h.ready()
        let record = try await h.coordinator.send(id)
        #expect(record.outcome == .refusal)
        #expect(record.answerText.isEmpty)
        #expect(record.refusalText == "I can't help with that.")
    }

    @Test func aFailingProviderNeverCausesAnotherToBeCalled() async throws {
        let configA = Self.localConfig
        var configB = Self.localConfig
        configB.providerID = UUID()
        configB.baseURL = URL(string: "https://api.openai.com/v1")!
        configB.kind = .openAIResponses
        let providerA = ScriptedProvider(config: configA, scripts: [[.fail(ProviderError(kind: .hostUnreachable, acceptance: .notSent, host: "127.0.0.1"))],
                                                                    [.fail(ProviderError(kind: .hostUnreachable, acceptance: .notSent, host: "127.0.0.1"))],
                                                                    [.fail(ProviderError(kind: .hostUnreachable, acceptance: .notSent, host: "127.0.0.1"))]])
        let providerB = ScriptedProvider(config: configB, scripts: [[Self.accepted, Self.text("hosted"), Self.done]])
        let registry = ProviderRegistry([providerA, providerB])
        var consent = ConsentLedger()
        for config in [configA, configB] {
            if case .required(let d) = consent.evaluate(TestPacks.endpoint(for: config), providerID: config.providerID, scopes: [.sourceText, .savedThoughts]) {
                consent.grant(d, providerID: config.providerID, at: Date())
            }
        }
        let coordinator = AskCoordinator(store: try FileAskStore(directory: TestPacks.temporaryDirectory()), consent: consent,
                                         providerFactory: { registry.provider(for: $0) }, connectivity: FakeConnectivity(online: true),
                                         sleeper: RecordingSleeper(), retry: RetryPolicy(jitter: false))
        let pack = TestPacks.make(config: configA)
        _ = try await coordinator.createDraft(pack: pack, config: configA)
        _ = try await coordinator.prepare(pack.requestID)
        let record = try await coordinator.send(pack.requestID)
        #expect(record.state == .failedRetryable)
        #expect(Set(registry.calledProviderIDs) == [configA.providerID], "the hosted provider was never called")
        #expect(providerB.requests.isEmpty)
    }

    @Test func destinationModelOrScopeChangeRequiresNewConsent() async throws {
        var ledger = ConsentLedger()
        let config = Self.localConfig
        let endpoint = TestPacks.endpoint(for: config)
        guard case .required(let first) = ledger.evaluate(endpoint, providerID: config.providerID, scopes: [.sourceText]) else {
            Issue.record("first request must need consent"); return
        }
        ledger.grant(first, providerID: config.providerID, at: Date())
        #expect(ledger.evaluate(endpoint, providerID: config.providerID, scopes: [.sourceText]) == .granted)

        var moved = config
        moved.baseURL = URL(string: "https://gateway.example.com/v1")!
        guard case .required(let changed) = ledger.evaluate(TestPacks.endpoint(for: moved), providerID: config.providerID, scopes: [.sourceText]) else {
            Issue.record("a new destination must need consent"); return
        }
        #expect(changed.reasons.contains(.destinationChanged(previousOrigin: "http://127.0.0.1:1234")))
        #expect(changed.reasons.contains(.classificationChanged(previous: .local)))
        #expect(changed.lines[2].contains("can't check who operates it"))

        var otherModel = endpoint
        otherModel.model = "bigger-model"
        guard case .required(let modelChange) = ledger.evaluate(otherModel, providerID: config.providerID, scopes: [.sourceText]) else {
            Issue.record("a model change must need consent"); return
        }
        #expect(modelChange.reasons == [.modelChanged(previousModel: "local-model")])

        guard case .required(let broader) = ledger.evaluate(endpoint, providerID: config.providerID, scopes: [.sourceText, .savedThoughts]) else {
            Issue.record("sharing notes must need consent"); return
        }
        #expect(broader.reasons == [.broaderSharing(added: [.savedThoughts])])
        #expect(broader.lines[1].contains("the saved thoughts you selected"))
    }

    @Test func packWithNotesNeedsBroaderConsentInTheCoordinator() async throws {
        var ledger = ConsentLedger()
        if case .required(let d) = ledger.evaluate(TestPacks.endpoint(for: Self.localConfig), providerID: Self.localConfig.providerID, scopes: [.sourceText]) {
            ledger.grant(d, providerID: Self.localConfig.providerID, at: Date())
        }
        let h = try Harness(scripts: [[Self.accepted, Self.text("ok"), Self.done]], consent: ledger)
        let pack = TestPacks.make(config: Self.localConfig, evidence: [(TestPacks.waldenPassage, .sourceText), ("My note about simplicity.", .userNote)])
        _ = try await h.coordinator.createDraft(pack: pack, config: Self.localConfig)
        let prepared = try await h.coordinator.prepare(pack.requestID)
        #expect(prepared.state == .awaitingConsent)
        #expect(await h.coordinator.disclosure(for: pack.requestID)?.reasons == [.broaderSharing(added: [.savedThoughts])])
    }
}

/// The generic adapter end to end through the coordinator against the loopback fake server (brief item 9).
@Suite("Local endpoint end to end")
struct LocalEndpointEndToEndTests {
    @Test func retryAfterA503ThenStreamToComplete() async throws {
        let server = try await FakeHTTPServer { request in
            if request.index == 0 { return .json(503, #"{"error":{"message":"loading model","type":"server_error"}}"#, headers: [("Retry-After", "0")]) }
            return .sse([
                "data: {\"id\":\"x\",\"model\":\"local-model\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Thoreau wanted to \"},\"finish_reason\":null}]}\n\n",
                "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"live deliberately [c1].\"},\"finish_reason\":\"stop\"}]}\n\n",
                "data: [DONE]\n\n",
            ], pauseMs: 10)
        }
        let config = Configs.generic(server)
        let store = try FileAskStore(directory: TestPacks.temporaryDirectory())
        let sleeper = RecordingSleeper()
        let coordinator = AskCoordinator(store: store, providerFactory: { HTTPTextGenerationProvider(config: $0, credentials: InMemoryCredentialStore(), transport: URLSessionTransport()) },
                                         connectivity: FakeConnectivity(online: true), sleeper: sleeper, retry: RetryPolicy(jitter: false))
        let pack = TestPacks.make(config: config)
        _ = try await coordinator.createDraft(pack: pack, config: config)
        _ = try await coordinator.prepare(pack.requestID)
        _ = try await coordinator.grantConsent(pack.requestID)
        let record = try await coordinator.send(pack.requestID)
        #expect(record.state == .complete)
        #expect(record.answerText == "Thoreau wanted to live deliberately [c1].")
        #expect(sleeper.sleeps == [.zero])
        #expect(server.requests.count == 2)
        for request in server.requests {
            #expect(request.bodyText.components(separatedBy: "living deliberately?").count - 1 == 1, "question sent exactly once per attempt")
            #expect(request.bodyText.contains("<evidence id=\\\"c1\\\""))
        }
        let resolved = CitationResolver.resolve(record.answerText, pack: record.pack)
        #expect(resolved.citations.map(\.isResolved) == [true])
    }

    /// R2-04 (plan 14.4: no automatic replay of a generation whose acceptance is uncertain). A 502 or 504 is a gateway
    /// reporting an upstream failure, a 500 may come after generation started, and any 5xx from a user-managed endpoint
    /// may be a gateway relaying an upstream that accepted the request: none is resent without the user.
    @Test(arguments: [(502, false), (504, false), (500, false), (503, true), (529, true)])
    func serverErrorsWhoseAcceptanceIsUncertainAreNeverReplayedAutomatically(status: Int, userManaged: Bool) async throws {
        let server = try await FakeHTTPServer { request in
            if request.index == 0 { return .json(status, #"{"error":{"message":"upstream failed","type":"server_error"}}"#, headers: [("Retry-After", "0")]) }
            return .sse(["data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Answer [c1].\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"])
        }
        let config = userManaged
            ? ProviderConfig(kind: .openAICompatibleChat, displayName: "Gateway", baseURL: try BaseURL.normalize("https://gateway.example.com/v1"),
                             model: "gateway-model", credential: nil, requestTimeoutMs: 5_000)
            : Configs.generic(server)
        let transport: any HTTPTransport = userManaged ? LoopbackRewriteTransport(target: server.baseURL) : URLSessionTransport()
        #expect(try EndpointIdentity.of(config).classification == (userManaged ? .userManaged : .local))
        let sleeper = RecordingSleeper()
        let coordinator = AskCoordinator(store: try FileAskStore(directory: TestPacks.temporaryDirectory()),
                                         providerFactory: { HTTPTextGenerationProvider(config: $0, credentials: InMemoryCredentialStore(), transport: transport) },
                                         connectivity: FakeConnectivity(online: true), sleeper: sleeper, retry: RetryPolicy(jitter: false))
        let pack = TestPacks.make(config: config)
        _ = try await coordinator.createDraft(pack: pack, config: config)
        _ = try await coordinator.prepare(pack.requestID)
        _ = try await coordinator.grantConsent(pack.requestID)
        let record = try await coordinator.send(pack.requestID)
        #expect(record.state == .failedRetryable)
        #expect(record.failure?.kind == .serverError)
        #expect(record.failure?.acceptance == .uncertain)
        #expect(record.failure?.resubmitNeedsConfirmation == true)
        #expect(record.failure?.userMessage.contains("may or may not have been processed") == true)
        #expect(server.requests.count == 1, "HTTP \(status) is not resent automatically")
        #expect(sleeper.sleeps.isEmpty)
        await #expect(throws: AskError.resubmitNeedsConfirmation) { try await coordinator.send(pack.requestID) }
        #expect(server.requests.count == 1)
        let confirmed = try await coordinator.send(pack.requestID, userConfirmedResubmit: true)
        #expect(confirmed.state == .complete)
        #expect(server.requests.count == 2)
    }

    @Test func serverErrorAcceptanceDependsOnTheStatusAndTheEndpoint() {
        let redactor = Redactor()
        func acceptance(_ status: Int, _ classification: EndpointClassification?) -> Acceptance {
            ErrorClassifier.classifyHTTP(status: status, headers: [:], body: Data(), host: "h", redactor: redactor, classification: classification).acceptance
        }
        // Certainly not accepted: the service said it did not take the request.
        for classification in [EndpointClassification.hosted, .local] {
            #expect(acceptance(503, classification) == .rejected)
            #expect(acceptance(529, classification) == .rejected)
        }
        // Uncertain: a gateway's upstream failure or timeout, a failure while handling the request, or any 5xx from an
        // endpoint that may itself be a gateway.
        for classification in [EndpointClassification.hosted, .local, .userManaged, nil] {
            for status in [500, 502, 504, 507, 599] { #expect(acceptance(status, classification) == .uncertain, "\(status) \(String(describing: classification))") }
        }
        for status in [500, 502, 503, 504, 529] { #expect(acceptance(status, .userManaged) == .uncertain) }
        #expect(acceptance(503, nil) == .uncertain, "an unknown classification is treated as user-managed")
        // Rate limits and client errors are refusals before generating.
        #expect(acceptance(429, .userManaged) == .rejected)
        #expect(acceptance(400, .userManaged) == .rejected)
        #expect(ProviderError(kind: .serverError, acceptance: .uncertain, host: "h", httpStatus: 502).isTransient == false)
        #expect(ProviderError(kind: .serverError, acceptance: .rejected, host: "h", httpStatus: 503).isTransient == true)
    }

    @Test func requestCarriesExactlyThePackAndNothingElse() async throws {
        // No hidden upload (plan 14.2): the body is the system text plus the pack's evidence and question,
        // reproducible from the stored pack alone.
        let server = try await FakeHTTPServer { _ in
            .sse(["data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"ok\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"])
        }
        let config = Configs.generic(server)
        let coordinator = AskCoordinator(store: try FileAskStore(directory: TestPacks.temporaryDirectory()),
                                         providerFactory: { HTTPTextGenerationProvider(config: $0, credentials: InMemoryCredentialStore(), transport: URLSessionTransport()) },
                                         connectivity: FakeConnectivity(online: true), sleeper: RecordingSleeper())
        let pack = TestPacks.make(config: config, evidence: [(TestPacks.waldenPassage, .sourceText), ("My own note.", .userNote)])
        _ = try await coordinator.createDraft(pack: pack, config: config)
        _ = try await coordinator.prepare(pack.requestID)
        _ = try await coordinator.grantConsent(pack.requestID)
        _ = try await coordinator.send(pack.requestID)
        let json = try #require(server.requests.first?.json)
        let sent = try #require(json["messages"] as? [[String: String]])
        let expected = PromptTemplate.request(for: pack, maxOutputTokens: pack.budget.outputReserveTokens)
        #expect(sent.count == 1 + expected.messages.count)
        #expect(sent[0] == ["role": "system", "content": expected.system])
        for (index, message) in expected.messages.enumerated() {
            #expect(sent[index + 1] == ["role": message.role.rawValue, "content": message.text])
        }
        #expect(Set(json.keys) == ["model", "messages", "stream", "max_tokens"], "no extra fields such as tools, user IDs or metadata")
    }

    /// R3-01 over real HTTP through the generic adapter (the reviewer's probes): a reply that ends normally with no answer
    /// text (reasoning fields only, a `<think>` block only, or `data: [DONE]` alone) is a failure, never "Complete".
    @Test(arguments: [
        ("reasoning only", [LocalEndpointEndToEndTests.chatChunk(#"{"reasoning_content":"The user asks about Thoreau. I should think"}"#),
                            LocalEndpointEndToEndTests.chatChunk(#"{"reasoning_content":" for a long time."}"#), LocalEndpointEndToEndTests.chatChunk("{}", finish: "stop"), "data: [DONE]\n\n"], true),
        ("think block only", [LocalEndpointEndToEndTests.chatChunk(#"{"content":"<think>The user asks about Thoreau."}"#), LocalEndpointEndToEndTests.chatChunk(#"{"content":" Still thinking.</think>\n\n"}"#),
                              LocalEndpointEndToEndTests.chatChunk("{}", finish: "stop"), "data: [DONE]\n\n"], true),
        ("[DONE] only", ["data: [DONE]\n\n"], false),
    ])
    func replyWithNoAnswerTextIsNeverComplete(label: String, sse: [String], reasoning: Bool) async throws {
        let server = try await FakeHTTPServer { _ in .sse(sse) }
        let sleeper = RecordingSleeper()
        let coordinator = AskCoordinator(store: try FileAskStore(directory: TestPacks.temporaryDirectory()),
                                         providerFactory: { HTTPTextGenerationProvider(config: $0, credentials: InMemoryCredentialStore(), transport: URLSessionTransport()) },
                                         connectivity: FakeConnectivity(online: true), sleeper: sleeper, retry: RetryPolicy(jitter: false))
        let record = try await Self.ask(coordinator, config: Configs.generic(server))
        #expect(record.state == .failedRetryable, "\(label)")
        #expect(record.outcome == .noAnswerText, "\(label)")
        #expect(record.answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(label): no reasoning saved as the answer")
        #expect(record.reasoningOmitted == reasoning, "\(label)")
        #expect(record.statusPhrase != "Complete" && record.statusPhrase != "Interrupted · partial answer", "\(label)")
        #expect(record.statusPhrase == (reasoning
            ? "127.0.0.1 sent only its reasoning and no answer text. Models that reason first may need a larger maximum output for this endpoint."
            : "127.0.0.1 ended its reply without any answer text. If the model reasons first, it may need a larger maximum output for this endpoint."), "\(label)")
        #expect(record.failure?.kind == .invalidResponse && record.failure?.acceptance == .uncertain, "\(label)")
        #expect(record.failure?.resubmitNeedsConfirmation == true, "\(label): the generation may have been billed")
        #expect(server.requests.count == 1 && sleeper.sleeps.isEmpty, "\(label): not resent automatically")
        await #expect(throws: AskError.resubmitNeedsConfirmation) { try await coordinator.send(record.id) }
        #expect(server.requests.count == 1)
    }

    /// R3-02 over real HTTP: text cut off by a content filter (generic adapter) or followed by a refusal stop
    /// (Anthropic adapter) is a labelled partial answer, never "Complete".
    @Test func textCutOffByAFilterOrARefusalStopIsAPartialAnswer() async throws {
        let filtered = try await FakeHTTPServer { _ in
            .sse([Self.chatChunk(#"{"content":"Thoreau went to the woods because"}"#), Self.chatChunk("{}", finish: "content_filter"), "data: [DONE]\n\n"])
        }
        let coordinator = try Self.coordinator(limits: StreamLimits())
        let first = try await Self.ask(coordinator, config: Configs.generic(filtered))
        #expect(first.state == .interrupted)
        #expect(first.outcome == .contentFiltered)
        #expect(first.answerText == "Thoreau went to the woods because")
        #expect(first.statusPhrase == "Interrupted · partial answer")
        #expect(first.outcomeMessage == "127.0.0.1's content filter cut the answer off. What arrived before that is kept as a partial answer.")

        let refusing = try await FakeHTTPServer { _ in
            .sse([
                "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_1\",\"model\":\"claude-test\",\"content\":[],\"usage\":{\"input_tokens\":9,\"output_tokens\":1}}}\n\n",
                "event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
                "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Thoreau went to the woods because\"}}\n\n",
                "event: content_block_stop\ndata: {\"type\":\"content_block_stop\",\"index\":0}\n\n",
                "event: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"refusal\"},\"usage\":{\"output_tokens\":7}}\n\n",
                "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n",
            ])
        }
        let credentials = InMemoryCredentialStore()
        let ref = CredentialRef(origin: "https://api.anthropic.com")
        try credentials.save(Secret(Canary.anthropicKey), for: ref)
        let config = Configs.anthropic(ref)
        let transport = LoopbackRewriteTransport(target: refusing.baseURL)
        var consent = ConsentLedger()
        if case .required(let disclosure) = consent.evaluate(TestPacks.endpoint(for: config), providerID: config.providerID, scopes: [.sourceText]) {
            consent.grant(disclosure, providerID: config.providerID, at: Date())
        }
        let anthropic = AskCoordinator(store: try FileAskStore(directory: TestPacks.temporaryDirectory()), consent: consent,
                                       providerFactory: { HTTPTextGenerationProvider(config: $0, credentials: credentials, transport: transport) },
                                       connectivity: FakeConnectivity(online: true), sleeper: RecordingSleeper())
        let pack = TestPacks.make(config: config)
        _ = try await anthropic.createDraft(pack: pack, config: config)
        let second = try await anthropic.send(pack.requestID)
        #expect(second.state == .interrupted)
        #expect(second.outcome == .refusal)
        #expect(second.answerText == "Thoreau went to the woods because")
        #expect(second.statusPhrase == "Interrupted · partial answer")
        #expect(second.outcomeMessage == "api.anthropic.com stopped partway and declined to continue. What arrived before that is kept as a partial answer.")
        #expect(refusing.requests.count == 1)
    }

    static func chatChunk(_ delta: String, finish: String? = nil) -> String {
        "data: {\"id\":\"x\",\"model\":\"local-model\",\"choices\":[{\"index\":0,\"delta\":\(delta),\"finish_reason\":\(finish.map { "\"\($0)\"" } ?? "null")}]}\n\n"
    }

    static func coordinator(limits: StreamLimits) throws -> AskCoordinator {
        AskCoordinator(store: try FileAskStore(directory: TestPacks.temporaryDirectory()),
                       providerFactory: { HTTPTextGenerationProvider(config: $0, credentials: InMemoryCredentialStore(), transport: URLSessionTransport(), limits: limits) },
                       connectivity: FakeConnectivity(online: true), sleeper: RecordingSleeper())
    }

    static func ask(_ coordinator: AskCoordinator, config: ProviderConfig) async throws -> AskRecord {
        let pack = TestPacks.make(config: config)
        _ = try await coordinator.createDraft(pack: pack, config: config)
        _ = try await coordinator.prepare(pack.requestID)
        _ = try await coordinator.grantConsent(pack.requestID)
        return try await coordinator.send(pack.requestID)
    }

    /// Plan 14.5: a server that keeps the stream open with keepalive comments never produces an event and never
    /// trips URLSession's idle timeout; the transport-level time limit stops it.
    @Test func keepaliveCommentsWithoutEndHitTheTimeLimit() async throws {
        let server = try await FakeHTTPServer { _ in
            .sse(["data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Partial \"},\"finish_reason\":null}]}\n\n"]
                 + Array(repeating: ": keepalive\n\n", count: 200), pauseMs: 50)
        }
        let started = ContinuousClock.now
        let record = try await Self.ask(try Self.coordinator(limits: StreamLimits(maxDuration: .seconds(2))), config: Configs.generic(server))
        #expect(ContinuousClock.now - started < .seconds(8), "stopped near the limit, not at the end of the server's script")
        #expect(record.state == .interrupted)
        #expect(record.outcome == .partial)
        #expect(record.failure?.kind == .responseTimeLimit)
        #expect(record.answerText == "Partial ")
        #expect(server.requests.count == 1, "no automatic resend")
    }

    @Test func bodyBeyondTheByteCapIsStopped() async throws {
        let delta = "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"more words \"},\"finish_reason\":null}]}\n\n"
        let server = try await FakeHTTPServer { _ in .sse(Array(repeating: delta, count: 400)) }
        let record = try await Self.ask(try Self.coordinator(limits: StreamLimits(bytesPerOutputToken: 0, minimumBytes: 4_000)), config: Configs.generic(server))
        #expect(record.state == .interrupted)
        #expect(record.failure?.kind == .responseSizeLimit)
        #expect(!record.answerText.isEmpty && record.answerText.utf8.count < 4_000)
        #expect(server.requests.count == 1)
    }

    /// A stream that goes silent after its headers is ended by the request's wall-clock limit, not left to the idle
    /// timeout (60 s by default, and reset by any trickle).
    @Test func silentStreamIsEndedByTheWallClockLimit() async throws {
        let server = try await FakeHTTPServer { _ in
            FakeResponse(status: 200, headers: [("Content-Type", "text/event-stream")], steps: [.pause(milliseconds: 10_000)])
        }
        let started = ContinuousClock.now
        let record = try await Self.ask(try Self.coordinator(limits: StreamLimits(maxDuration: .seconds(2))), config: Configs.generic(server))
        #expect(ContinuousClock.now - started < .seconds(8))
        #expect(record.state == .failedRetryable)
        #expect(record.failure?.kind == .responseTimeLimit)
        #expect(record.failure?.resubmitNeedsConfirmation == true)
        #expect(server.requests.count == 1)
    }

    /// A server that answers with one JSON body (not a stream) is bounded too: a body trickled byte by byte never
    /// trips URLSession's idle timeout, and an oversized one is refused rather than read without end.
    @Test func singleJSONBodyIsBoundedInTimeAndSize() async throws {
        let trickle = try await FakeHTTPServer { _ in
            FakeResponse(status: 200, headers: [("Content-Type", "application/json")],
                         steps: [.send(Data("{".utf8))] + Array(repeating: [FakeStep.pause(milliseconds: 50), .send(Data(" ".utf8))], count: 200).flatMap { $0 })
        }
        let started = ContinuousClock.now
        let slow = try await Self.ask(try Self.coordinator(limits: StreamLimits(maxDuration: .seconds(2))), config: Configs.generic(trickle))
        #expect(ContinuousClock.now - started < .seconds(8), "stopped near the limit, not at the end of the server's script")
        #expect(slow.state == .failedRetryable)
        #expect(slow.failure?.kind == .responseTimeLimit)
        #expect(slow.failure?.resubmitNeedsConfirmation == true, "the provider may have generated it, so no silent resend")
        #expect(trickle.requests.count == 1)

        let huge = #"{"choices":[{"index":0,"message":{"role":"assistant","content":""# + String(repeating: "word ", count: 2_000) + #""},"finish_reason":"stop"}]}"#
        let big = try await FakeHTTPServer { _ in .json(200, huge) }
        let large = try await Self.ask(try Self.coordinator(limits: StreamLimits(bytesPerOutputToken: 0, minimumBytes: 4_000)), config: Configs.generic(big))
        #expect(large.state == .failedRetryable)
        #expect(large.failure?.kind == .responseSizeLimit)
        #expect(large.answerText.isEmpty, "a truncated body is never parsed into an answer")
        #expect(big.requests.count == 1)
    }

    @Test func contextTooLongIsExplainedAndEvidenceIsNotSilentlyDropped() async throws {
        let server = try await FakeHTTPServer { _ in
            .json(400, #"{"error":{"message":"This model's maximum context length is 4096 tokens. However, your messages resulted in 9000 tokens.","type":"invalid_request_error","param":"messages","code":"context_length_exceeded"}}"#)
        }
        let config = Configs.generic(server)
        let coordinator = AskCoordinator(store: try FileAskStore(directory: TestPacks.temporaryDirectory()),
                                         providerFactory: { HTTPTextGenerationProvider(config: $0, credentials: InMemoryCredentialStore(), transport: URLSessionTransport()) },
                                         connectivity: FakeConnectivity(online: true), sleeper: RecordingSleeper())
        let pack = TestPacks.make(config: config)
        _ = try await coordinator.createDraft(pack: pack, config: config)
        _ = try await coordinator.prepare(pack.requestID)
        _ = try await coordinator.grantConsent(pack.requestID)
        let record = try await coordinator.send(pack.requestID)
        #expect(record.state == .failedFinal)
        #expect(record.failure?.kind == .contextTooLong)
        #expect(record.statusPhrase.contains("Choose a narrower context"))
        #expect(record.pack == pack, "the pack is unchanged: reducing scope is the user's choice, with a new pack")
        #expect(server.requests.count == 1, "no automatic resend with silently fewer passages")
    }
}

/// Lets a scripted step wait until the coordinator has taken in the output so far, so that a clock change in the next
/// step is ordered after it (the scripted provider and the coordinator run concurrently).
final class ObservedRecord: Sendable {
    private let target = Mutex<(AskCoordinator, UUID)?>(nil)

    func watch(_ coordinator: AskCoordinator, _ id: UUID) { target.withLock { $0 = (coordinator, id) } }

    func waitForAnswer(_ text: String) async {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if let (coordinator, id) = target.withLock({ $0 }), (try? await coordinator.record(id).answerText) == text { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("the coordinator never held \"\(text)\"")
    }
}
