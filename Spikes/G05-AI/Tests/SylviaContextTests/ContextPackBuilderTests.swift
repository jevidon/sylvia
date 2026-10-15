import Foundation
import G05TestSupport
import Testing
@testable import SylviaAI
@testable import SylviaContext

/// Shared fixture: Walden and Middlemarch extracted, chunked and indexed once (in-memory GRDB database).
enum Library {
    struct IndexedWork: Sendable {
        let snapshot: WorkSnapshot
        let work: ExtractedWork
        let chunks: [TextChunk]
    }

    static let index = try! PassageIndex()
    static let walden = load("epub/se-walden.epub")
    static let middlemarch = load("epub/se-middlemarch.epub")

    static func load(_ path: String) -> IndexedWork {
        let work = try! EPUBTextExtractor.extract(epubAt: RepoFixtures.url(path))
        let chunks = Chunker.chunk(work.paragraphs)
        let snapshot = WorkSnapshot(workID: UUID(), editionID: UUID(), title: work.title, authorDisplay: work.author, sourceKind: "local_epub")
        try! index.index(work: work, workID: snapshot.workID, chunks: chunks)
        return IndexedWork(snapshot: snapshot, work: work, chunks: chunks)
    }

    static let config = ProviderConfig(kind: .openAICompatibleChat, displayName: "Local", baseURL: URL(string: "http://127.0.0.1:1234/v1")!,
                                       model: "local-model", credential: nil, allowInsecureLocalHTTP: true)
    static let endpoint = TestPacks.endpoint(for: config)
    static let now = Date(timeIntervalSince1970: 1_791_590_400.1234)

    static func paragraph(in work: IndexedWork, containing text: String) -> ExtractedParagraph {
        work.work.paragraphs.first { $0.text.contains(text) }!
    }

    static func build(_ request: ContextRequest, work: IndexedWork, config: ProviderConfig = config,
                      settings: BuilderSettings = BuilderSettings()) throws -> ContextPack {
        try ContextPackBuilder(index: index, settings: settings).build(request, work: work.snapshot, config: config, endpoint: endpoint, createdAt: now)
    }
}

@Suite("Lexical retrieval (FTS5 through GRDB)")
struct RetrievalTests {
    @Test func indexIsConsistent() throws {
        let counts = try Library.index.counts(workID: Library.walden.snapshot.workID)
        #expect(counts.paragraphs == Library.walden.work.paragraphs.count)
        #expect(counts.chunks == Library.walden.chunks.count)
    }

    @Test func finds_theKnownWaldenPassage() throws {
        let result = try Library.index.search(workID: Library.walden.snapshot.workID,
                                              question: "Why did Thoreau go to the woods to live deliberately?", maxOrdinal: nil, limit: 5)
        #expect(result.terms == ["thoreau", "go", "woods", "live", "deliberately"])
        let ranks = result.hits.filter { $0.chunk.text.contains("I went to the woods because I wished to live deliberately") }.map(\.rank)
        #expect(ranks.first.map { $0 <= 3 } == true, "expected the passage in the top 3, got ranks \(ranks)")
    }

    @Test(arguments: [
        #"what about "quoted phrase" and NEAR(woods pond, 2)"#,
        "text: pond OR -woods AND ^solitude *",
        "'); DROP TABLE chunk; --",
        #"chunk_fts MATCH 'x' "" """#,
        "{text}: col* ~ ^ $ ( ) [ ] : ; ,",
        "Ünïcödé — 😀 étang",
    ])
    func hostileQueriesAreLiteralTermsNotSyntax(query: String) throws {
        let result = try Library.index.search(workID: Library.walden.snapshot.workID, question: query, maxOrdinal: nil, limit: 3)
        for term in result.terms { #expect(term.allSatisfy { $0.isLetter || $0.isNumber }) }
        #expect(try Library.index.counts(workID: Library.walden.snapshot.workID).chunks == Library.walden.chunks.count, "tables intact")
    }

    @Test func matchExpressionQuotesEveryTerm() {
        #expect(FTSQuery.matchExpression(["pond", "near"]) == #""pond" OR "near""#)
        #expect(FTSQuery.matchExpression([]) == nil)
        #expect(FTSQuery.terms(from: "What is the meaning of this?") == ["meaning"])
        #expect(FTSQuery.terms(from: String(repeating: "word", count: 1) + (1...40).map { " w\($0)" }.joined()).count == FTSQuery.maxTerms)
    }

    @Test func boundaryFiltersInSQLBeforeRanking() throws {
        let mm = Library.middlemarch
        let boundary = mm.work.paragraphs.last { $0.resourceHref == "text/chapter-10.xhtml" }!.ordinal
        let open = try Library.index.search(workID: mm.snapshot.workID, question: "Raffles Bulstrode", maxOrdinal: nil, limit: 5)
        #expect(open.hits.contains { $0.chunk.text.contains("Raffles") }, "unrestricted search reaches the later chapters")
        let restricted = try Library.index.search(workID: mm.snapshot.workID, question: "Raffles Bulstrode", maxOrdinal: boundary, limit: 5)
        #expect(!restricted.hits.isEmpty)
        #expect(restricted.hits.allSatisfy { $0.chunk.lastOrdinal <= boundary })
        #expect(!restricted.hits.contains { $0.chunk.text.contains("Raffles") })
        #expect(restricted.excludedByBoundary > 0)
    }
}

@Suite("ContextPack builder")
struct ContextPackBuilderTests {
    static let waldenParagraph = Library.paragraph(in: Library.walden, containing: "I went to the woods because I wished to live deliberately")
    static let selection = TextSelection(paragraphOrdinal: waldenParagraph.ordinal,
                                         exactText: "I went to the woods because I wished to live deliberately, to front only the essential facts of life")

    @Test func selectedPassageContainsExactlyTheSelection() throws {
        let pack = try Library.build(ContextRequest(question: "What does he mean?", scope: .selectedPassage, selection: Self.selection), work: Library.walden)
        #expect(pack.evidence.count == 1)
        #expect(pack.evidence[0].citationID == "c1")
        #expect(pack.evidence[0].text == Self.selection.exactText)
        #expect(pack.evidence[0].textSHA256 == SHA256Hex.of(Self.selection.exactText))
        #expect(pack.evidence[0].position?.firstOrdinal == Self.waldenParagraph.ordinal)
        #expect(pack.scopeLabel == "Selected passage")
        #expect(pack.coverage == .excerptOnly)
        #expect(pack.digestIsValid)
        #expect(pack.endpoint.disclosureRow == "127.0.0.1 · local · local-model")
        let roundTrip = try ContextPack.decoder().decode(ContextPack.self, from: ContextPack.encoder().encode(pack))
        #expect(roundTrip == pack)
    }

    @Test func passageAndNearbyStaysInTheChapterAndIsBounded() throws {
        let pack = try Library.build(ContextRequest(question: "What does he mean?", scope: .passageAndNearby, selection: Self.selection), work: Library.walden)
        #expect(pack.scopeLabel == "Passage and nearby text")
        #expect(pack.evidence.map(\.role) == [.selection, .nearby, .nearby, .nearby])
        #expect(pack.evidence[1].text == Self.waldenParagraph.text)
        for item in pack.evidence { #expect(item.position?.resourceHref == Self.waldenParagraph.resourceHref) }
        let before = pack.evidence[2], after = pack.evidence[3]
        #expect(before.position!.lastOrdinal == Self.waldenParagraph.ordinal - 1)
        #expect(after.position!.firstOrdinal == Self.waldenParagraph.ordinal + 1)
        // Each side stops at the first paragraph that reaches the 250-word allowance.
        let words = { (text: String) in text.split(whereSeparator: \.isWhitespace).count }
        let lastBefore = Library.walden.work.paragraphs[before.position!.firstOrdinal]
        #expect(words(before.text) - lastBefore.wordCount < 250)
    }

    @Test func workSearchRetrievesBoundedPassagesAndSaysSo() throws {
        let pack = try Library.build(ContextRequest(question: "Why did Thoreau go to the woods to live deliberately?", scope: .workSearch), work: Library.walden)
        #expect(pack.scopeLabel == "Relevant passages from this work")
        #expect(pack.coverageLabel == "Relevant passages retrieved")
        #expect(pack.retrieval?.strategy == "fts5_bm25")
        #expect(pack.retrieval?.queryTerms == ["thoreau", "go", "woods", "live", "deliberately"])
        #expect(pack.evidence.count <= BuilderSettings().topK + 2)
        #expect(pack.evidence.contains { $0.text.contains("I wished to live deliberately") })
        #expect(pack.evidence.filter { $0.role == .retrieved }.map { $0.retrieval!.rank } == Array(1...pack.evidence.filter { $0.role == .retrieved }.count))
        #expect(pack.evidence.map(\.citationID) == (1...pack.evidence.count).map { "c\($0)" })
        #expect(!pack.truncation.truncated)
    }

    @Test func selectedThoughtsUseTheirOwnOriginsAndAreCapped() throws {
        let thoughts = [
            SavedThought(captureID: UUID(), kind: .quote, text: "Simplify, simplify.", workID: Library.walden.snapshot.workID, editionID: Library.walden.snapshot.editionID, locationLabel: "Where I Lived", ordinal: Self.waldenParagraph.ordinal + 3),
            SavedThought(captureID: UUID(), kind: .note, text: "My note: compare with Seneca on time.", workID: nil, editionID: nil, locationLabel: "Note", ordinal: nil),
        ]
        let pack = try Library.build(ContextRequest(question: "How do these relate?", scope: .selectedThoughts, thoughts: thoughts), work: Library.walden)
        #expect(pack.coverageLabel == "Selected thoughts only")
        #expect(pack.evidence.map(\.origin) == [.savedQuote, .userNote])
        #expect(pack.evidence.map(\.sourceQuality) == [.exactCapture, .userEntered])
        #expect(pack.evidence.map(\.captureID) == thoughts.map(\.captureID))
        #expect(SharingScope.scopes(for: pack) == [.savedThoughts])
        let tooMany = Array(repeating: thoughts[1], count: 9)
        #expect(throws: ContextBuildError.tooManyThoughts(limit: 8)) {
            try Library.build(ContextRequest(question: "q", scope: .selectedThoughts, thoughts: tooMany), work: Library.walden)
        }
    }

    /// R4-03 (plan 14.2: state what will be sent): the "What is sent" line counts passages from the work by how they were
    /// chosen and counts saved thoughts apart, so a note is never described as a passage from the book. The whole line
    /// is asserted for each scope and for a pack that mixes passages and a note.
    @Test func disclosureCountsPassagesByHowTheyWereChosenAndThoughtsApart() throws {
        struct NoDisclosure: Error {}
        func whatIsSent(_ pack: ContextPack) throws -> String {
            guard case .required(let disclosure) = ConsentLedger().evaluate(pack: pack, providerID: Library.config.providerID) else { throw NoDisclosure() }
            return disclosure.lines[1]
        }
        let title = Library.walden.snapshot.title
        let mixed = TestPacks.make(config: Library.config, evidence: [(TestPacks.waldenPassage, .sourceText), ("Simplify, simplify.", .sourceText),
                                                                      ("My note: compare with Seneca on time.", .userNote)])
        #expect(try whatIsSent(mixed) == "What is sent: your question, 2 selected passages from Walden, 1 saved thought you selected. Nothing else from your library is sent.")

        let nearby = try Library.build(ContextRequest(question: "What does he mean?", scope: .passageAndNearby, selection: Self.selection), work: Library.walden)
        #expect(nearby.evidence.map(\.role) == [.selection, .nearby, .nearby, .nearby])
        #expect(try whatIsSent(nearby) == "What is sent: your question, 1 selected passage and 3 nearby passages from \(title). Nothing else from your library is sent.")

        let search = try Library.build(ContextRequest(question: "Why did Thoreau go to the woods to live deliberately?", scope: .workSearch), work: Library.walden)
        let retrieved = search.evidence.count
        #expect(retrieved > 1 && search.evidence.allSatisfy { $0.role == .retrieved || $0.role == .adjacent })
        #expect(try whatIsSent(search) == "What is sent: your question, \(retrieved) retrieved passages from \(title). Nothing else from your library is sent.")

        let searchWithSelection = try Library.build(ContextRequest(question: "Why did Thoreau go to the woods to live deliberately?", scope: .workSearch,
                                                                   selection: Self.selection), work: Library.walden)
        let found = searchWithSelection.evidence.filter { $0.role != .selection }.count
        #expect(try whatIsSent(searchWithSelection)
                == "What is sent: your question, 1 selected passage and \(found) retrieved passage\(found == 1 ? "" : "s") from \(title). Nothing else from your library is sent.")

        let thoughts = try Library.build(ContextRequest(question: "How do these relate?", scope: .selectedThoughts, thoughts: [
            SavedThought(captureID: UUID(), kind: .quote, text: "Simplify, simplify.", workID: Library.walden.snapshot.workID, editionID: Library.walden.snapshot.editionID, locationLabel: "Where I Lived", ordinal: Self.waldenParagraph.ordinal + 3),
            SavedThought(captureID: UUID(), kind: .note, text: "My note: compare with Seneca on time.", workID: nil, editionID: nil, locationLabel: "Note", ordinal: nil),
        ]), work: Library.walden)
        #expect(try whatIsSent(thoughts) == "What is sent: your question, 2 saved thoughts you selected. Nothing else from your library is sent.")

        var big = Library.config
        big.contextLimitTokens = 1_000_000
        let book = try Library.build(ContextRequest(question: "What is this book about?", scope: .wholeWork), work: Library.walden, config: big)
        #expect(book.evidence.allSatisfy { $0.role == .wholeWork })
        #expect(try whatIsSent(book) == "What is sent: your question, the whole text of \(title) (\(book.evidence.count) passages). Nothing else from your library is sent.")
    }

    @Test func budgetArithmeticIsExplicitAndLabelledAsAnEstimate() throws {
        let pack = try Library.build(ContextRequest(question: "Why did Thoreau go to the woods?", scope: .workSearch), work: Library.walden)
        let b = pack.budget
        #expect(b.contextLimitSource == .defaultUnknownModel)
        #expect(b.contextLimitTokens == 8_192)
        #expect(b.estimated)
        #expect(b.estimator == TokenEstimatorInfo(kind: .heuristic, name: "utf8-bytes-div-3"))
        #expect(b.evidenceBudgetTokens == b.contextLimitTokens - b.systemTokens - b.questionTokens - b.historyTokens - b.outputReserveTokens - b.safetyMarginTokens)
        #expect(b.evidenceTokens == pack.evidence.map(\.estimatedTokens).reduce(0, +))
        #expect(b.evidenceTokens <= b.evidenceBudgetTokens)
        // The heuristic over-counts relative to the common ~4 bytes/token: estimate ≥ bytes / 4.
        #expect(pack.evidence.allSatisfy { $0.estimatedTokens >= $0.text.utf8.count / 4 })
    }

    @Test func truncationIsDisclosedNotSilent() throws {
        var config = Library.config
        config.contextLimitTokens = 3_000
        config.maxOutputTokens = 500
        let pack = try Library.build(ContextRequest(question: "Why did Thoreau go to the woods to live deliberately?", scope: .workSearch),
                                     work: Library.walden, config: config)
        #expect(pack.budget.contextLimitSource == .configured)
        #expect(pack.truncation.truncated)
        #expect(pack.truncation.omittedEvidenceCount > 0)
        #expect(pack.truncation.disclosure?.contains("didn't fit") == true)
        #expect(pack.budget.evidenceTokens <= pack.budget.evidenceBudgetTokens)
    }

    @Test func oversizedSelectionIsAnErrorNotATrim() throws {
        var config = Library.config
        config.contextLimitTokens = 1_200
        config.maxOutputTokens = 200
        let long = Library.walden.work.paragraphs.max { $0.wordCount < $1.wordCount }!
        #expect(throws: ContextBuildError.self) {
            try Library.build(ContextRequest(question: "q", scope: .selectedPassage, selection: TextSelection(paragraphOrdinal: long.ordinal, exactText: long.text)),
                              work: Library.walden, config: config)
        }
    }

    @Test func wholeWorkOnlyWhenItTrulyFits() throws {
        #expect(throws: ContextBuildError.self) {
            try Library.build(ContextRequest(question: "Summarize", scope: .wholeWork), work: Library.walden)
        }
        var big = Library.config
        big.contextLimitTokens = 1_000_000
        let pack = try Library.build(ContextRequest(question: "Summarize", scope: .wholeWork), work: Library.walden, config: big)
        #expect(pack.coverage == .wholeWork)
        #expect(pack.evidence.count == Library.walden.chunks.count)
    }

    @Test func wholeWorkIsNeverLabelledSoWhenASpoilerBoundaryApplies() {
        var big = Library.config
        big.contextLimitTokens = 1_000_000
        let paragraph = Library.paragraph(in: Library.walden, containing: "I went to the woods because")
        #expect(throws: ContextBuildError.wholeWorkWithSpoilerBoundary) {
            try Library.build(ContextRequest(question: "Summarize", scope: .wholeWork, excludeLaterPassages: true,
                                             confirmedPosition: ReadingPosition(editionID: Library.walden.snapshot.editionID, paragraphOrdinal: paragraph.ordinal)), work: Library.walden, config: big)
        }
        #expect(ContextBuildError.wholeWorkWithSpoilerBoundary.userMessage.contains("Relevant passages from this work"))
    }

    /// Plan 13.3 / 10.4: when nothing is sent, or an audio passage cannot be given, the pack carries the statement.
    @Test func emptyAndAudioPacksStateTheirLimitation() throws {
        let noTerms = try Library.build(ContextRequest(question: "What is this?", scope: .workSearch), work: Library.walden)
        #expect(noTerms.evidence.isEmpty && noTerms.coverage == .noPassages)
        #expect(noTerms.limitations.map(\.code) == [.noSearchableTerms])

        let noMatch = try Library.build(ContextRequest(question: "xylophones zeppelins quasars", scope: .workSearch), work: Library.walden)
        #expect(noMatch.evidence.isEmpty && noMatch.coverageLabel == "No passages sent")
        #expect(noMatch.limitations.map(\.code) == [.noMatchingPassages])

        let boundary = Library.middlemarch.work.paragraphs.last { $0.resourceHref == "text/chapter-10.xhtml" }!.ordinal
        let later = try Library.build(ContextRequest(question: "Raffles", scope: .workSearch, excludeLaterPassages: true,
                                                     confirmedPosition: ReadingPosition(editionID: Library.middlemarch.snapshot.editionID, paragraphOrdinal: boundary)), work: Library.middlemarch)
        #expect(later.evidence.isEmpty && later.spoilerBoundary.excludedEvidenceCount > 0)
        #expect(later.limitations.map(\.code) == [.allExcludedByBoundary])

        let found = try Library.build(ContextRequest(question: "Why did Thoreau go to the woods?", scope: .workSearch), work: Library.walden)
        #expect(found.limitations.isEmpty && found.coverage == .retrievedPassages)

        let note = SavedThought(captureID: UUID(), kind: .note, text: "Something about his grandfather at 2:30.", workID: nil, editionID: nil, locationLabel: "Note", ordinal: nil)
        let audio = try Library.build(ContextRequest(question: "What did the narrator say?", scope: .selectedThoughts, thoughts: [note],
                                                     audioMoment: "Meditations, Book One, 2:30"), work: Library.walden)
        #expect(audio.limitations.map(\.code) == [.audioPassageUnavailable])
        #expect(audio.limitations[0].disclosure.contains("Meditations, Book One, 2:30"))
        let transcript = SavedThought(captureID: UUID(), kind: .transcript, text: "From my grandfather Verus I learned good morals.", workID: nil,
                                      editionID: nil, locationLabel: "2:30", ordinal: nil)
        let transcribed = try Library.build(ContextRequest(question: "What did the narrator say?", scope: .selectedThoughts, thoughts: [transcript],
                                                           audioMoment: "Meditations, Book One, 2:30"), work: Library.walden)
        #expect(transcribed.limitations.isEmpty, "a transcript of the moment is in the pack")
        #expect(throws: ContextBuildError.thoughtsRequired) {
            try Library.build(ContextRequest(question: "q", scope: .selectedThoughts), work: Library.walden)
        }
    }

    @Test func selectionMustExistInTheExtractedText() {
        #expect(throws: ContextBuildError.selectionNotFound) {
            try Library.build(ContextRequest(question: "q", scope: .selectedPassage,
                                             selection: TextSelection(paragraphOrdinal: Self.waldenParagraph.ordinal, exactText: "words that are not there")),
                              work: Library.walden)
        }
    }
}

/// T32 / plan 13.3: the spoiler boundary filters retrieval before sending and excludes earlier turns that used
/// later passages.
@Suite("Spoiler boundary")
struct SpoilerBoundaryTests {
    static let mm = Library.middlemarch
    static let boundary = mm.work.paragraphs.last { $0.resourceHref == "text/chapter-10.xhtml" }!.ordinal

    @Test func restrictedWorkSearchContainsNothingAfterThePosition() throws {
        let request = ContextRequest(question: "Who is Raffles and what does he know about Bulstrode?", scope: .workSearch,
                                     excludeLaterPassages: true, confirmedPosition: ReadingPosition(editionID: Self.mm.snapshot.editionID, paragraphOrdinal: Self.boundary))
        let pack = try Library.build(request, work: Self.mm)
        #expect(pack.spoilerBoundary.enabled)
        #expect(pack.spoilerBoundary.basis == .userConfirmedPosition)
        #expect(pack.spoilerBoundary.maxOrdinal == Self.boundary)
        #expect(pack.spoilerBoundary.excludedEvidenceCount > 0)
        #expect(pack.evidence.allSatisfy { ($0.position?.lastOrdinal ?? Int.max) <= Self.boundary })
        #expect(!pack.evidence.contains { $0.text.contains("Raffles") })
        // The serialized request contains no later text either (outside the user's own question).
        let body = PromptTemplate.request(for: pack, maxOutputTokens: 100).messages.map(\.text).joined()
            .replacingOccurrences(of: PromptTemplate.escape(pack.question), with: "")
        #expect(!body.contains("Raffles"))
        #expect(pack.maxEvidenceOrdinal.map { $0 <= Self.boundary } ?? true)
    }

    @Test func unrestrictedSearchDoesReachLaterChapters() throws {
        let pack = try Library.build(ContextRequest(question: "Who is Raffles and what does he know about Bulstrode?", scope: .workSearch), work: Self.mm)
        #expect(pack.evidence.contains { $0.text.contains("Raffles") })
        #expect(!pack.spoilerBoundary.enabled)
    }

    @Test func nearbyTextStopsAtTheSelectionWhenRestricted() throws {
        let paragraph = Self.mm.work.paragraphs.first { $0.resourceHref == "text/chapter-10.xhtml" && $0.wordCount > 40 }!
        let selection = TextSelection(paragraphOrdinal: paragraph.ordinal, exactText: String(paragraph.text.prefix(60)))
        let pack = try Library.build(ContextRequest(question: "q", scope: .passageAndNearby, selection: selection, excludeLaterPassages: true), work: Self.mm)
        #expect(pack.spoilerBoundary.basis == .selectionPosition)
        #expect(pack.evidence.allSatisfy { ($0.position?.lastOrdinal ?? 0) <= paragraph.ordinal })
    }

    @Test func earlierTurnsThatUsedLaterPassagesAreExcluded() throws {
        let history = [
            ConversationTurnSnapshot(turnID: UUID(), question: "Early question", answer: "Early answer", maxEvidenceOrdinal: Self.boundary - 50, editionID: Self.mm.snapshot.editionID, sharedScopes: [.sourceText], destination: Library.endpoint),
            ConversationTurnSnapshot(turnID: UUID(), question: "Who is Raffles?", answer: "Raffles knows Bulstrode's past.", maxEvidenceOrdinal: Self.boundary + 2_000, editionID: Self.mm.snapshot.editionID, sharedScopes: [.sourceText], destination: Library.endpoint),
            ConversationTurnSnapshot(turnID: UUID(), question: "Unknown provenance", answer: "Something", maxEvidenceOrdinal: nil, editionID: Self.mm.snapshot.editionID, sharedScopes: [.sourceText], destination: Library.endpoint),
        ]
        let restricted = try Library.build(ContextRequest(question: "What is Bulstrode like?", scope: .workSearch, excludeLaterPassages: true,
                                                          confirmedPosition: ReadingPosition(editionID: Self.mm.snapshot.editionID, paragraphOrdinal: Self.boundary), history: history), work: Self.mm)
        #expect(restricted.history.includedTurns.map(\.question) == ["Early question"])
        #expect(restricted.history.excludedTurnCount == 2)
        // R6-01: each excluded turn is counted under the reason that is true for it.
        #expect(restricted.history.exclusionReason == "Earlier answers in this conversation used passages beyond your position, so they weren't sent. Start a new conversation with \"Do not include later passages\" to keep them out entirely. Earlier answers in this conversation used material whose place in this edition isn't known, so they weren't sent.")
        let body = PromptTemplate.request(for: restricted, maxOutputTokens: 100).messages.map(\.text).joined()
        #expect(!body.contains("Raffles"))

        let open = try Library.build(ContextRequest(question: "What is Bulstrode like?", scope: .workSearch, history: history), work: Self.mm)
        #expect(open.history.includedTurns.count == 3)
    }

    @Test func restrictedThoughtsBeyondThePositionAreExcluded() throws {
        let thoughts = [
            SavedThought(captureID: UUID(), kind: .quote, text: "An early quote", workID: Self.mm.snapshot.workID, editionID: Self.mm.snapshot.editionID, locationLabel: "I", ordinal: 10),
            SavedThought(captureID: UUID(), kind: .note, text: "Note on the ending", workID: Self.mm.snapshot.workID, editionID: Self.mm.snapshot.editionID, locationLabel: "LXXXVI", ordinal: Self.boundary + 3_000),
        ]
        let pack = try Library.build(ContextRequest(question: "q", scope: .selectedThoughts, thoughts: thoughts, excludeLaterPassages: true,
                                                    confirmedPosition: ReadingPosition(editionID: Self.mm.snapshot.editionID, paragraphOrdinal: Self.boundary)), work: Self.mm)
        #expect(pack.evidence.map(\.text) == ["An early quote"])
        #expect(pack.spoilerBoundary.excludedEvidenceCount == 1)
        // R4-06: the kept thought records its work and place, so the stored pack shows it lies within the boundary.
        #expect(pack.evidence[0].workID == Self.mm.snapshot.workID)
        #expect(pack.evidence[0].position?.firstOrdinal == 10 && pack.evidence[0].position?.lastOrdinal == 10)
        #expect(pack.evidence[0].position?.resourceHref == Self.mm.work.paragraphs[10].resourceHref)
        #expect(pack.spoilerBoundaryViolations.isEmpty)
    }

    /// R4-06: the spoiler self-check covers saved thoughts, not only source text. A restricted pack holding a thought on
    /// this work from after the position, or one whose place is unknown, breaks its boundary; the builder never returns
    /// one and the coordinator refuses it (`packWithALaterThoughtIsNeverStored`). A thought on another work, or on none,
    /// has no place in this work and is not restricted by it.
    @Test func spoilerSelfCheckCoversSavedThoughts() throws {
        let thoughts = [
            SavedThought(captureID: UUID(), kind: .quote, text: "An early quote", workID: Self.mm.snapshot.workID, editionID: Self.mm.snapshot.editionID, locationLabel: "I", ordinal: 10),
            SavedThought(captureID: UUID(), kind: .note, text: "A note on another book", workID: Library.walden.snapshot.workID, editionID: Library.walden.snapshot.editionID, locationLabel: "Walden", ordinal: 9_000),
            SavedThought(captureID: UUID(), kind: .note, text: "A general note", workID: nil, editionID: nil, locationLabel: "Note", ordinal: nil),
        ]
        let pack = try Library.build(ContextRequest(question: "q", scope: .selectedThoughts, thoughts: thoughts, excludeLaterPassages: true,
                                                    confirmedPosition: ReadingPosition(editionID: Self.mm.snapshot.editionID, paragraphOrdinal: Self.boundary)), work: Self.mm)
        #expect(pack.evidence.map(\.text) == thoughts.map(\.text))
        #expect(pack.evidence.map(\.workID) == thoughts.map(\.workID))
        #expect(pack.evidence[1].position == nil && pack.evidence[2].position == nil, "no place in this work")
        #expect(pack.spoilerBoundaryViolations.isEmpty)

        var later = pack
        later.evidence[0].position = EvidencePosition(resourceHref: "text/chapter-86.xhtml", firstOrdinal: Self.boundary + 3_000, lastOrdinal: Self.boundary + 3_000)
        #expect(later.spoilerBoundaryViolations == ["c1 ends at paragraph \(Self.boundary + 3_000), after the boundary \(Self.boundary)"])
        var unplaced = pack
        unplaced.evidence[0].position = nil
        #expect(unplaced.spoilerBoundaryViolations == ["c1 is from this work but has no position, so it can't be shown to lie within the boundary"])
        // Without the boundary the same thoughts are unrestricted.
        unplaced.spoilerBoundary = .disabled
        #expect(unplaced.spoilerBoundaryViolations.isEmpty)
    }

    /// A thought on this work whose place is not in this edition's text can't be shown to lie within the boundary, so a
    /// restricted pack leaves it out; an unrestricted pack keeps it without a position.
    @Test func restrictedThoughtWithAnUnknownPlaceIsLeftOut() throws {
        let thought = SavedThought(captureID: UUID(), kind: .quote, text: "A quote whose place is not in this text", workID: Self.mm.snapshot.workID,
                                   editionID: Self.mm.snapshot.editionID, locationLabel: "?", ordinal: Self.mm.work.paragraphs.count + 50)
        let restricted = try Library.build(ContextRequest(question: "q", scope: .selectedThoughts, thoughts: [thought], excludeLaterPassages: true,
                                                          confirmedPosition: ReadingPosition(editionID: Self.mm.snapshot.editionID, paragraphOrdinal: Self.mm.work.paragraphs.count + 100)), work: Self.mm)
        #expect(restricted.evidence.isEmpty)
        #expect(restricted.spoilerBoundary.excludedEvidenceCount == 1)
        #expect(restricted.limitations == [ContextLimitation(code: .allExcludedByBoundary,
                                                             disclosure: "None of the thoughts you selected can be shown to come before your position, so none were sent.")])
        let open = try Library.build(ContextRequest(question: "q", scope: .selectedThoughts, thoughts: [thought]), work: Self.mm)
        #expect(open.evidence.map(\.text) == [thought.text])
        #expect(open.evidence[0].position == nil)
    }

    /// R5-03 (plan 13.3, I-05): ordinals count one edition's extracted paragraphs. A thought captured in another edition of
    /// this work, at an ordinal that in this edition lies before the position (in its own edition it may be far later),
    /// has no known place here: a restricted pack leaves it out rather than compare foreign ordinals, and never records
    /// this edition's href or ID for it; an unrestricted pack keeps it on the work without a position or an edition. A
    /// thought at the same ordinal in this edition keeps its place.
    @Test func thoughtFromAnotherEditionHasNoPlaceInThisOne() throws {
        let otherEdition = SavedThought(captureID: UUID(), kind: .note, text: "Note made in another edition", workID: Self.mm.snapshot.workID,
                                        editionID: UUID(), locationLabel: "Chapter I", ordinal: 10)
        let thisEdition = SavedThought(captureID: UUID(), kind: .quote, text: "Quote made in this edition", workID: Self.mm.snapshot.workID,
                                       editionID: Self.mm.snapshot.editionID, locationLabel: "Chapter I", ordinal: 10)
        #expect(10 < Self.boundary)

        let restricted = try Library.build(ContextRequest(question: "q", scope: .selectedThoughts, thoughts: [otherEdition, thisEdition],
                                                          excludeLaterPassages: true, confirmedPosition: ReadingPosition(editionID: Self.mm.snapshot.editionID, paragraphOrdinal: Self.boundary)), work: Self.mm)
        #expect(restricted.evidence.map(\.text) == [thisEdition.text])
        #expect(restricted.evidence[0].editionID == Self.mm.snapshot.editionID)
        #expect(restricted.evidence[0].position == EvidencePosition(resourceHref: Self.mm.work.paragraphs[10].resourceHref, firstOrdinal: 10, lastOrdinal: 10))
        #expect(restricted.spoilerBoundary.excludedEvidenceCount == 1)
        #expect(restricted.spoilerBoundaryViolations.isEmpty)

        let onlyOther = try Library.build(ContextRequest(question: "q", scope: .selectedThoughts, thoughts: [otherEdition], excludeLaterPassages: true,
                                                         confirmedPosition: ReadingPosition(editionID: Self.mm.snapshot.editionID, paragraphOrdinal: Self.boundary)), work: Self.mm)
        #expect(onlyOther.evidence.isEmpty)
        #expect(onlyOther.limitations == [ContextLimitation(code: .allExcludedByBoundary,
                                                            disclosure: "None of the thoughts you selected can be shown to come before your position, so none were sent.")])

        let open = try Library.build(ContextRequest(question: "q", scope: .selectedThoughts, thoughts: [otherEdition, thisEdition]), work: Self.mm)
        #expect(open.evidence.map(\.text) == [otherEdition.text, thisEdition.text])
        #expect(open.evidence[0].workID == Self.mm.snapshot.workID)
        #expect(open.evidence[0].position == nil && open.evidence[0].editionID == nil, "no place or edition is claimed for it")
        #expect(open.evidence[1].position?.lastOrdinal == 10 && open.evidence[1].editionID == Self.mm.snapshot.editionID)
        // A turn built from the open pack has no known position (one item has no place here), so a restricted pack
        // never resends it.
        #expect(ConversationTurnSnapshot(question: "q", answer: "a", pack: open).maxEvidenceOrdinal == nil)
    }

    /// R5-03: the spoiler self-check (used by the builder, the coordinator and, in Python, the contract check) refuses a
    /// position or an included turn counted in another edition, even when its ordinal is before the boundary.
    @Test func spoilerSelfCheckRefusesAPositionInAnotherEdition() throws {
        let thought = SavedThought(captureID: UUID(), kind: .quote, text: "An early quote", workID: Self.mm.snapshot.workID,
                                   editionID: Self.mm.snapshot.editionID, locationLabel: "I", ordinal: 10)
        let turn = ConversationTurnSnapshot(turnID: UUID(), question: "Early question", answer: "Early answer", maxEvidenceOrdinal: Self.boundary - 50,
                                            editionID: Self.mm.snapshot.editionID, sharedScopes: [.sourceText], destination: Library.endpoint)
        let pack = try Library.build(ContextRequest(question: "q", scope: .selectedThoughts, thoughts: [thought], excludeLaterPassages: true,
                                                    confirmedPosition: ReadingPosition(editionID: Self.mm.snapshot.editionID, paragraphOrdinal: Self.boundary), history: [turn]), work: Self.mm)
        #expect(pack.evidence.count == 1 && pack.history.includedTurns.count == 1)
        #expect(pack.spoilerBoundaryViolations.isEmpty)

        var foreignItem = pack
        foreignItem.evidence[0].editionID = UUID()
        #expect(foreignItem.spoilerBoundaryViolations == ["c1 has a position in another edition, so it can't be compared with the boundary"])
        var noEdition = pack
        noEdition.evidence[0].editionID = nil
        #expect(noEdition.spoilerBoundaryViolations == ["c1 has a position in another edition, so it can't be compared with the boundary"])
        var foreignTurn = pack
        foreignTurn.history.includedTurns[0].editionID = UUID()
        #expect(foreignTurn.spoilerBoundaryViolations == ["included turn \(turn.turnID) used paragraphs of another edition, so they can't be compared with the boundary"])
        #expect(throws: AskError.packViolatesSpoilerBoundary) { try AskCoordinator.validate(pack: foreignItem, config: Library.config) }
        #expect(throws: AskError.packViolatesSpoilerBoundary) { try AskCoordinator.validate(pack: foreignTurn, config: Library.config) }
    }

    /// R5-03: an earlier turn whose evidence was counted in another edition is left out of a restricted pack with its own
    /// reason; the same turn in this edition is included.
    @Test func earlierTurnsFromAnotherEditionAreExcluded() throws {
        let history = [
            ConversationTurnSnapshot(turnID: UUID(), question: "Asked in this edition", answer: "Answer one.", maxEvidenceOrdinal: Self.boundary - 50,
                                     editionID: Self.mm.snapshot.editionID, sharedScopes: [.sourceText], destination: Library.endpoint),
            ConversationTurnSnapshot(turnID: UUID(), question: "Asked in another edition", answer: "Answer two.", maxEvidenceOrdinal: Self.boundary - 50,
                                     editionID: UUID(), sharedScopes: [.sourceText], destination: Library.endpoint),
            ConversationTurnSnapshot(turnID: UUID(), question: "Asked without evidence", answer: "Answer three.", maxEvidenceOrdinal: -1,
                                     editionID: UUID(), sharedScopes: [], destination: Library.endpoint),
        ]
        #expect(history[2].editionID == nil, "a turn that used no evidence names no edition")
        let restricted = try Library.build(ContextRequest(question: "What is Bulstrode like?", scope: .workSearch, excludeLaterPassages: true,
                                                          confirmedPosition: ReadingPosition(editionID: Self.mm.snapshot.editionID, paragraphOrdinal: Self.boundary), history: history), work: Self.mm)
        #expect(restricted.history.includedTurns.map(\.question) == ["Asked in this edition", "Asked without evidence"])
        #expect(restricted.history.excludedTurnCount == 1)
        #expect(restricted.history.exclusionReason == "Earlier answers in this conversation used passages from another edition, which Sylvia can't compare with your position, so they weren't sent.")
        #expect(restricted.spoilerBoundaryViolations.isEmpty)
        let open = try Library.build(ContextRequest(question: "What is Bulstrode like?", scope: .workSearch, history: history), work: Self.mm)
        #expect(open.history.includedTurns.count == 3)
        // A turn made from a restricted pack names the pack's edition.
        let next = ConversationTurnSnapshot(question: "What is Bulstrode like?", answer: "Pious.", pack: restricted)
        #expect(next.editionID == Self.mm.snapshot.editionID)
        #expect(next.maxEvidenceOrdinal.map { $0 <= Self.boundary } == true)
    }

    static let unknownPlaceReason = "Earlier answers in this conversation used material whose place in this edition isn't known, so they weren't sent."
    static let beyondReason = "Earlier answers in this conversation used passages beyond your position, so they weren't sent. Start a new conversation with \"Do not include later passages\" to keep them out entirely."

    /// R6-01 (I-06, plan 22.3): a turn whose evidence has no known place in this edition is left out of a restricted pack
    /// with a reason that says so, never "used passages beyond your position". Both of the reviewer's probes go through the
    /// real snapshot initializer: P3, a restricted pack holding only a general note (which a restricted pack may send);
    /// P3b, an unrestricted pack holding a thought captured in another edition.
    @Test func earlierTurnsWithAnUnknownPlaceSayWhy() throws {
        let position = ReadingPosition(editionID: Self.mm.snapshot.editionID, paragraphOrdinal: Self.boundary)
        let generalNote = SavedThought(captureID: UUID(), kind: .note, text: "A general note on vocation.", workID: nil, editionID: nil,
                                       locationLabel: "Note", ordinal: nil)
        let noteOnly = try Library.build(ContextRequest(question: "What does my note say?", scope: .selectedThoughts, thoughts: [generalNote],
                                                        excludeLaterPassages: true, confirmedPosition: position), work: Self.mm)
        #expect(noteOnly.evidence.map(\.origin) == [.userNote] && noteOnly.spoilerBoundary.enabled)
        let p3 = ConversationTurnSnapshot(question: noteOnly.question, answer: "Your note says vocation matters.", pack: noteOnly)
        #expect(p3.maxEvidenceOrdinal == nil && p3.editionID == nil, "a note has no place in this edition")

        let otherEditionThought = SavedThought(captureID: UUID(), kind: .note, text: "Note made in another edition", workID: Self.mm.snapshot.workID,
                                               editionID: UUID(), locationLabel: "Chapter I", ordinal: 10)
        let foreign = try Library.build(ContextRequest(question: "What did I note?", scope: .selectedThoughts, thoughts: [otherEditionThought]), work: Self.mm)
        let p3b = ConversationTurnSnapshot(question: foreign.question, answer: "You noted the opening.", pack: foreign)
        #expect(p3b.maxEvidenceOrdinal == nil && p3b.editionID == nil)

        for turn in [p3, p3b] {
            let next = try Library.build(ContextRequest(question: "What is Bulstrode like?", scope: .workSearch, excludeLaterPassages: true,
                                                        confirmedPosition: position, history: [turn]), work: Self.mm)
            #expect(next.history.includedTurns.isEmpty)
            #expect(next.history.excludedTurnCount == 1)
            #expect(next.history.exclusionReason == Self.unknownPlaceReason)
            #expect(next.spoilerBoundaryViolations.isEmpty)
            // Without the restriction the turn is resent.
            let open = try Library.build(ContextRequest(question: "What is Bulstrode like?", scope: .workSearch, history: [turn]), work: Self.mm)
            #expect(open.history.includedTurns.map(\.turnID) == [turn.turnID] && open.history.exclusionReason == nil)
        }

        // One turn for each of the four reasons a turn can be left out of a pack with a confirmed position (the fifth, no
        // position set, is the next test): each turn is counted once, under its own reason, and the reasons come in a
        // fixed order. The turn that went to another model lies within the boundary, so the destination is its only reason.
        var otherModel = Library.endpoint
        otherModel.model = "another-local-model"
        let elsewhere = ConversationTurnSnapshot(turnID: UUID(), question: "Asked of another model", answer: "Early.", maxEvidenceOrdinal: 10,
                                                 editionID: Self.mm.snapshot.editionID, sharedScopes: [.sourceText], destination: otherModel)
        let beyond = ConversationTurnSnapshot(turnID: UUID(), question: "Who is Raffles?", answer: "Later.", maxEvidenceOrdinal: Self.boundary + 2_000,
                                              editionID: Self.mm.snapshot.editionID, sharedScopes: [.sourceText], destination: Library.endpoint)
        let otherEdition = ConversationTurnSnapshot(turnID: UUID(), question: "Asked in another edition", answer: "Early.", maxEvidenceOrdinal: 10,
                                                    editionID: UUID(), sharedScopes: [.sourceText], destination: Library.endpoint)
        let mixed = try Library.build(ContextRequest(question: "What is Bulstrode like?", scope: .workSearch, excludeLaterPassages: true,
                                                     confirmedPosition: position, history: [p3, beyond, elsewhere, otherEdition, p3b]), work: Self.mm)
        #expect(mixed.history.includedTurns.isEmpty)
        #expect(mixed.history.excludedTurnCount == 5)
        #expect(mixed.history.exclusionReason == ["1 earlier question in this conversation went to a different provider or model, so it and its answer weren't sent to 127.0.0.1 · local · local-model.",
                                                  Self.beyondReason,
                                                  "Earlier answers in this conversation used passages from another edition, which Sylvia can't compare with your position, so they weren't sent.",
                                                  Self.unknownPlaceReason].joined(separator: " "))
    }

    /// R6-01, same class: with "Do not include later passages" on and no position set, there is no position for an earlier
    /// turn to be "beyond"; the reason says what is true.
    @Test func earlierTurnsWithoutAPositionToCompareSayWhy() throws {
        let used = ConversationTurnSnapshot(turnID: UUID(), question: "Who is Lydgate?", answer: "A doctor.", maxEvidenceOrdinal: 10,
                                            editionID: Self.mm.snapshot.editionID, sharedScopes: [.sourceText], destination: Library.endpoint)
        let unknown = ConversationTurnSnapshot(turnID: UUID(), question: "My note?", answer: "It says…", maxEvidenceOrdinal: nil,
                                               editionID: nil, sharedScopes: [.savedThoughts], destination: Library.endpoint)
        let none = ConversationTurnSnapshot(turnID: UUID(), question: "Hello?", answer: "Hello.", maxEvidenceOrdinal: -1,
                                            editionID: nil, sharedScopes: [], destination: Library.endpoint)
        let pack = try Library.build(ContextRequest(question: "What happens to Dorothea?", scope: .workSearch, excludeLaterPassages: true,
                                                    history: [used, unknown, none]), work: Self.mm)
        #expect(pack.spoilerBoundary.basis == .none)
        #expect(pack.history.includedTurns.map(\.turnID) == [none.turnID], "a turn that used no evidence is kept")
        #expect(pack.history.excludedTurnCount == 2)
        #expect(pack.history.exclusionReason == "\"Do not include later passages\" is on, but no reading position is set, so earlier answers in this conversation that used passages or saved thoughts weren't sent.")
    }

    /// R6-04 (plan 12, 13.3): a confirmed position counts one edition's paragraphs. Under "Do not include later passages",
    /// a position from another edition of the work is refused in every scope rather than applied to this edition's
    /// paragraphs (where it would draw the boundary in the wrong place while the pack claimed a user-confirmed boundary).
    /// The same ordinal in this edition is applied; without the restriction the position is not used at all.
    @Test(arguments: [ContextScope.selectedPassage, .passageAndNearby, .workSearch, .selectedThoughts])
    func confirmedPositionFromAnotherEditionIsRefused(scope: ContextScope) throws {
        let early = Self.mm.work.paragraphs.first { $0.resourceHref == "text/chapter-5.xhtml" && $0.wordCount > 40 }!
        let selection = TextSelection(paragraphOrdinal: early.ordinal, exactText: String(early.text.prefix(60)))
        let thoughts = [SavedThought(captureID: UUID(), kind: .quote, text: "An early quote", workID: Self.mm.snapshot.workID,
                                     editionID: Self.mm.snapshot.editionID, locationLabel: "I", ordinal: 10)]
        func request(_ position: ReadingPosition, restricted: Bool) -> ContextRequest {
            ContextRequest(question: "What does Dorothea want?", scope: scope, selection: scope == .selectedThoughts ? nil : selection,
                           thoughts: scope == .selectedThoughts ? thoughts : [], excludeLaterPassages: restricted, confirmedPosition: position)
        }
        let foreign = ReadingPosition(editionID: UUID(), paragraphOrdinal: Self.boundary)
        #expect(throws: ContextBuildError.confirmedPositionInAnotherEdition) { try Library.build(request(foreign, restricted: true), work: Self.mm) }
        #expect(ContextBuildError.confirmedPositionInAnotherEdition.userMessage == "Your confirmed position is in another edition, which Sylvia can't compare with this one, and \"Do not include later passages\" is on. Confirm your position in this edition, or turn that setting off, to ask.")

        let mine = try Library.build(request(ReadingPosition(editionID: Self.mm.snapshot.editionID, paragraphOrdinal: Self.boundary), restricted: true), work: Self.mm)
        #expect(mine.spoilerBoundary == SpoilerBoundary(enabled: true, maxOrdinal: Self.boundary, basis: .userConfirmedPosition,
                                                        excludedEvidenceCount: mine.spoilerBoundary.excludedEvidenceCount))
        #expect(mine.spoilerBoundaryViolations.isEmpty)

        let open = try Library.build(request(foreign, restricted: false), work: Self.mm)
        #expect(open.spoilerBoundary == .disabled)
    }

    @Test func noEnforceablePositionMeansNoRetrievalRatherThanAFalsePromise() throws {
        let pack = try Library.build(ContextRequest(question: "What happens to Dorothea?", scope: .workSearch, excludeLaterPassages: true), work: Self.mm)
        #expect(pack.spoilerBoundary.basis == .none)
        #expect(pack.evidence.isEmpty)
        // Plan 13.3 "state the limitation": the app says it, not the model.
        #expect(pack.coverage == .noPassages)
        #expect(pack.coverageLabel == "No passages sent")
        #expect(pack.limitations.map(\.code) == [.noEnforceablePosition])
        #expect(pack.limitations[0].disclosure.contains("no reading position is set"))
        let prompt = PromptTemplate.request(for: pack, maxOutputTokens: 100).messages.last!.text
        #expect(prompt.contains("<limitation>"))

        let thoughts = [SavedThought(captureID: UUID(), kind: .note, text: "My note", workID: Self.mm.snapshot.workID, editionID: Self.mm.snapshot.editionID, locationLabel: "I", ordinal: 10)]
        let thoughtPack = try Library.build(ContextRequest(question: "q", scope: .selectedThoughts, thoughts: thoughts, excludeLaterPassages: true), work: Self.mm)
        #expect(thoughtPack.evidence.isEmpty)
        #expect(thoughtPack.limitations.map(\.code) == [.noEnforceablePosition])
    }

    /// Plan 20.3 gate "no later text enters a restricted ContextPack": the selection is evidence too. A selection after
    /// the confirmed position is refused in every scope that takes one, instead of being sent under a boundary label
    /// that says otherwise.
    @Test(arguments: [ContextScope.selectedPassage, .passageAndNearby, .workSearch])
    func selectionAfterTheConfirmedPositionIsRefused(scope: ContextScope) throws {
        let later = Self.mm.work.paragraphs.first { $0.ordinal > Self.boundary + 1_500 && $0.wordCount > 40 }!
        let selection = TextSelection(paragraphOrdinal: later.ordinal, exactText: String(later.text.prefix(60)))
        let request = ContextRequest(question: "What does this mean for Dorothea?", scope: scope, selection: selection,
                                     excludeLaterPassages: true, confirmedPosition: ReadingPosition(editionID: Self.mm.snapshot.editionID, paragraphOrdinal: Self.boundary))
        #expect(throws: ContextBuildError.selectionAfterBoundary(selectionOrdinal: later.ordinal, boundaryOrdinal: Self.boundary)) {
            try Library.build(request, work: Self.mm)
        }
        #expect(ContextBuildError.selectionAfterBoundary(selectionOrdinal: 1, boundaryOrdinal: 0).userMessage.contains("Move your position"))

        // Without the restriction the same selection is fine; at or before the position it is fine and stays inside it.
        let open = try Library.build(ContextRequest(question: "What does this mean for Dorothea?", scope: scope, selection: selection), work: Self.mm)
        #expect(open.evidence.contains { $0.role == .selection })
        for paragraph in [Self.mm.work.paragraphs.last { $0.ordinal <= Self.boundary && $0.wordCount > 40 }!,
                          Self.mm.work.paragraphs.first { $0.resourceHref == "text/chapter-5.xhtml" && $0.wordCount > 40 }!] {
            let inside = TextSelection(paragraphOrdinal: paragraph.ordinal, exactText: String(paragraph.text.prefix(60)))
            let pack = try Library.build(ContextRequest(question: "What does this mean for Dorothea?", scope: scope, selection: inside,
                                                        excludeLaterPassages: true, confirmedPosition: ReadingPosition(editionID: Self.mm.snapshot.editionID, paragraphOrdinal: Self.boundary)), work: Self.mm)
            #expect(pack.spoilerBoundary.maxOrdinal == Self.boundary)
            #expect(pack.spoilerBoundaryViolations.isEmpty)
            #expect(pack.evidence.allSatisfy { ($0.position?.lastOrdinal ?? Int.min) <= Self.boundary })
        }
    }

    /// The bounded adjacent chunk next to the top hit must stop at the boundary even when the boundary falls inside a
    /// chapter (where the same-chapter rule does not block it). Twenty mid-chapter boundaries, each placed at the end of
    /// a chunk whose next chunk in the same chapter starts with a later paragraph; the question is made from that
    /// chunk's rarest words, so it is usually the top hit and the later chunk is the adjacent candidate.
    @Test func adjacentChunkNeverCrossesAMidChapterBoundary() throws {
        let chunks = Self.mm.chunks
        let pairs = chunks.indices.dropLast().filter { i in
            chunks[i + 1].resourceHref == chunks[i].resourceHref && chunks[i + 1].firstOrdinal > chunks[i].lastOrdinal && chunks[i].wordCount >= 300
        }
        let picked = stride(from: 0, to: pairs.count, by: max(1, pairs.count / 20)).prefix(20).map { pairs[$0] }
        #expect(picked.count == 20)
        var adjacentBlocked = 0
        for i in picked {
            let chunk = chunks[i], boundary = chunk.lastOrdinal
            let words = Set(chunk.text.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 8 })
            let question = words.sorted { ($0.count, $0) > ($1.count, $1) }.prefix(10).joined(separator: " ")
            let pack = try Library.build(ContextRequest(question: question, scope: .workSearch, excludeLaterPassages: true,
                                                        confirmedPosition: ReadingPosition(editionID: Self.mm.snapshot.editionID, paragraphOrdinal: boundary)), work: Self.mm)
            #expect(pack.spoilerBoundaryViolations.isEmpty, "boundary \(boundary)")
            #expect(pack.evidence.allSatisfy { ($0.position?.lastOrdinal ?? Int.min) <= boundary }, "boundary \(boundary)")
            #expect(!pack.evidence.contains { $0.text == chunks[i + 1].text }, "the later chunk in the same chapter is never sent")
            let top = pack.evidence.first { $0.retrieval?.rank == 1 }
            if top?.text == chunk.text { adjacentBlocked += 1 }
        }
        #expect(adjacentBlocked >= 10, "the boundary chunk was the top hit in \(adjacentBlocked) of 20 cases")
    }
}
