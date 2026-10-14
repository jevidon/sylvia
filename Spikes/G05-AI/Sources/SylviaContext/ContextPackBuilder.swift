import Foundation
import SylviaAI

/// Token estimation. No model tokenizer is bundled in the spike, so every count is a labelled estimate
/// (plan 13.2: "estimates must be labelled").
public protocol TokenEstimator: Sendable {
    var info: TokenEstimatorInfo { get }
    func estimate(_ text: String) -> Int
}

/// One token per 3 UTF-8 bytes, rounded up. English prose averages about 4 bytes per token with current
/// tokenizers, so this over-counts on purpose: a conservative estimate leaves room rather than overflowing.
public struct HeuristicTokenEstimator: TokenEstimator {
    public init() {}
    public var info: TokenEstimatorInfo { TokenEstimatorInfo(kind: .heuristic, name: "utf8-bytes-div-3") }
    public func estimate(_ text: String) -> Int { (text.utf8.count + 2) / 3 }
}

/// A saved thought (quote or note) the user picked for "Selected thoughts".
public struct SavedThought: Sendable, Equatable {
    public enum Kind: Sendable { case quote, note, transcript }
    public var captureID: UUID
    public var kind: Kind
    public var text: String
    public var workID: UUID?
    /// The edition the thought was captured in. Paragraph ordinals are positions in one edition's extracted text, so
    /// `ordinal` is meaningful only in this edition (plan 7.x, I-05; plan 13.3: no precise boundary across editions
    /// without an alignment).
    public var editionID: UUID?
    public var locationLabel: String
    /// Paragraph ordinal in the extracted text of `editionID`, when known (for spoiler filtering).
    public var ordinal: Int?

    public init(captureID: UUID, kind: Kind, text: String, workID: UUID?, editionID: UUID?, locationLabel: String, ordinal: Int?) {
        self.captureID = captureID
        self.kind = kind
        self.text = text
        self.workID = workID
        self.editionID = editionID
        self.locationLabel = locationLabel
        self.ordinal = ordinal
    }
}

public struct TextSelection: Sendable, Equatable {
    public var paragraphOrdinal: Int
    public var exactText: String

    public init(paragraphOrdinal: Int, exactText: String) {
        self.paragraphOrdinal = paragraphOrdinal
        self.exactText = exactText
    }
}

/// A position the user confirmed, in the edition whose extracted paragraphs its ordinal counts. Reading positions are
/// edition-specific (plan 12): the same ordinal in another edition is a different paragraph, so the edition travels with
/// the ordinal and a position from another edition is never applied to this one (plan 13.3).
public struct ReadingPosition: Sendable, Equatable {
    public var editionID: UUID
    public var paragraphOrdinal: Int

    public init(editionID: UUID, paragraphOrdinal: Int) {
        self.editionID = editionID
        self.paragraphOrdinal = paragraphOrdinal
    }
}

public struct ContextRequest: Sendable {
    public var question: String
    public var conversationID: UUID
    public var scope: ContextScope
    public var selection: TextSelection?
    public var thoughts: [SavedThought]
    /// "Do not include later passages" (plan 13.3).
    public var excludeLaterPassages: Bool
    /// A position the user confirmed (for example their reading position), with the edition it counts in. Without it the
    /// selection is the boundary. Under "Do not include later passages" a position in another edition than the pack's is
    /// refused (`confirmedPositionInAnotherEdition`): it can't be compared with this edition's paragraphs.
    public var confirmedPosition: ReadingPosition?
    public var history: [ConversationTurnSnapshot]
    /// Set when the user asks from a moment in a recording (for example "Meditations, Book One, 2:30"). Unless the
    /// pack carries a transcript or a confirmed companion passage for it, the pack states that the audio passage is
    /// unavailable (plan 10.4). Sylvia never infers ebook text from a timestamp.
    public var audioMoment: String?

    public init(question: String, conversationID: UUID = UUID(), scope: ContextScope, selection: TextSelection? = nil,
                thoughts: [SavedThought] = [], excludeLaterPassages: Bool = false, confirmedPosition: ReadingPosition? = nil,
                history: [ConversationTurnSnapshot] = [], audioMoment: String? = nil) {
        self.question = question
        self.conversationID = conversationID
        self.scope = scope
        self.selection = selection
        self.thoughts = thoughts
        self.excludeLaterPassages = excludeLaterPassages
        self.confirmedPosition = confirmedPosition
        self.history = history
        self.audioMoment = audioMoment
    }
}

public struct BuilderSettings: Sendable, Equatable {
    public var topK = 5
    public var adjacentChunks = 1
    public var nearbyWordsEachSide = 250
    public var maxThoughts = 8
    /// Used when the model's context limit is unknown (plan 13.2: conservative, configurable).
    public var defaultContextLimitTokens = 8_192
    public var defaultOutputReserveTokens = 1_024
    public var safetyMarginFraction = 0.10
    public var minimumSafetyMarginTokens = 256
    /// Per-evidence wrapper cost (the <evidence> element and attributes).
    public var evidenceOverheadTokens = 30

    public init() {}
}

public enum ContextBuildError: Error, Equatable {
    case selectionRequired
    case thoughtsRequired
    case selectionNotFound
    case selectionExceedsBudget(requiredTokens: Int, availableTokens: Int)
    case wholeWorkDoesNotFit(requiredTokens: Int, availableTokens: Int)
    /// Whole-book inclusion and "Do not include later passages" contradict each other: a pack holding only the text
    /// up to a position is not the whole book, and must not be labelled so.
    case wholeWorkWithSpoilerBoundary
    case tooManyThoughts(limit: Int)
    case noRoomForEvidence
    case questionEmpty
    /// "Do not include later passages" is on and the selection lies after the user's confirmed position.
    case selectionAfterBoundary(selectionOrdinal: Int, boundaryOrdinal: Int)
    /// "Do not include later passages" is on and the user's confirmed position counts the paragraphs of another edition,
    /// which can't be compared with this one without an alignment (plan 12, 13.3).
    case confirmedPositionInAnotherEdition
    /// Internal check failed: the assembled pack would hold text after its own spoiler boundary. Never expected.
    case spoilerBoundaryViolated([String])
    /// Internal check failed: the assembled pack would resend an earlier turn to a destination it did not go to, or with
    /// a citation marker from its own pack. Never expected.
    case historyRuleViolated([String])

    public var userMessage: String {
        switch self {
        case .selectionRequired: "Select a passage first."
        case .thoughtsRequired: "Choose at least one saved thought."
        case .selectionNotFound: "The selected text couldn't be found in this edition's extracted text."
        case .selectionExceedsBudget(let required, let available):
            "The selection is too long for this model (about \(required) tokens; about \(available) available, estimated). Select a shorter passage."
        case .wholeWorkDoesNotFit(let required, let available):
            "The whole book doesn't fit this model (about \(required) tokens; about \(available) available, estimated). Use \"Relevant passages from this work\" instead."
        case .wholeWorkWithSpoilerBoundary:
            "\"Whole book\" can't be combined with \"Do not include later passages\". Use \"Relevant passages from this work\" instead."
        case .tooManyThoughts(let limit): "Choose up to \(limit) thoughts."
        case .noRoomForEvidence: "This model's context is too small for the question and any passage. Shorten the question or choose a model with a larger context."
        case .questionEmpty: "Enter a question."
        case .selectionAfterBoundary:
            "Your selection is after your confirmed position, and \"Do not include later passages\" is on. Move your position to the selection, or turn that setting off, to ask about it."
        case .confirmedPositionInAnotherEdition:
            "Your confirmed position is in another edition, which Sylvia can't compare with this one, and \"Do not include later passages\" is on. Confirm your position in this edition, or turn that setting off, to ask."
        case .spoilerBoundaryViolated:
            "Sylvia couldn't build this request without including passages after your position, so nothing was sent."
        case .historyRuleViolated:
            "Sylvia couldn't build this request from this conversation's earlier answers, so nothing was sent. Start a new conversation to ask it."
        }
    }
}

/// Assembles a ContextPack for one of the four scopes (plan 13.1-13.3). Never deletes evidence silently: what
/// did not fit is counted and disclosed; a selection that does not fit is an error the user resolves.
public struct ContextPackBuilder: Sendable {
    let index: PassageIndex
    let estimator: any TokenEstimator
    let settings: BuilderSettings

    public init(index: PassageIndex, estimator: any TokenEstimator = HeuristicTokenEstimator(), settings: BuilderSettings = BuilderSettings()) {
        self.index = index
        self.estimator = estimator
        self.settings = settings
    }

    struct Candidate {
        var role: EvidenceRole
        var origin: EvidenceOrigin
        var quality: SourceQuality
        var text: String
        var label: String
        var position: EvidencePosition?
        var retrieval: RetrievalScore?
        var captureID: UUID?
        var required: Bool
        /// The work a saved thought belongs to (source text always belongs to the pack's work).
        var thoughtWorkID: UUID? = nil
    }

    public func build(_ request: ContextRequest, work: WorkSnapshot, config: ProviderConfig, endpoint: EndpointIdentity,
                      createdAt: Date) throws -> ContextPack {
        let question = request.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { throw ContextBuildError.questionEmpty }

        // Spoiler boundary (plan 13.3): enforced by filtering before anything is assembled.
        var boundary = SpoilerBoundary.disabled
        if request.excludeLaterPassages {
            if let confirmed = request.confirmedPosition {
                // A position counts one edition's paragraphs; applied to another edition it would draw the boundary on
                // the wrong paragraphs, and the pack would claim a user-confirmed boundary it doesn't have.
                guard confirmed.editionID == work.editionID else { throw ContextBuildError.confirmedPositionInAnotherEdition }
                boundary = SpoilerBoundary(enabled: true, maxOrdinal: confirmed.paragraphOrdinal, basis: .userConfirmedPosition)
            } else if let selection = request.selection {
                boundary = SpoilerBoundary(enabled: true, maxOrdinal: selection.paragraphOrdinal, basis: .selectionPosition)
            } else {
                // No enforceable position: refuse to pretend. Nothing from the work is retrieved.
                boundary = SpoilerBoundary(enabled: true, maxOrdinal: -1, basis: .none)
            }
        }
        let maxOrdinal = boundary.enabled ? boundary.maxOrdinal : nil
        // The selection itself is evidence: a selection after the confirmed position would put later text into a
        // restricted pack. Refuse rather than move the boundary silently; the user moves the position or turns the
        // setting off (plan 13.3, 20.3 "no later text enters a restricted ContextPack").
        if let maxOrdinal, let selection = request.selection, selection.paragraphOrdinal > maxOrdinal {
            throw ContextBuildError.selectionAfterBoundary(selectionOrdinal: selection.paragraphOrdinal, boundaryOrdinal: maxOrdinal)
        }

        // Budget (plan 13.2).
        let contextLimit = config.contextLimitTokens ?? settings.defaultContextLimitTokens
        let limitSource: BudgetAccounting.LimitSource = config.contextLimitTokens == nil ? .defaultUnknownModel : .configured
        let outputReserve = config.maxOutputTokens ?? settings.defaultOutputReserveTokens
        let systemTokens = estimator.estimate(PromptTemplate.systemText)
        let questionTokens = estimator.estimate(question) + 20
        let margin = max(settings.minimumSafetyMarginTokens, Int(Double(contextLimit) * settings.safetyMarginFraction))

        // History. A turn is resent only to the destination it was sent to (origin, classification and model): its
        // answer can repeat what it shared, for example the user's notes, and that destination has already received it
        // (plan 14.2, I-07). In a restricted pack, only turns whose evidence is known to lie within the boundary, counted
        // in this edition's paragraphs (a turn that used another edition's text can't be compared with it). Each excluded
        // turn is counted under the reason that is true for it: another destination, no position to compare with, another
        // edition, an unknown place, or beyond the position (plan I-06, 22.3: the message matches the actual state). One
        // exception is known: a turn names its edition but not its work, so a turn about another work counts as another
        // edition (safe, but the wrong reason; plan 7.2 ties a conversation to one work, see ConversationTurnSnapshot). An
        // included answer's citation markers pointed into its own pack, whose evidence is not resent, so they are
        // replaced (plan 13.4, A.2).
        var included: [ConversationTurnSnapshot] = []
        var otherDestination = 0
        var beyondBoundary = 0
        var otherEdition = 0
        // Turns whose evidence has no known place: a note or thought with no position in the work, or a thought from
        // another edition (`ConversationTurnSnapshot.init(question:answer:pack:)` gives nil for these).
        var unknownPlace = 0
        // Turns that used any evidence while the boundary has no position to compare with (basis none).
        var noPosition = 0
        for turn in request.history {
            if !turn.destination.isSameDestination(as: endpoint) {
                otherDestination += 1
                continue
            }
            if boundary.enabled, boundary.basis == .none, turn.maxEvidenceOrdinal != -1 {
                noPosition += 1
                continue
            }
            if boundary.enabled, turn.maxEvidenceOrdinal != nil, !turn.isPlaced(inEdition: work.editionID) {
                otherEdition += 1
                continue
            }
            if boundary.enabled, turn.maxEvidenceOrdinal == nil {
                unknownPlace += 1
                continue
            }
            if boundary.enabled, let turnMax = turn.maxEvidenceOrdinal, turnMax > (maxOrdinal ?? Int.max) {
                beyondBoundary += 1
                continue
            }
            var resent = turn
            resent.answer = PromptTemplate.neutralizeCitationMarkers(turn.answer)
            included.append(resent)
        }
        var exclusionReasons: [String] = []
        if otherDestination > 0 {
            exclusionReasons.append(otherDestination == 1
                ? "1 earlier question in this conversation went to a different provider or model, so it and its answer weren't sent to \(endpoint.disclosureRow)."
                : "\(otherDestination) earlier questions in this conversation went to a different provider or model, so they and their answers weren't sent to \(endpoint.disclosureRow).")
        }
        if beyondBoundary > 0 {
            exclusionReasons.append("Earlier answers in this conversation used passages beyond your position, so they weren't sent. Start a new conversation with \"Do not include later passages\" to keep them out entirely.")
        }
        if otherEdition > 0 {
            exclusionReasons.append("Earlier answers in this conversation used passages from another edition, which Sylvia can't compare with your position, so they weren't sent.")
        }
        if unknownPlace > 0 {
            exclusionReasons.append("Earlier answers in this conversation used material whose place in this edition isn't known, so they weren't sent.")
        }
        if noPosition > 0 {
            exclusionReasons.append("\"Do not include later passages\" is on, but no reading position is set, so earlier answers in this conversation that used passages or saved thoughts weren't sent.")
        }
        var excludedTurns = otherDestination + beyondBoundary + otherEdition + unknownPlace + noPosition
        var historyTokens = included.map { estimator.estimate($0.question) + estimator.estimate($0.answer) + 10 }.reduce(0, +)
        var evidenceBudget = contextLimit - systemTokens - questionTokens - historyTokens - outputReserve - margin
        // Drop the oldest included turns if history alone crowds out evidence; disclose it.
        var droppedForBudget = 0
        while evidenceBudget < contextLimit / 4, !included.isEmpty {
            let removed = included.removeFirst()
            let cost = estimator.estimate(removed.question) + estimator.estimate(removed.answer) + 10
            historyTokens -= cost
            evidenceBudget += cost
            droppedForBudget += 1
        }
        if droppedForBudget > 0 {
            excludedTurns += droppedForBudget
            exclusionReasons.append("The oldest \(droppedForBudget) turn\(droppedForBudget == 1 ? "" : "s") of this conversation didn't fit and weren't sent.")
        }
        let exclusionReason = exclusionReasons.isEmpty ? nil : exclusionReasons.joined(separator: " ")
        guard evidenceBudget > settings.evidenceOverheadTokens else { throw ContextBuildError.noRoomForEvidence }

        // Candidates for the chosen scope, in priority order.
        var candidates: [Candidate] = []
        var retrievalSettings: RetrievalSettings?
        var coverage = ContextCoverage.excerptOnly
        var excludedByBoundary = 0
        // Thoughts on this work left out of a restricted pack because their place isn't in this edition's text.
        var unplacedThoughts = 0
        var noSearchableTerms = false
        var retrievedHits = 0

        func selectionCandidate() throws -> (Candidate, ExtractedParagraph) {
            guard let selection = request.selection else { throw ContextBuildError.selectionRequired }
            guard let paragraph = try index.paragraph(workID: work.workID, ordinal: selection.paragraphOrdinal),
                  !selection.exactText.isEmpty, paragraph.text.contains(selection.exactText) else { throw ContextBuildError.selectionNotFound }
            return (Candidate(role: .selection, origin: .sourceText, quality: .extractedText, text: selection.exactText, label: paragraph.locationLabel,
                              position: EvidencePosition(resourceHref: paragraph.resourceHref, firstOrdinal: paragraph.ordinal, lastOrdinal: paragraph.ordinal),
                              retrieval: nil, captureID: nil, required: true), paragraph)
        }

        switch request.scope {
        case .selectedPassage:
            candidates.append(try selectionCandidate().0)
        case .passageAndNearby:
            let (selection, paragraph) = try selectionCandidate()
            candidates.append(selection)
            if selection.text != paragraph.text {
                candidates.append(Candidate(role: .nearby, origin: .sourceText, quality: .extractedText, text: paragraph.text, label: paragraph.locationLabel,
                                            position: selection.position, retrieval: nil, captureID: nil, required: false))
            }
            candidates += try nearby(work: work.workID, around: paragraph, maxOrdinal: maxOrdinal)
        case .workSearch:
            coverage = .retrievedPassages
            if request.selection != nil { candidates.append(try selectionCandidate().0) }
            let result = try index.search(workID: work.workID, question: question, maxOrdinal: maxOrdinal, limit: settings.topK)
            excludedByBoundary = result.excludedByBoundary
            noSearchableTerms = result.terms.isEmpty
            retrievedHits = result.hits.count
            var used = Set<Int>()
            for hit in result.hits where used.insert(hit.chunk.chunkIndex).inserted {
                candidates.append(candidate(for: hit.chunk, role: .retrieved, retrieval: RetrievalScore(rank: hit.rank, score: hit.score)))
            }
            // Bounded adjacent context for the top hit only, never past the boundary.
            if let top = result.hits.first, settings.adjacentChunks > 0 {
                for offset in [-1, 1] {
                    let index = top.chunk.chunkIndex + offset
                    guard !used.contains(index), let adjacent = try self.index.chunk(workID: work.workID, index: index),
                          adjacent.resourceHref == top.chunk.resourceHref,
                          maxOrdinal.map({ adjacent.lastOrdinal <= $0 }) ?? true else { continue }
                    used.insert(index)
                    candidates.append(candidate(for: adjacent, role: .adjacent, retrieval: nil))
                }
            }
            retrievalSettings = RetrievalSettings(strategy: "fts5_bm25", queryTerms: result.terms, topK: settings.topK,
                                                  adjacentChunks: settings.adjacentChunks, chunkWordsMin: 300, chunkWordsMax: 600,
                                                  candidatesConsidered: result.candidatesConsidered)
        case .selectedThoughts:
            coverage = .savedThoughts
            guard !request.thoughts.isEmpty else { throw ContextBuildError.thoughtsRequired }
            guard request.thoughts.count <= settings.maxThoughts else { throw ContextBuildError.tooManyThoughts(limit: settings.maxThoughts) }
            for thought in request.thoughts {
                let inThisWork = thought.workID == work.workID
                // A thought on this work has a place in this pack only when its ordinal counts this edition's extracted
                // paragraphs: an ordinal from another edition counts different paragraphs (plan 13.3: no precise boundary
                // across editions without an alignment). A known place is kept, so the stored pack shows the thought lies
                // within the boundary (plan 11.2) and the final self-check below, the coordinator and the contract check
                // can verify it. In a restricted pack, a thought on this work with no known place in this edition
                // (captured in another edition, no ordinal, or an ordinal not in this edition's text) can't be shown to
                // lie within the boundary, so it is left out; an unrestricted pack keeps it without a position.
                var paragraph: ExtractedParagraph?
                if inThisWork, thought.editionID == work.editionID, let ordinal = thought.ordinal {
                    paragraph = try index.paragraph(workID: work.workID, ordinal: ordinal)
                }
                var position: EvidencePosition?
                if let paragraph {
                    if boundary.enabled, paragraph.ordinal > (maxOrdinal ?? Int.max) {
                        excludedByBoundary += 1
                        continue
                    }
                    position = EvidencePosition(resourceHref: paragraph.resourceHref, firstOrdinal: paragraph.ordinal, lastOrdinal: paragraph.ordinal)
                } else if inThisWork, boundary.enabled {
                    excludedByBoundary += 1
                    unplacedThoughts += 1
                    continue
                }
                let (origin, quality): (EvidenceOrigin, SourceQuality) = switch thought.kind {
                case .quote: (.savedQuote, .exactCapture)
                case .note: (.userNote, .userEntered)
                case .transcript: (.transcript, .machineTranscript)
                }
                candidates.append(Candidate(role: .thought, origin: origin, quality: quality, text: thought.text, label: thought.locationLabel,
                                            position: position, retrieval: nil, captureID: thought.captureID, required: false,
                                            thoughtWorkID: thought.workID))
            }
        case .wholeWork:
            guard !boundary.enabled else { throw ContextBuildError.wholeWorkWithSpoilerBoundary }
            coverage = .wholeWork
            let chunks = try index.allChunks(workID: work.workID, maxOrdinal: nil)
            let required = chunks.map { estimator.estimate($0.text) + settings.evidenceOverheadTokens }.reduce(0, +)
            guard required <= evidenceBudget, chunks.count <= ContextPack.maxEvidenceItems else {
                throw ContextBuildError.wholeWorkDoesNotFit(requiredTokens: required, availableTokens: evidenceBudget)
            }
            candidates += chunks.map { candidate(for: $0, role: .wholeWork, retrieval: nil) }
        }

        // Fit candidates into the budget in priority order; required ones must fit.
        var evidence: [EvidenceItem] = []
        var used = 0
        var omitted = 0
        for candidate in candidates {
            let cost = estimator.estimate(candidate.text) + settings.evidenceOverheadTokens
            if used + cost > evidenceBudget {
                if candidate.required {
                    throw ContextBuildError.selectionExceedsBudget(requiredTokens: cost, availableTokens: evidenceBudget - used)
                }
                omitted += 1
                continue
            }
            used += cost
            // A position is in this edition's extracted paragraphs, so an item with one names the edition too.
            evidence.append(EvidenceItem(citationID: "c\(evidence.count + 1)", role: candidate.role, origin: candidate.origin,
                                         sourceQuality: candidate.quality, text: candidate.text, locationLabel: candidate.label,
                                         captureID: candidate.captureID, workID: candidate.origin == .sourceText ? work.workID : candidate.thoughtWorkID,
                                         editionID: candidate.origin == .sourceText || candidate.position != nil ? work.editionID : nil,
                                         position: candidate.position, retrieval: candidate.retrieval, estimatedTokens: cost))
        }
        boundary.excludedEvidenceCount = excludedByBoundary

        var truncation = TruncationInfo()
        if omitted > 0 {
            truncation = TruncationInfo(truncated: true, omittedEvidenceCount: omitted, reason: "budget",
                                        disclosure: "\(omitted) passage\(omitted == 1 ? "" : "s") didn't fit this model's context and weren't sent (estimated).")
        }

        // Limitations the app states itself (plan 13.3, 10.4), never left to the model.
        var limitations: [ContextLimitation] = []
        // Retrieved hits all left out by the budget are disclosed by `truncation`, not here.
        if request.scope == .workSearch, retrievedHits == 0 {
            if boundary.enabled && boundary.basis == .none {
                limitations.append(ContextLimitation(code: .noEnforceablePosition,
                    disclosure: "\"Do not include later passages\" is on, but no reading position is set, so no passages from \(work.title) were sent. Set your position to include passages up to it."))
            } else if noSearchableTerms {
                limitations.append(ContextLimitation(code: .noSearchableTerms,
                    disclosure: "Your question had no searchable words, so no passages from \(work.title) were sent."))
            } else if excludedByBoundary > 0 {
                limitations.append(ContextLimitation(code: .allExcludedByBoundary,
                    disclosure: "The passages that matched your question are all after your position, so none were sent."))
            } else {
                limitations.append(ContextLimitation(code: .noMatchingPassages,
                    disclosure: "No passage in \(work.title) matched your question, so none were sent."))
            }
        }
        if request.scope == .selectedThoughts, evidence.isEmpty, excludedByBoundary > 0, omitted == 0 {
            limitations.append(boundary.basis == .none
                ? ContextLimitation(code: .noEnforceablePosition,
                                    disclosure: "\"Do not include later passages\" is on, but no reading position is set, so your thoughts on \(work.title) weren't sent. Set your position to include thoughts up to it.")
                : ContextLimitation(code: .allExcludedByBoundary,
                                    disclosure: unplacedThoughts > 0
                                        ? "None of the thoughts you selected can be shown to come before your position, so none were sent."
                                        : "The thoughts you selected are all after your position, so none were sent."))
        }
        if let moment = request.audioMoment, !evidence.contains(where: { $0.origin == .transcript || $0.origin == .companionPassage }) {
            limitations.append(ContextLimitation(code: .audioPassageUnavailable,
                disclosure: "The audio at \(moment) is unavailable to the model: it has no transcript and no confirmed matching passage in an ebook, so no words from it were sent."))
        }
        if evidence.isEmpty { coverage = .noPassages }

        let budget = BudgetAccounting(contextLimitTokens: contextLimit, contextLimitSource: limitSource, systemTokens: systemTokens,
                                      questionTokens: questionTokens, historyTokens: historyTokens, outputReserveTokens: outputReserve,
                                      safetyMarginTokens: margin, evidenceBudgetTokens: evidenceBudget, evidenceTokens: used,
                                      estimator: estimator.info, estimated: estimator.info.kind == .heuristic)
        let resources = try index.resourceCount(workID: work.workID)
        let created = Date(timeIntervalSince1970: (createdAt.timeIntervalSince1970 * 1000).rounded(.down) / 1000)
        let pack = ContextPack(conversationID: request.conversationID, createdAt: created, scope: request.scope, coverage: coverage,
                               question: question, work: work, evidence: evidence, spoilerBoundary: boundary,
                               history: HistoryInclusion(includedTurns: included, excludedTurnCount: excludedTurns, exclusionReason: exclusionReason),
                               budget: budget, truncation: truncation, limitations: limitations, retrieval: retrievalSettings,
                               textCoverage: TextCoverage(state: resources > 0 ? .bookTextIndexed : .textUnavailable, resourcesIndexed: resources, resourcesTotal: resources),
                               endpoint: endpoint, promptTemplateVersion: PromptTemplate.version)
        // Defence in depth: the filters above should make this impossible; a pack that breaks its own boundary, or
        // that resends a turn from another destination or with an earlier citation marker, is never returned.
        let violations = pack.spoilerBoundaryViolations
        guard violations.isEmpty else { throw ContextBuildError.spoilerBoundaryViolated(violations) }
        let historyViolations = pack.historyViolations
        guard historyViolations.isEmpty else { throw ContextBuildError.historyRuleViolated(historyViolations) }
        return pack
    }

    func candidate(for chunk: TextChunk, role: EvidenceRole, retrieval: RetrievalScore?) -> Candidate {
        Candidate(role: role, origin: .sourceText, quality: .extractedText, text: chunk.text, label: chunk.locationLabel,
                  position: EvidencePosition(resourceHref: chunk.resourceHref, firstOrdinal: chunk.firstOrdinal, lastOrdinal: chunk.lastOrdinal,
                                             pieceIndex: chunk.pieceIndex),
                  retrieval: retrieval, captureID: nil, required: false)
    }

    /// Paragraphs before and after the selection's paragraph in the same resource, up to the word allowance each
    /// side, never past the spoiler boundary. Returned as one "before" and one "after" candidate.
    func nearby(work: UUID, around paragraph: ExtractedParagraph, maxOrdinal: Int?) throws -> [Candidate] {
        var out: [Candidate] = []
        for direction in [-1, 1] {
            var collected: [ExtractedParagraph] = []
            var words = 0
            var ordinal = paragraph.ordinal + direction
            while words < settings.nearbyWordsEachSide, ordinal >= 0 {
                if let maxOrdinal, ordinal > maxOrdinal { break }
                guard let next = try index.paragraph(workID: work, ordinal: ordinal), next.resourceHref == paragraph.resourceHref else { break }
                collected.append(next)
                words += next.wordCount
                ordinal += direction
            }
            guard !collected.isEmpty else { continue }
            let ordered = direction < 0 ? collected.reversed() : collected
            out.append(Candidate(role: .nearby, origin: .sourceText, quality: .extractedText, text: ordered.map(\.text).joined(separator: "\n\n"),
                                 label: paragraph.locationLabel,
                                 position: EvidencePosition(resourceHref: paragraph.resourceHref, firstOrdinal: ordered.first!.ordinal, lastOrdinal: ordered.last!.ordinal),
                                 retrieval: nil, captureID: nil, required: false))
        }
        return out
    }
}
