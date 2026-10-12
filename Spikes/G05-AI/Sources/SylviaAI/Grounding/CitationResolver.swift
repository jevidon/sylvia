import Foundation

public struct Citation: Sendable, Equatable {
    public let id: String
    public let evidenceID: UUID?
    /// Nil when resolved; otherwise the one-line explanation shown under the answer (plan 13.4, 4.4.5).
    public let explanation: String?

    public var isResolved: Bool { explanation == nil }
}

public enum AnswerSegment: Sendable, Equatable {
    case text(String)
    case citation(Citation)
}

public struct ResolvedAnswer: Sendable, Equatable {
    public let segments: [AnswerSegment]
    public let citations: [Citation]
    public var unresolved: [Citation] { citations.filter { !$0.isResolved } }
    /// URLs found in the answer. They are shown as inert text; opening one is an explicit user action (plan 18.1).
    public let inertURLs: [String]
}

/// Resolves local citation markers ([c1], [c2, c3]) against a pack's allowlist after generation (plan 13.4).
/// An ID outside the allowlist stays visibly unresolved; it never becomes a link. Anything else that looks like
/// a reference (URLs, entity IDs, footnote markers) stays plain text.
public enum CitationResolver {
    static let marker = try! NSRegularExpression(pattern: #"\[\s*([cC][0-9]{1,4}(?:\s*[,;]\s*[cC][0-9]{1,4})*)\s*\]"#)
    static let url = try! NSRegularExpression(pattern: #"(?i)\b(?:https?|ftp|file|sylvia)://[^\s<>\]\)"]+"#)

    public static func resolve(_ answer: String, pack: ContextPack) -> ResolvedAnswer {
        var byID: [String: UUID] = [:]
        for item in pack.evidence { byID[item.citationID] = item.evidenceID }
        return resolve(answer, evidence: byID)
    }

    public static func resolve(_ answer: String, allowlist: Set<String>) -> ResolvedAnswer {
        var byID: [String: UUID] = [:]
        for id in allowlist { byID[id] = UUID(uuid: UUID_NULL) }
        return resolve(answer, evidence: byID)
    }

    static func resolve(_ answer: String, evidence: [String: UUID]) -> ResolvedAnswer {
        var segments: [AnswerSegment] = []
        var citations: [Citation] = []
        let ns = answer as NSString
        var cursor = 0
        for match in marker.matches(in: answer, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                segments.append(.text(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))))
            }
            let ids = ns.substring(with: match.range(at: 1)).split(whereSeparator: { $0 == "," || $0 == ";" })
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            for id in ids {
                let citation: Citation
                if let evidenceID = evidence[id] {
                    citation = Citation(id: id, evidenceID: evidenceID, explanation: nil)
                } else {
                    citation = Citation(id: id, evidenceID: nil,
                                        explanation: "\(id) doesn't match any passage sent with this question, so it can't be opened.")
                }
                citations.append(citation)
                segments.append(.citation(citation))
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length { segments.append(.text(ns.substring(from: cursor))) }
        let urls = url.matches(in: answer, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
        return ResolvedAnswer(segments: segments, citations: citations, inertURLs: urls)
    }
}
