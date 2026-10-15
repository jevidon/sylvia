import Foundation
import G05TestSupport
import Testing
@testable import SylviaAI
@testable import SylviaContext

/// Review round 2: earlier turns of a conversation are content too. R2-02 (I-07, plan 14.2): an earlier answer can
/// repeat the notes it was based on, so a turn is resent only to the destination it went to, its scopes count towards
/// consent, and the disclosure names it. R2-03 (plan 13.4, A.2): an earlier answer's citation IDs pointed into an
/// earlier pack, so they are never resent and can never resolve against the current pack's evidence.
@Suite("Conversation history: consent and citations", .serialized)
struct ConversationHistoryTests {
    static let noteCanary = "MARGIN-NOTE-CANARY"
    static let selectionText = "I went to the woods because I wished to live deliberately"

    /// A fake OpenAI-compatible server that always answers with `answer`.
    static func server(answer: String) async throws -> FakeHTTPServer {
        try await FakeHTTPServer { _ in
            .sse(["data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\(String(decoding: try! JSONSerialization.data(withJSONObject: answer, options: .fragmentsAllowed), as: UTF8.self))},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"])
        }
    }

    static func config(_ server: FakeHTTPServer, model: String) -> ProviderConfig {
        ProviderConfig(kind: .openAICompatibleChat, displayName: model, baseURL: try! BaseURL.normalize(server.baseURL.absoluteString + "/v1"),
                       model: model, credential: nil, requestTimeoutMs: 5_000, allowInsecureLocalHTTP: true)
    }

    static func build(_ request: ContextRequest, for config: ProviderConfig) throws -> ContextPack {
        try ContextPackBuilder(index: Library.index).build(request, work: Library.walden.snapshot, config: config,
                                                           endpoint: TestPacks.endpoint(for: config), createdAt: Library.now)
    }

    static func coordinator() throws -> AskCoordinator {
        AskCoordinator(store: try FileAskStore(directory: TestPacks.temporaryDirectory()),
                       providerFactory: { HTTPTextGenerationProvider(config: $0, credentials: InMemoryCredentialStore(), transport: URLSessionTransport()) },
                       connectivity: FakeConnectivity(online: true), sleeper: RecordingSleeper())
    }

    static var selection: TextSelection {
        TextSelection(paragraphOrdinal: Library.paragraph(in: Library.walden, containing: selectionText).ordinal, exactText: selectionText)
    }

    /// Turn 1: a question about the user's own note, answered by `config`'s server, with consent for saved thoughts.
    static func askAboutANote(_ coordinator: AskCoordinator, config: ProviderConfig, conversation: UUID) async throws -> AskRecord {
        let note = SavedThought(captureID: UUID(), kind: .note, text: "\(noteCanary): simplicity is a discipline, not a mood.",
                                workID: nil, editionID: nil, locationLabel: "Note", ordinal: nil)
        let pack = try build(ContextRequest(question: "What does my note say about simplicity?", conversationID: conversation,
                                            scope: .selectedThoughts, thoughts: [note]), for: config)
        _ = try await coordinator.createDraft(pack: pack, config: config)
        #expect(try await coordinator.prepare(pack.requestID).state == .awaitingConsent)
        #expect(await coordinator.disclosure(for: pack.requestID)?.scopes == [.savedThoughts])
        _ = try await coordinator.grantConsent(pack.requestID)
        let record = try await coordinator.send(pack.requestID)
        #expect(record.state == .complete)
        return record
    }

    /// The reviewer's case: turn 1 asks provider A about the user's notes; the user then asks provider B about a
    /// selected passage in the same conversation. Consent for B covers source text only, so turn 1 (whose answer
    /// repeats the note) must not reach B, and the disclosure must not hide anything that is sent.
    @Test func earlierAnswerBasedOnNotesNeverReachesANewDestination() async throws {
        let serverA = try await Self.server(answer: "Your note says \(Self.noteCanary) [c1].")
        let serverB = try await Self.server(answer: "Thoreau means living on purpose [c1].")
        let configA = Self.config(serverA, model: "model-a"), configB = Self.config(serverB, model: "model-b")
        let coordinator = try Self.coordinator()
        let conversation = UUID()
        let first = try await Self.askAboutANote(coordinator, config: configA, conversation: conversation)
        #expect(first.answerText.contains(Self.noteCanary))
        let turn = ConversationTurnSnapshot(question: first.question, answer: first.answerText, pack: first.pack)
        #expect(turn.sharedScopes == [.savedThoughts])
        #expect(turn.destination == TestPacks.endpoint(for: configA))
        #expect(turn.maxEvidenceOrdinal == nil, "a note has no position in the work")

        let pack = try Self.build(ContextRequest(question: "What does he mean by deliberately?", conversationID: conversation, scope: .selectedPassage,
                                                 selection: Self.selection, history: [turn]), for: configB)
        #expect(pack.history.includedTurns.isEmpty)
        #expect(pack.history.excludedTurnCount == 1)
        #expect(pack.history.exclusionReason == "1 earlier question in this conversation went to a different provider or model, so it and its answer weren't sent to 127.0.0.1 · local · model-b.")
        #expect(SharingScope.scopes(for: pack) == [.sourceText])
        _ = try await coordinator.createDraft(pack: pack, config: configB)
        #expect(try await coordinator.prepare(pack.requestID).state == .awaitingConsent)
        let disclosure = try #require(await coordinator.disclosure(for: pack.requestID))
        #expect(disclosure.scopes == [.sourceText])
        #expect(disclosure.lines[1] == "What is sent: your question, 1 selected passage from \(Library.walden.snapshot.title). Nothing else from your library is sent.")
        _ = try await coordinator.grantConsent(pack.requestID)
        #expect(try await coordinator.send(pack.requestID).state == .complete)
        let sentToB = try #require(serverB.requests.first?.bodyText)
        #expect(serverB.requests.count == 1)
        #expect(!sentToB.contains(Self.noteCanary), "the earlier answer based on the note never reaches B")
        #expect(!sentToB.contains("What does my note say"), "nor does the earlier question")

        // A pack built by hand that resends turn 1 to B is refused before anything is stored or sent.
        var smuggled = pack
        smuggled.requestID = UUID()
        smuggled.history = HistoryInclusion(includedTurns: [turn])
        smuggled.packSHA256 = smuggled.computeDigest()
        #expect(smuggled.historyViolations.count == 2, "another destination, and a citation marker from its own pack")
        await #expect(throws: AskError.packHistoryInvalid) { try await coordinator.createDraft(pack: smuggled, config: configB) }
        #expect(serverB.requests.count == 1)
    }

    /// Same origin, different model: a different destination as consent defines it, so the turn is not resent.
    @Test func aModelChangeAtTheSameOriginIsAnotherDestination() async throws {
        let server = try await Self.server(answer: "unused")
        let first = Self.config(server, model: "model-a"), second = Self.config(server, model: "model-a-large")
        let turn = ConversationTurnSnapshot(turnID: UUID(), question: "Earlier?", answer: "Earlier answer.", maxEvidenceOrdinal: 10, editionID: Library.walden.snapshot.editionID,
                                            sharedScopes: [.sourceText], destination: TestPacks.endpoint(for: first))
        let request = ContextRequest(question: "What does he mean by deliberately?", scope: .selectedPassage, selection: Self.selection, history: [turn])
        #expect(try Self.build(request, for: first).history.includedTurns.count == 1)
        let other = try Self.build(request, for: second)
        #expect(other.history.includedTurns.isEmpty)
        #expect(other.history.excludedTurnCount == 1)
        #expect(server.requests.isEmpty)
    }

    /// Back at the same destination the earlier turn is resent, and it counts: its scopes join the pack's, the
    /// disclosure names it, and consent covers what it shared.
    @Test func earlierTurnsAreDisclosedAndCountTowardsConsent() async throws {
        let serverA = try await Self.server(answer: "Your note says \(Self.noteCanary) [c1].")
        let configA = Self.config(serverA, model: "model-a")
        let coordinator = try Self.coordinator()
        let conversation = UUID()
        let first = try await Self.askAboutANote(coordinator, config: configA, conversation: conversation)
        let turn = ConversationTurnSnapshot(question: first.question, answer: first.answerText, pack: first.pack)

        let pack = try Self.build(ContextRequest(question: "What does he mean by deliberately?", conversationID: conversation, scope: .selectedPassage,
                                                 selection: Self.selection, history: [turn]), for: configA)
        #expect(pack.history.includedTurns.count == 1)
        #expect(SharingScope.evidenceScopes(for: pack) == [.sourceText])
        #expect(SharingScope.scopes(for: pack) == [.savedThoughts, .sourceText])
        // A destination that has never been approved sees every part of what is sent.
        guard case .required(let fresh) = ConsentLedger().evaluate(pack: pack, providerID: configA.providerID) else {
            Issue.record("consent expected"); return
        }
        #expect(fresh.scopes == [.savedThoughts, .sourceText])
        #expect(fresh.lines[1] == "What is sent: your question, 1 selected passage from \(Library.walden.snapshot.title), 1 earlier question and answer from this conversation, including answers based on your saved thoughts. Nothing else from your library is sent.")
        // A was approved for saved thoughts in turn 1; adding the passage is broader sharing, disclosed with the turn.
        _ = try await coordinator.createDraft(pack: pack, config: configA)
        #expect(try await coordinator.prepare(pack.requestID).state == .awaitingConsent)
        let disclosure = try #require(await coordinator.disclosure(for: pack.requestID))
        #expect(disclosure.reasons == [.broaderSharing(added: [.sourceText])])
        #expect(disclosure.lines[1].contains("1 earlier question and answer from this conversation"))
        _ = try await coordinator.grantConsent(pack.requestID)
        #expect(try await coordinator.send(pack.requestID).state == .complete)
        let sent = try #require(serverA.requests.last?.json?["messages"] as? [[String: String]])
        #expect(sent.map { $0["role"] } == ["system", "user", "assistant", "user"])
        #expect(sent[2]["content"] == "Your note says \(Self.noteCanary) [earlier source].", "resent to the destination that wrote it, without its citation marker")
    }

    /// R2-03: the earlier answer's [c1] pointed at the note in turn 1's pack. The new pack's c1 is a Walden passage, so the
    /// marker is never resent, and the model cannot carry it over to the wrong passage.
    @Test func earlierCitationIDsAreNeverResentOrResolvedAgainstTheNewPack() async throws {
        let server = try await Self.server(answer: "unused")
        let config = Self.config(server, model: "model-a")
        let endpoint = TestPacks.endpoint(for: config)
        let earlier = "The note [c1] and the passage [c2, C3] agree; see also [ c4 ]."
        let turn = ConversationTurnSnapshot(turnID: UUID(), question: "Do they agree?", answer: earlier, maxEvidenceOrdinal: 10, editionID: Library.walden.snapshot.editionID,
                                            sharedScopes: [.savedThoughts, .sourceText], destination: endpoint)
        let pack = try Self.build(ContextRequest(question: "What does he mean by deliberately?", scope: .selectedPassage, selection: Self.selection,
                                                 history: [turn]), for: config)
        #expect(pack.evidence.map(\.citationID) == ["c1"], "every pack numbers its evidence from c1")
        let resent = try #require(pack.history.includedTurns.first?.answer)
        #expect(resent == "The note [earlier source] and the passage [earlier source] agree; see also [earlier source].")
        #expect(pack.historyViolations.isEmpty)
        let request = PromptTemplate.request(for: pack, maxOutputTokens: 100)
        #expect(request.messages[1].role == .assistant)
        #expect(!PromptTemplate.containsCitationMarker(request.messages[1].text), "no earlier ID reaches the model")
        #expect(request.system.contains("[earlier source]"), "the model is told what the replacement means")
        #expect(pack.promptTemplateVersion == "sylvia-grounded-3")

        // What the model can do with the earlier answer: repeat "[earlier source]", which stays plain text and links
        // nowhere, while [c1] can only mean the passage sent now.
        let resolved = CitationResolver.resolve("As said before [earlier source]; here he says so directly [c1].", pack: pack)
        #expect(resolved.citations.count == 1)
        #expect(resolved.citations.first?.evidenceID == pack.evidence[0].evidenceID)
        #expect(resolved.segments.first == .text("As said before [earlier source]; here he says so directly "))

        // A pack built by hand with an earlier marker is refused by the coordinator, and the template never resends it.
        var handBuilt = TestPacks.make(config: config)
        handBuilt.history = HistoryInclusion(includedTurns: [turn])
        handBuilt.packSHA256 = handBuilt.computeDigest()
        #expect(handBuilt.historyViolations == ["included turn \(turn.turnID) has a citation marker from its own pack"])
        let coordinator = try Self.coordinator()
        await #expect(throws: AskError.packHistoryInvalid) { try await coordinator.createDraft(pack: handBuilt, config: config) }
        let template = PromptTemplate.request(for: handBuilt, maxOutputTokens: 100)
        #expect(!template.messages.contains { $0.role == .assistant && PromptTemplate.containsCitationMarker($0.text) })
        #expect(server.requests.isEmpty)
    }

    @Test func neutralizingMarkersIsIdempotentAndLeavesOtherBracketsAlone() {
        let text = "See [c1], [C2; c3] and [ c12 ] but not [1], [note] or [cat]."
        let once = PromptTemplate.neutralizeCitationMarkers(text)
        #expect(once == "See [earlier source], [earlier source] and [earlier source] but not [1], [note] or [cat].")
        #expect(PromptTemplate.neutralizeCitationMarkers(once) == once)
        #expect(!PromptTemplate.containsCitationMarker(once))
        #expect(PromptTemplate.containsCitationMarker(text))
    }

    /// The turn an answer adds records the highest position its pack used, or unknown when any part has none.
    @Test func aTurnRecordsWhatItsPackUsed() throws {
        let config = Library.config
        let passage = try Self.build(ContextRequest(question: "What does he mean by deliberately?", scope: .passageAndNearby, selection: Self.selection), for: config)
        let turn = ConversationTurnSnapshot(question: passage.question, answer: "It means on purpose [c1].", pack: passage)
        #expect(turn.maxEvidenceOrdinal == passage.maxEvidenceOrdinal)
        #expect(turn.sharedScopes == [.sourceText])
        #expect(turn.turnID == passage.requestID)
        // A later turn that resent it records the union of what both shared.
        let thought = SavedThought(captureID: UUID(), kind: .note, text: "My note.", workID: nil, editionID: nil, locationLabel: "Note", ordinal: nil)
        let next = try Self.build(ContextRequest(question: "And my note?", scope: .selectedThoughts, thoughts: [thought], history: [turn]), for: config)
        let nextTurn = ConversationTurnSnapshot(question: next.question, answer: "Both.", pack: next)
        #expect(nextTurn.sharedScopes == [.savedThoughts, .sourceText])
        #expect(nextTurn.maxEvidenceOrdinal == nil, "the note has no position, so the turn's position is unknown")
    }
}
