import CryptoKit
import Foundation

/// The four user-chosen scopes (plan 13.1) plus whole-work inclusion, allowed only when it truly fits.
public enum ContextScope: String, Codable, Sendable, CaseIterable {
    case selectedPassage = "selected_passage"
    case passageAndNearby = "passage_and_nearby"
    case workSearch = "work_search"
    case selectedThoughts = "selected_thoughts"
    case wholeWork = "whole_work"

    /// Scope chip labels fixed in plan 4.4.6.
    public var chipLabel: String {
        switch self {
        case .selectedPassage: "Selected passage"
        case .passageAndNearby: "Passage and nearby text"
        case .workSearch: "Relevant passages from this work"
        case .selectedThoughts: "Selected thoughts"
        case .wholeWork: "Whole book"
        }
    }
}

public enum ContextCoverage: String, Codable, Sendable {
    case excerptOnly = "excerpt_only"
    case retrievedPassages = "retrieved_passages"
    case savedThoughts = "saved_thoughts"
    case wholeWork = "whole_work"
    /// Nothing from the work or the user's thoughts was sent; `limitations` (or `truncation`) says why.
    case noPassages = "no_passages"

    /// Coverage wording; after a work search the UI says "Relevant passages retrieved" (plan 13.1).
    public var label: String {
        switch self {
        case .excerptOnly: "Excerpt only"
        case .retrievedPassages: "Relevant passages retrieved"
        case .savedThoughts: "Selected thoughts only"
        case .wholeWork: "Whole book included"
        case .noPassages: "No passages sent"
        }
    }
}

/// A limitation of the pack that the app states itself, deterministically, rather than leaving it to the model
/// (plan 13.3 "state the limitation", 10.4 "say that the current audio passage is unavailable"). The disclosure is
/// shown with the request and the answer, and is also given to the model inside the prompt.
public struct ContextLimitation: Codable, Sendable, Equatable {
    public enum Code: String, Codable, Sendable, CaseIterable {
        /// "Do not include later passages" is on but no position is set, so nothing was retrieved from the work.
        case noEnforceablePosition = "no_enforceable_position"
        /// The question had no searchable words.
        case noSearchableTerms = "no_searchable_terms"
        /// The search found no passage for the question (within the boundary, if one applies).
        case noMatchingPassages = "no_matching_passages"
        /// Every candidate (retrieved passage or saved thought) lay after the reader's position.
        case allExcludedByBoundary = "all_excluded_by_boundary"
        /// The question is about a moment in a recording with no transcript and no confirmed ebook passage.
        case audioPassageUnavailable = "audio_passage_unavailable"
    }

    public var code: Code
    public var disclosure: String

    public init(code: Code, disclosure: String) {
        self.code = code
        self.disclosure = disclosure
    }
}

public enum EvidenceOrigin: String, Codable, Sendable {
    case sourceText = "source_text"
    case savedQuote = "saved_quote"
    case userNote = "user_note"
    case transcript
    case companionPassage = "companion_passage"
}

public enum SourceQuality: String, Codable, Sendable {
    /// Text Sylvia extracted from the publication.
    case extractedText = "extracted_text"
    /// Exact wording captured by the user (a saved quote).
    case exactCapture = "exact_capture"
    /// The user's own words.
    case userEntered = "user_entered"
    /// Machine transcription; potentially inaccurate.
    case machineTranscript = "machine_transcript"
}

public enum EvidenceRole: String, Codable, Sendable {
    case selection, nearby, retrieved, adjacent, thought, wholeWork = "whole_work"
}

public struct EvidencePosition: Codable, Sendable, Equatable {
    public var ordinalUnit: String = "extracted_paragraph"
    public var resourceHref: String
    public var firstOrdinal: Int
    public var lastOrdinal: Int
    public var pieceIndex: Int?

    public init(resourceHref: String, firstOrdinal: Int, lastOrdinal: Int, pieceIndex: Int? = nil) {
        self.resourceHref = resourceHref
        self.firstOrdinal = firstOrdinal
        self.lastOrdinal = lastOrdinal
        self.pieceIndex = pieceIndex
    }

    enum CodingKeys: String, CodingKey {
        case ordinalUnit = "ordinal_unit"
        case resourceHref = "resource_href"
        case firstOrdinal = "first_ordinal"
        case lastOrdinal = "last_ordinal"
        case pieceIndex = "piece_index"
    }
}

public struct RetrievalScore: Codable, Sendable, Equatable {
    public var rank: Int
    public var score: Double
    public init(rank: Int, score: Double) {
        self.rank = rank
        self.score = score
    }
}

/// One evidence snippet exactly as sent. `citationID` is local to this pack (c1, c2, …).
public struct EvidenceItem: Codable, Sendable, Equatable {
    public var citationID: String
    public var evidenceID: UUID
    public var role: EvidenceRole
    public var origin: EvidenceOrigin
    public var sourceQuality: SourceQuality
    public var text: String
    public var textSHA256: String
    public var locationLabel: String
    public var captureID: UUID?
    public var workID: UUID?
    public var editionID: UUID?
    public var position: EvidencePosition?
    public var retrieval: RetrievalScore?
    public var estimatedTokens: Int

    public init(citationID: String, evidenceID: UUID = UUID(), role: EvidenceRole, origin: EvidenceOrigin,
                sourceQuality: SourceQuality, text: String, locationLabel: String, captureID: UUID? = nil,
                workID: UUID? = nil, editionID: UUID? = nil, position: EvidencePosition? = nil,
                retrieval: RetrievalScore? = nil, estimatedTokens: Int) {
        self.citationID = citationID
        self.evidenceID = evidenceID
        self.role = role
        self.origin = origin
        self.sourceQuality = sourceQuality
        self.text = text
        self.textSHA256 = SHA256Hex.of(text)
        self.locationLabel = locationLabel
        self.captureID = captureID
        self.workID = workID
        self.editionID = editionID
        self.position = position
        self.retrieval = retrieval
        self.estimatedTokens = estimatedTokens
    }

    enum CodingKeys: String, CodingKey {
        case citationID = "citation_id"
        case evidenceID = "evidence_id"
        case role, origin
        case sourceQuality = "source_quality"
        case text
        case textSHA256 = "text_sha256"
        case locationLabel = "location_label"
        case captureID = "capture_id"
        case workID = "work_id"
        case editionID = "edition_id"
        case position, retrieval
        case estimatedTokens = "estimated_tokens"
    }
}

public struct WorkSnapshot: Codable, Sendable, Equatable {
    public var workID: UUID
    public var editionID: UUID
    public var title: String
    public var authorDisplay: String
    public var sourceKind: String

    public init(workID: UUID, editionID: UUID, title: String, authorDisplay: String, sourceKind: String) {
        self.workID = workID
        self.editionID = editionID
        self.title = title
        self.authorDisplay = authorDisplay
        self.sourceKind = sourceKind
    }

    enum CodingKeys: String, CodingKey {
        case workID = "work_id"
        case editionID = "edition_id"
        case title
        case authorDisplay = "author_display"
        case sourceKind = "source_kind"
    }
}

public struct SpoilerBoundary: Codable, Sendable, Equatable {
    public enum Basis: String, Codable, Sendable {
        case none
        case selectionPosition = "selection_position"
        case userConfirmedPosition = "user_confirmed_position"
    }
    public var enabled: Bool
    public var maxOrdinal: Int?
    public var basis: Basis
    public var excludedEvidenceCount: Int

    public init(enabled: Bool, maxOrdinal: Int?, basis: Basis, excludedEvidenceCount: Int = 0) {
        self.enabled = enabled
        self.maxOrdinal = maxOrdinal
        self.basis = basis
        self.excludedEvidenceCount = excludedEvidenceCount
    }

    public static let disabled = SpoilerBoundary(enabled: false, maxOrdinal: nil, basis: .none)

    enum CodingKeys: String, CodingKey {
        case enabled
        case maxOrdinal = "max_ordinal"
        case basis
        case excludedEvidenceCount = "excluded_evidence_count"
    }
}

/// An earlier question and answer of the same conversation, as resent with a later question.
public struct ConversationTurnSnapshot: Codable, Sendable, Equatable {
    public var turnID: UUID
    public var question: String
    /// The answer as resent. Citation markers in it pointed into that turn's own pack, whose evidence is not resent,
    /// so the builder replaces them with `PromptTemplate.earlierCitation` (a pack never holds an earlier `[cN]`).
    public var answer: String
    /// Highest paragraph ordinal of the evidence that turn used; -1 when it used none; nil when unknown.
    public var maxEvidenceOrdinal: Int?
    /// The edition whose extracted paragraphs `maxEvidenceOrdinal` counts, set when it is 0 or more. Ordinals in
    /// another edition count different paragraphs, so a restricted pack compares a turn with its boundary only when this
    /// is the pack's edition (plan 13.3).
    public var editionID: UUID?
    /// What that turn shared with its destination: the scopes of its evidence and, transitively, of the earlier
    /// turns it resent (plan 14.2). Resending the turn shares the same content again, so a pack's sharing scopes
    /// include these.
    public var sharedScopes: [SharingScope]
    /// Where that turn was sent. A turn is resent only to the same destination (origin, classification and model),
    /// because its answer can repeat what that turn shared, for example the user's notes (I-07).
    public var destination: EndpointIdentity

    public init(turnID: UUID, question: String, answer: String, maxEvidenceOrdinal: Int?, editionID: UUID?, sharedScopes: [SharingScope],
                destination: EndpointIdentity) {
        self.turnID = turnID
        self.question = question
        self.answer = answer
        self.maxEvidenceOrdinal = maxEvidenceOrdinal
        self.editionID = (maxEvidenceOrdinal ?? -1) >= 0 ? editionID : nil
        self.sharedScopes = Set(sharedScopes).sorted()
        self.destination = destination
    }

    /// The turn an answered request adds to its conversation: its question and answer, the scopes and destination of
    /// its pack, and the highest position its pack used, counted in the pack's edition: -1 when it sent no evidence and
    /// resent no turn that used any; nil when any evidence or resent turn has no known position in that edition. A
    /// restricted pack never includes a turn whose position is nil. Unless the turn went to another destination, the
    /// reason it gives first, it says the turn's place in this edition isn't known when a position is set, and that no
    /// reading position is set when none is. A note or thought
    /// with no position in the work counts as unknown too, even one on no work at all: the turn carries one maximum and
    /// one edition, so it could not show later that a note made at a late place in another work is within that work's
    /// boundary.
    ///
    /// The snapshot names an edition but no work. A turn about another work, with a position in that work's edition, is
    /// left out of a restricted pack as one counted in "another edition", which is safe but names the wrong reason. Plan
    /// 7.2 ties a conversation to one work (or a capture in it), so this arises only if M5 lets a conversation span
    /// works; it would then need the work in the snapshot to say "another book".
    public init(question: String, answer: String, pack: ContextPack) {
        let edition = pack.work?.editionID
        let evidence = pack.evidence.map { item in item.editionID != nil && item.editionID == edition ? item.position?.lastOrdinal : nil }
        let turns = pack.history.includedTurns.map { turn in turn.isPlaced(inEdition: edition) ? turn.maxEvidenceOrdinal : nil }
        let positions = evidence + turns
        let known = positions.compactMap { $0 }
        self.init(turnID: pack.requestID, question: question, answer: answer,
                  maxEvidenceOrdinal: positions.isEmpty ? -1 : (known.count == positions.count ? known.max() : nil),
                  editionID: edition, sharedScopes: Array(SharingScope.scopes(for: pack)), destination: pack.endpoint)
    }

    /// True when the turn's evidence has a known place in `edition`: it used none (-1), or its highest position counts
    /// that edition's paragraphs.
    public func isPlaced(inEdition edition: UUID?) -> Bool {
        guard let maxEvidenceOrdinal else { return false }
        return maxEvidenceOrdinal < 0 || (editionID != nil && editionID == edition)
    }

    enum CodingKeys: String, CodingKey {
        case turnID = "turn_id"
        case question, answer
        case maxEvidenceOrdinal = "max_evidence_ordinal"
        case editionID = "edition_id"
        case sharedScopes = "shared_scopes"
        case destination
    }
}

public struct HistoryInclusion: Codable, Sendable, Equatable {
    public var includedTurns: [ConversationTurnSnapshot]
    public var excludedTurnCount: Int
    public var exclusionReason: String?

    public init(includedTurns: [ConversationTurnSnapshot] = [], excludedTurnCount: Int = 0, exclusionReason: String? = nil) {
        self.includedTurns = includedTurns
        self.excludedTurnCount = excludedTurnCount
        self.exclusionReason = exclusionReason
    }

    enum CodingKeys: String, CodingKey {
        case includedTurns = "included_turns"
        case excludedTurnCount = "excluded_turn_count"
        case exclusionReason = "exclusion_reason"
    }
}

public struct TokenEstimatorInfo: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case heuristic, tokenizer }
    public var kind: Kind
    public var name: String

    public init(kind: Kind, name: String) {
        self.kind = kind
        self.name = name
    }
}

/// Budget accounting (plan 13.2). Every number is an estimate unless `estimator.kind == .tokenizer`.
public struct BudgetAccounting: Codable, Sendable, Equatable {
    public enum LimitSource: String, Codable, Sendable {
        case configured
        case defaultUnknownModel = "default_unknown_model"
    }
    public var contextLimitTokens: Int
    public var contextLimitSource: LimitSource
    public var systemTokens: Int
    public var questionTokens: Int
    public var historyTokens: Int
    public var outputReserveTokens: Int
    public var safetyMarginTokens: Int
    public var evidenceBudgetTokens: Int
    public var evidenceTokens: Int
    public var estimator: TokenEstimatorInfo
    public var estimated: Bool

    public init(contextLimitTokens: Int, contextLimitSource: LimitSource, systemTokens: Int, questionTokens: Int, historyTokens: Int,
                outputReserveTokens: Int, safetyMarginTokens: Int, evidenceBudgetTokens: Int, evidenceTokens: Int,
                estimator: TokenEstimatorInfo, estimated: Bool) {
        self.contextLimitTokens = contextLimitTokens
        self.contextLimitSource = contextLimitSource
        self.systemTokens = systemTokens
        self.questionTokens = questionTokens
        self.historyTokens = historyTokens
        self.outputReserveTokens = outputReserveTokens
        self.safetyMarginTokens = safetyMarginTokens
        self.evidenceBudgetTokens = evidenceBudgetTokens
        self.evidenceTokens = evidenceTokens
        self.estimator = estimator
        self.estimated = estimated
    }

    enum CodingKeys: String, CodingKey {
        case contextLimitTokens = "context_limit_tokens"
        case contextLimitSource = "context_limit_source"
        case systemTokens = "system_tokens"
        case questionTokens = "question_tokens"
        case historyTokens = "history_tokens"
        case outputReserveTokens = "output_reserve_tokens"
        case safetyMarginTokens = "safety_margin_tokens"
        case evidenceBudgetTokens = "evidence_budget_tokens"
        case evidenceTokens = "evidence_tokens"
        case estimator, estimated
    }
}

public struct TruncationInfo: Codable, Sendable, Equatable {
    public var truncated: Bool
    public var omittedEvidenceCount: Int
    public var reason: String?
    /// User-facing disclosure, for example "2 passages didn't fit and weren't sent".
    public var disclosure: String?

    public init(truncated: Bool = false, omittedEvidenceCount: Int = 0, reason: String? = nil, disclosure: String? = nil) {
        self.truncated = truncated
        self.omittedEvidenceCount = omittedEvidenceCount
        self.reason = reason
        self.disclosure = disclosure
    }

    enum CodingKeys: String, CodingKey {
        case truncated
        case omittedEvidenceCount = "omitted_evidence_count"
        case reason, disclosure
    }
}

public struct RetrievalSettings: Codable, Sendable, Equatable {
    public var strategy: String
    public var queryTerms: [String]
    public var topK: Int
    public var adjacentChunks: Int
    public var chunkWordsMin: Int
    public var chunkWordsMax: Int
    public var candidatesConsidered: Int

    public init(strategy: String, queryTerms: [String], topK: Int, adjacentChunks: Int, chunkWordsMin: Int,
                chunkWordsMax: Int, candidatesConsidered: Int) {
        self.strategy = strategy
        self.queryTerms = queryTerms
        self.topK = topK
        self.adjacentChunks = adjacentChunks
        self.chunkWordsMin = chunkWordsMin
        self.chunkWordsMax = chunkWordsMax
        self.candidatesConsidered = candidatesConsidered
    }

    enum CodingKeys: String, CodingKey {
        case strategy
        case queryTerms = "query_terms"
        case topK = "top_k"
        case adjacentChunks = "adjacent_chunks"
        case chunkWordsMin = "chunk_words_min"
        case chunkWordsMax = "chunk_words_max"
        case candidatesConsidered = "candidates_considered"
    }
}

public struct TextCoverage: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable {
        case bookTextIndexed = "book_text_indexed"
        case indexing
        case textUnavailable = "text_unavailable"
        case notApplicable = "not_applicable"
    }
    public var state: State
    public var resourcesIndexed: Int
    public var resourcesTotal: Int

    public init(state: State, resourcesIndexed: Int, resourcesTotal: Int) {
        self.state = state
        self.resourcesIndexed = resourcesIndexed
        self.resourcesTotal = resourcesTotal
    }

    enum CodingKeys: String, CodingKey {
        case state
        case resourcesIndexed = "resources_indexed"
        case resourcesTotal = "resources_total"
    }
}

/// The ContextPack (plan 13.1, 11.2, Appendix A.2; Contracts/schemas/context-pack.v1.schema.json).
/// Built and persisted before a request is sent; it is the auditable record of exactly what was sent.
public struct ContextPack: Codable, Sendable, Equatable {
    public var schemaVersion: Int = 1
    public var packID: UUID
    public var requestID: UUID
    public var conversationID: UUID
    public var createdAt: Date
    public var scope: ContextScope
    public var scopeLabel: String
    public var mode: String
    public var coverage: ContextCoverage
    public var coverageLabel: String
    public var question: String
    public var work: WorkSnapshot?
    public var evidence: [EvidenceItem]
    public var spoilerBoundary: SpoilerBoundary
    public var history: HistoryInclusion
    public var budget: BudgetAccounting
    public var truncation: TruncationInfo
    /// Limitations the app states itself (empty when there are none).
    public var limitations: [ContextLimitation]
    public var retrieval: RetrievalSettings?
    public var textCoverage: TextCoverage
    public var endpoint: EndpointIdentity
    public var promptTemplateVersion: String
    public var packSHA256: String = ""

    public init(packID: UUID = UUID(), requestID: UUID = UUID(), conversationID: UUID, createdAt: Date, scope: ContextScope,
                coverage: ContextCoverage, question: String, work: WorkSnapshot?, evidence: [EvidenceItem],
                spoilerBoundary: SpoilerBoundary, history: HistoryInclusion, budget: BudgetAccounting,
                truncation: TruncationInfo, limitations: [ContextLimitation] = [], retrieval: RetrievalSettings?,
                textCoverage: TextCoverage, endpoint: EndpointIdentity, promptTemplateVersion: String) {
        self.packID = packID
        self.requestID = requestID
        self.conversationID = conversationID
        self.createdAt = createdAt
        self.scope = scope
        self.scopeLabel = scope.chipLabel
        self.mode = "source_grounded"
        self.coverage = coverage
        self.coverageLabel = coverage.label
        self.question = question
        self.work = work
        self.evidence = evidence
        self.spoilerBoundary = spoilerBoundary
        self.history = history
        self.budget = budget
        self.truncation = truncation
        self.limitations = limitations
        self.retrieval = retrieval
        self.textCoverage = textCoverage
        self.endpoint = endpoint
        self.promptTemplateVersion = promptTemplateVersion
        self.packSHA256 = ""
        self.packSHA256 = computeDigest()
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case packID = "pack_id"
        case requestID = "request_id"
        case conversationID = "conversation_id"
        case createdAt = "created_at"
        case scope
        case scopeLabel = "scope_label"
        case mode, coverage
        case coverageLabel = "coverage_label"
        case question, work, evidence
        case spoilerBoundary = "spoiler_boundary"
        case history, budget, truncation, limitations, retrieval
        case textCoverage = "text_coverage"
        case endpoint
        case promptTemplateVersion = "prompt_template_version"
        case packSHA256 = "pack_sha256"
    }

    /// Upper bound on evidence items in one pack (also enforced by the contract schema).
    public static let maxEvidenceItems = 1000

    /// Citation IDs that may resolve for an answer to this pack.
    public var citationAllowlist: Set<String> { Set(evidence.map(\.citationID)) }

    /// Highest paragraph ordinal of source evidence in this pack (nil if none carries a position).
    public var maxEvidenceOrdinal: Int? { evidence.compactMap { $0.position?.lastOrdinal }.max() }

    /// Spoiler-boundary rules JSON Schema cannot express (plan 13.3, 20.3 "no later text enters a restricted
    /// ContextPack"). With the boundary enabled, every evidence position and every included earlier turn lies at or
    /// before `max_ordinal`; every item from the pack's work (its source text, and a saved thought or companion passage
    /// whose `work_id` is the pack's work) carries a position, so nothing from the work escapes the check; and a turn
    /// whose evidence position is unknown is not included. Positions count one edition's extracted paragraphs, so every
    /// position, and every included turn that used evidence, must be in the pack's edition (`work.edition_id`); an
    /// ordinal from another edition can't be compared with the boundary. Empty when the pack holds.
    /// The builder refuses to return, and the coordinator refuses to store or send, a pack that breaks these rules;
    /// `Spikes/G05-AI/Scripts/validate-exports.py` applies the same rules to contract instances and fixtures.
    public var spoilerBoundaryViolations: [String] {
        guard spoilerBoundary.enabled else { return [] }
        guard let maxOrdinal = spoilerBoundary.maxOrdinal else { return ["spoiler boundary enabled without max_ordinal"] }
        var problems: [String] = []
        for item in evidence {
            if let position = item.position {
                if item.editionID == nil || item.editionID != work?.editionID {
                    problems.append("\(item.citationID) has a position in another edition, so it can't be compared with the boundary")
                } else if position.lastOrdinal > maxOrdinal {
                    problems.append("\(item.citationID) ends at paragraph \(position.lastOrdinal), after the boundary \(maxOrdinal)")
                }
            } else if isFromThisWork(item) {
                problems.append("\(item.citationID) is from this work but has no position, so it can't be shown to lie within the boundary")
            }
        }
        for turn in history.includedTurns {
            guard let turnMax = turn.maxEvidenceOrdinal else {
                problems.append("included turn \(turn.turnID) has no known evidence position")
                continue
            }
            if !turn.isPlaced(inEdition: work?.editionID) {
                problems.append("included turn \(turn.turnID) used paragraphs of another edition, so they can't be compared with the boundary")
            } else if turnMax > maxOrdinal {
                problems.append("included turn \(turn.turnID) used paragraph \(turnMax), after the boundary \(maxOrdinal)")
            }
        }
        return problems
    }

    /// True for the pack's own source text and for any item whose `work_id` is the pack's work (a saved thought on it).
    func isFromThisWork(_ item: EvidenceItem) -> Bool {
        item.origin == .sourceText || (item.workID != nil && item.workID == work?.workID)
    }

    /// Conversation-history rules (plan 14.2, I-07; plan 13.4, A.2). Every included earlier turn was sent to this pack's
    /// destination (origin, classification and model), so resending it shares nothing with a destination that has not
    /// already received it; and no included answer carries a citation marker, because its IDs pointed into an earlier
    /// pack and would resolve against this one's evidence. Empty when the pack holds. The builder refuses to return, and
    /// the coordinator refuses to store or send, a pack that breaks these rules; `validate-exports.py` applies the
    /// destination rule to contract instances and fixtures, and the schema rejects a marker in an included answer.
    public var historyViolations: [String] {
        var problems: [String] = []
        for turn in history.includedTurns {
            if !turn.destination.isSameDestination(as: endpoint) {
                problems.append("included turn \(turn.turnID) was sent to \(turn.destination.disclosureRow), not \(endpoint.disclosureRow)")
            }
            if PromptTemplate.containsCitationMarker(turn.answer) {
                problems.append("included turn \(turn.turnID) has a citation marker from its own pack")
            }
        }
        return problems
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(RFC3339.string(date))
        }
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = RFC3339.date(text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not RFC 3339"))
            }
            return date
        }
        return decoder
    }

    /// SHA-256 (lowercase hex) of the pack's canonical JSON with `pack_sha256` set to "": UTF-8, object keys sorted by
    /// code point, no insignificant whitespace, non-ASCII characters and "/" not escaped, integers in plain decimal,
    /// dates as RFC 3339 UTC strings with milliseconds. Equivalent to Python
    /// `json.dumps(pack, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")`
    /// (checked by `validate-exports.py` on every exported instance and committed fixture).
    public func computeDigest() -> String {
        var copy = self
        copy.packSHA256 = ""
        let data = (try? Self.encoder().encode(copy)) ?? Data()
        return SHA256Hex.of(data)
    }

    public var digestIsValid: Bool { packSHA256 == computeDigest() }
}

public enum SHA256Hex {
    public static func of(_ text: String) -> String { of(Data(text.utf8)) }
    public static func of(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

public enum RFC3339 {
    static func formatter(fractional: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }

    /// RFC 3339 UTC with milliseconds, for example 2026-10-06T08:00:00.000Z.
    public static func string(_ date: Date) -> String { formatter(fractional: true).string(from: date) }

    public static func date(_ text: String) -> Date? {
        formatter(fractional: true).date(from: text) ?? formatter(fractional: false).date(from: text)
    }
}
