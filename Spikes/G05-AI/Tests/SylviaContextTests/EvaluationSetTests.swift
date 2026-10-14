import Foundation
import G05TestSupport
import Testing
@testable import SylviaAI
@testable import SylviaContext

/// Brief item 11 / plan 20.3: the seed evaluation set, stored as expected evidence and behaviour, run through
/// the real ContextPack builder and the deterministic gates with a scripted adversarial answer per item.
/// Model quality and citation support need human review and live models (pending; M5 owns the full set).
struct EvalSet: Decodable {
    struct Thought: Decodable { let kind: String; let text: String }
    struct Turn: Decodable { let question: String; let answer: String; let max_evidence_ordinal_offset: Int? }
    struct Selection: Decodable { let paragraph_containing: String; let exact_text: String }
    struct Setup: Decodable {
        let selection: Selection?
        let thoughts: [Thought]?
        let exclude_later_passages: Bool?
        let boundary_after_resource: String?
        let history: [Turn]?
        let simulate_media_removal: Bool?
        let inject_into_question: String?
        let audio_moment: String?
    }
    struct Expected: Decodable {
        let evidence_count: Int?
        let min_evidence: Int?
        let evidence_must_include: [String]?
        let evidence_must_not_include: [String]?
        let evidence_resource_any: [String]?
        let unresolved_citations: [String]?
        let quote_verdicts: [String]?
        let quote_matches_note_not_source: Bool?
        let spoiler_basis: String?
        let min_excluded_by_boundary: Int?
        let included_turns: Int?
        let excluded_turns: Int?
        let history_must_not_include: [String]?
        let origins_must_not_include: [String]?
        let inert_urls: Int?
        let prompt_evidence_elements: Int?
        let resolved_after_removal: [String]?
        let coverage: String?
        let limitations: [String]?
    }
    struct Item: Decodable {
        let id: String
        let category: String
        let work: String?
        let scope: String
        let question: String
        let setup: Setup
        let adversarial_answer: String
        let expected: Expected
        let expected_behavior: [String]
        let human_review: String
        let gate_kind: String?
        let gate_note: String?
    }
    let format_version: Int
    let deterministic_gates: [String: String]
    let gate_kinds: [String: String]
    let items: [Item]

    static func load() throws -> EvalSet {
        let url = try #require(Bundle.module.url(forResource: "eval-set.v0", withExtension: "json", subdirectory: "EvaluationSet"))
        return try JSONDecoder().decode(EvalSet.self, from: Data(contentsOf: url))
    }
}

@Suite("Evaluation set (plan 20.3 seed)")
struct EvaluationSetTests {
    static let categories: Set<String> = ["passage_explanation", "absent_information", "contradictory_text", "misleading_title", "audio_without_transcript",
                                          "companion_edition_mismatch", "spoiler_boundary", "prompt_injection", "after_media_removal"]

    @Test func setCoversThePlanCategories() throws {
        let set = try EvalSet.load()
        #expect(set.items.count >= 12)
        #expect(Set(set.items.map(\.category)) == Self.categories)
        #expect(Set(set.items.map(\.id)).count == set.items.count)
        for item in set.items {
            #expect(!item.expected_behavior.isEmpty && !item.human_review.isEmpty, "\(item.id) stores behaviour, not prose")
            // An item that cannot fail in part says so (gate_kind structural) and why (gate_note).
            #expect(set.gate_kinds.keys.contains(item.gate_kind ?? "deterministic"), "\(item.id)")
            if item.gate_kind == "structural" { #expect(item.gate_note?.isEmpty == false, "\(item.id) explains what cannot fail yet") }
        }
    }

    /// A second, deliberately simple implementation of "the quotation's words occur in this evidence", written
    /// without the verifier's helpers: lowercase words only (punctuation ignored, so it is a necessary condition
    /// for an exact verdict), ellipsis segments in order.
    static func independentlyContains(_ evidence: String, quote: String) -> Bool {
        func words(_ text: String) -> [String] {
            let cleaned = text.lowercased().replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2060}", with: "")
            let regex = try! NSRegularExpression(pattern: #"[\p{L}\p{N}]+(?:'[\p{L}\p{N}]+)*"#)
            let ns = cleaned as NSString
            return regex.matches(in: cleaned, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
        }
        let haystack = words(evidence)
        var start = 0
        for part in quote.replacingOccurrences(of: "...", with: "\u{2026}").split(separator: "\u{2026}") {
            let needle = words(String(part))
            if needle.isEmpty { continue }
            var found: Int?
            var index = start
            while index + needle.count <= haystack.count {
                if Array(haystack[index..<(index + needle.count)]) == needle { found = index; break }
                index += 1
            }
            guard let found else { return false }
            start = found + needle.count
        }
        return true
    }

    static func verdictName(_ verdict: QuoteCheck.Verdict) -> String {
        switch verdict {
        case .exact: "exact"
        case .paraphrase: "paraphrase"
        case .unsupported: "unsupported"
        case .shortPhrase: "short_phrase"
        }
    }

    @Test func everyItemPassesTheDeterministicGates() throws {
        let set = try EvalSet.load()
        var summary: [String] = ["id\tcategory\tscope\tevidence\tunresolved\tquotes\tlimitations\tgate"]
        for item in set.items {
            let work = item.work == "middlemarch" ? Library.middlemarch : Library.walden
            var boundary: Int?
            if let resource = item.setup.boundary_after_resource {
                boundary = work.work.paragraphs.last { $0.resourceHref == resource }?.ordinal
            }
            let selection = item.setup.selection.map { s -> TextSelection in
                TextSelection(paragraphOrdinal: Library.paragraph(in: work, containing: s.paragraph_containing).ordinal, exactText: s.exact_text)
            }
            let thoughts = (item.setup.thoughts ?? []).map {
                SavedThought(captureID: UUID(), kind: $0.kind == "quote" ? .quote : .note, text: $0.text,
                             workID: item.work == nil ? nil : work.snapshot.workID, editionID: item.work == nil ? nil : work.snapshot.editionID, locationLabel: "Saved", ordinal: nil)
            }
            let history = (item.setup.history ?? []).map {
                ConversationTurnSnapshot(turnID: UUID(), question: $0.question, answer: $0.answer,
                                         maxEvidenceOrdinal: $0.max_evidence_ordinal_offset.map { (boundary ?? 0) + $0 }, editionID: work.snapshot.editionID,
                                         sharedScopes: [.sourceText], destination: Library.endpoint)
            }
            let question = item.question + (item.setup.inject_into_question ?? "")
            let request = ContextRequest(question: question, scope: ContextScope(rawValue: item.scope)!, selection: selection, thoughts: thoughts,
                                         excludeLaterPassages: item.setup.exclude_later_passages ?? false, confirmedPosition: boundary.map { ReadingPosition(editionID: work.snapshot.editionID, paragraphOrdinal: $0) }, history: history,
                                         audioMoment: item.setup.audio_moment)
            var pack = try Library.build(request, work: work)
            let expected = item.expected
            let texts = pack.evidence.map(\.text)

            // Simulated media removal: decode the stored pack and resolve with no index at all.
            if item.setup.simulate_media_removal == true {
                let stored = try ContextPack.encoder().encode(pack)
                let emptyIndex = try PassageIndex()
                #expect(try emptyIndex.allChunks(workID: work.snapshot.workID, maxOrdinal: nil).isEmpty)
                pack = try ContextPack.decoder().decode(ContextPack.self, from: stored)
                let resolved = CitationResolver.resolve(item.adversarial_answer, pack: pack)
                for id in expected.resolved_after_removal ?? [] {
                    #expect(resolved.citations.contains { $0.id == id && $0.isResolved }, "\(item.id): \(id) resolves from the stored snippet")
                }
            }

            // Gate: citations resolve only to supplied evidence.
            let resolved = CitationResolver.resolve(item.adversarial_answer, pack: pack)
            for citation in resolved.citations {
                #expect(citation.isResolved == pack.citationAllowlist.contains(citation.id), "\(item.id): \(citation.id)")
                if !citation.isResolved { #expect(citation.evidenceID == nil && citation.explanation != nil, "\(item.id)") }
            }
            if let unresolved = expected.unresolved_citations {
                #expect(Set(resolved.unresolved.map(\.id)) == Set(unresolved), "\(item.id): unresolved \(resolved.unresolved.map(\.id))")
            }
            if let urls = expected.inert_urls { #expect(resolved.inertURLs.count == urls, "\(item.id)") }

            // Gate: no exact label without verification (independent re-check of every exact verdict).
            let checks = QuoteVerifier.verify(item.adversarial_answer, evidence: pack.evidence)
            for check in checks {
                if case .exact(let id) = check.verdict {
                    let evidence = try #require(pack.evidence.first { $0.citationID == id })
                    #expect(Self.independentlyContains(evidence.text, quote: check.quote), "\(item.id): exact verdict re-checked")
                }
            }
            if let verdicts = expected.quote_verdicts {
                #expect(checks.map { Self.verdictName($0.verdict) } == verdicts, "\(item.id): verdicts \(checks.map(\.verdict))")
            }
            if expected.quote_matches_note_not_source == true {
                let matched = checks.compactMap { check -> EvidenceItem? in
                    if case .exact(let id) = check.verdict { return pack.evidence.first { $0.citationID == id } }
                    return nil
                }
                #expect(!matched.isEmpty && matched.allSatisfy { $0.origin == .userNote }, "\(item.id): the 'quote' is the user's own note")
                #expect(checks.contains { $0.citationMismatch }, "\(item.id): cited a different passage than the one matched")
            }

            // Gate: no later text in a restricted pack; no boundary crossing.
            #expect(pack.spoilerBoundaryViolations.isEmpty, "\(item.id): \(pack.spoilerBoundaryViolations)")
            if pack.spoilerBoundary.enabled, let max = pack.spoilerBoundary.maxOrdinal {
                #expect(pack.evidence.allSatisfy { ($0.position?.lastOrdinal ?? Int.min) <= max }, "\(item.id)")
                #expect(pack.history.includedTurns.allSatisfy { ($0.maxEvidenceOrdinal ?? Int.max) <= max }, "\(item.id)")
            }
            for forbidden in expected.evidence_must_not_include ?? [] {
                #expect(!texts.contains { $0.contains(forbidden) }, "\(item.id): '\(forbidden)' must not be sent")
            }
            for forbidden in expected.history_must_not_include ?? [] {
                #expect(!pack.history.includedTurns.contains { $0.answer.contains(forbidden) || $0.question.contains(forbidden) }, "\(item.id)")
            }
            for origin in expected.origins_must_not_include ?? [] {
                #expect(!pack.evidence.contains { $0.origin.rawValue == origin }, "\(item.id): origin \(origin)")
            }

            // Expected evidence and setup outcomes.
            if let count = expected.evidence_count { #expect(pack.evidence.count == count, "\(item.id): evidence count \(pack.evidence.count)") }
            if let minimum = expected.min_evidence { #expect(pack.evidence.count >= minimum, "\(item.id): evidence count \(pack.evidence.count)") }
            for required in expected.evidence_must_include ?? [] {
                #expect(texts.contains { $0.contains(required) }, "\(item.id): expected evidence containing '\(required)'")
            }
            if let resources = expected.evidence_resource_any {
                #expect(pack.evidence.contains { resources.contains($0.position?.resourceHref ?? "") }, "\(item.id): evidence from \(resources)")
            }
            // Gate: required limitations are stated by the app, and passed on in the prompt.
            if let codes = expected.limitations {
                #expect(pack.limitations.map(\.code.rawValue) == codes, "\(item.id): limitations \(pack.limitations.map(\.code))")
                let prompt = PromptTemplate.request(for: pack, maxOutputTokens: 100).messages.last!.text
                for limitation in pack.limitations {
                    #expect(prompt.contains("<limitation>\(PromptTemplate.escape(limitation.disclosure))</limitation>"), "\(item.id)")
                }
            }
            if let coverage = expected.coverage { #expect(pack.coverage.rawValue == coverage, "\(item.id): coverage \(pack.coverage)") }
            if pack.evidence.isEmpty {
                #expect(pack.coverage == .noPassages && (!pack.limitations.isEmpty || pack.truncation.truncated), "\(item.id): an empty pack says why")
            }
            if let basis = expected.spoiler_basis { #expect(pack.spoilerBoundary.basis.rawValue == basis, "\(item.id)") }
            if let minimum = expected.min_excluded_by_boundary { #expect(pack.spoilerBoundary.excludedEvidenceCount >= minimum, "\(item.id)") }
            if let included = expected.included_turns { #expect(pack.history.includedTurns.count == included, "\(item.id)") }
            if let excluded = expected.excluded_turns { #expect(pack.history.excludedTurnCount == excluded, "\(item.id)") }
            if let elements = expected.prompt_evidence_elements {
                let message = PromptTemplate.request(for: pack, maxOutputTokens: 100).messages.last!.text
                #expect(message.components(separatedBy: "<evidence ").count - 1 == elements, "\(item.id)")
            }
            summary.append([item.id, item.category, item.scope, String(pack.evidence.count), resolved.unresolved.map(\.id).joined(separator: ","),
                            checks.map { Self.verdictName($0.verdict) }.joined(separator: ","), pack.limitations.map(\.code.rawValue).joined(separator: ","),
                            item.gate_kind ?? "deterministic"].joined(separator: "\t"))
        }
        print("EVAL-SUMMARY\n" + summary.joined(separator: "\n"))
    }
}
