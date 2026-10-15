import Foundation

/// What a request shares beyond the question (plan 14.2: reconfirm when the user broadens sharing to notes/audio).
public enum SharingScope: String, Codable, Sendable, CaseIterable, Comparable {
    /// Passages from the publication's text.
    case sourceText = "source_text"
    /// The user's saved quotes, notes and transcripts of their clips.
    case savedThoughts = "saved_thoughts"
    /// An audio clip uploaded for transcription.
    case audio

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Everything a request for `pack` shares: its evidence, and the earlier turns it resends with what each of them
    /// shared (an earlier answer can repeat or paraphrase the notes it was based on).
    public static func scopes(for pack: ContextPack) -> Set<SharingScope> {
        evidenceScopes(for: pack).union(historyScopes(for: pack))
    }

    /// The scopes of the pack's own evidence.
    public static func evidenceScopes(for pack: ContextPack) -> Set<SharingScope> {
        var scopes = Set<SharingScope>()
        for item in pack.evidence {
            switch item.origin {
            case .sourceText, .companionPassage: scopes.insert(.sourceText)
            case .savedQuote, .userNote, .transcript: scopes.insert(.savedThoughts)
            }
        }
        return scopes
    }

    /// The scopes the resent earlier turns shared.
    public static func historyScopes(for pack: ContextPack) -> Set<SharingScope> {
        Set(pack.history.includedTurns.flatMap(\.sharedScopes))
    }
}

public struct ConsentGrant: Codable, Sendable, Equatable {
    public var providerID: UUID
    public var origin: String
    public var classification: EndpointClassification
    public var model: String
    public var scopes: [SharingScope]
    public var grantedAt: Date

    enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case origin, classification, model, scopes
        case grantedAt = "granted_at"
    }
}

public struct Disclosure: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        case firstRequest
        case destinationChanged(previousOrigin: String)
        case classificationChanged(previous: EndpointClassification)
        case modelChanged(previousModel: String)
        case broaderSharing(added: [SharingScope])
    }

    public let endpoint: EndpointIdentity
    public let reasons: [Reason]
    public let scopes: [SharingScope]
    /// Plain statements shown before sending (plan 14.2): destination, class, what is sent, whose policies apply.
    public let lines: [String]
}

/// What the request itself carries besides the shared scopes: a typed question (text generation) or nothing but the
/// audio clip (transcription). The disclosure lists only what is actually sent (plan 14.2).
public enum RequestContent: Sendable, Equatable {
    case question
    case audioClip
}

/// How many items of each kind a request's evidence holds, for the "What is sent" line of the disclosure (plan 14.2:
/// state what will be sent). Passages from the work are counted by how they were chosen; the user's saved thoughts are
/// counted apart and never as passages from the book.
public struct EvidenceSummary: Sendable, Equatable {
    /// Passages the user selected in the work.
    public var selected: Int
    /// Text around the selection ("Passage and nearby text").
    public var nearby: Int
    /// Passages Sylvia found by searching the work for the question, and their adjacent passages.
    public var retrieved: Int
    /// Passages of a whole-book pack.
    public var wholeWork: Int
    /// Passages from a confirmed companion ebook (another edition).
    public var companion: Int
    /// Saved quotes, notes and transcripts.
    public var thoughts: Int

    public init(selected: Int = 0, nearby: Int = 0, retrieved: Int = 0, wholeWork: Int = 0, companion: Int = 0, thoughts: Int = 0) {
        self.selected = selected
        self.nearby = nearby
        self.retrieved = retrieved
        self.wholeWork = wholeWork
        self.companion = companion
        self.thoughts = thoughts
    }

    public init(pack: ContextPack) {
        self.init()
        for item in pack.evidence {
            switch item.origin {
            case .savedQuote, .userNote, .transcript: thoughts += 1
            case .companionPassage: companion += 1
            case .sourceText:
                switch item.role {
                case .selection: selected += 1
                case .nearby: nearby += 1
                case .retrieved, .adjacent: retrieved += 1
                case .wholeWork: wholeWork += 1
                // A thought role on source text is not produced by the builder; it is still a passage of the work.
                case .thought: selected += 1
                }
            }
        }
    }

    static func plural(_ count: Int, _ singular: String, _ plural: String) -> String { "\(count) \(count == 1 ? singular : plural)" }

    /// "1 selected passage and 3 nearby passages from Walden", "7 retrieved passages from Middlemarch", "the whole text of
    /// Walden (61 passages)", or nil when the request carries no passage from the work.
    func passagePhrase(workTitle: String?) -> String? {
        var parts: [String] = []
        if wholeWork > 0 {
            let whole = "the whole text\(workTitle.map { " of \($0)" } ?? "") (\(Self.plural(wholeWork, "passage", "passages")))"
            // A whole-book pack holds nothing else from the work; say so without a second "from {title}".
            if selected + nearby + retrieved == 0 {
                return companion > 0 ? whole + " and " + Self.plural(companion, "matching passage", "matching passages") + " from a companion ebook" : whole
            }
            parts.append(Self.plural(wholeWork, "passage", "passages") + " of the whole text")
        }
        if selected > 0 { parts.append(Self.plural(selected, "selected passage", "selected passages")) }
        if nearby > 0 { parts.append(Self.plural(nearby, "nearby passage", "nearby passages")) }
        if retrieved > 0 { parts.append(Self.plural(retrieved, "retrieved passage", "retrieved passages")) }
        var phrase = parts.isEmpty ? nil : parts.joined(separator: " and ") + (workTitle.map { " from \($0)" } ?? "")
        if companion > 0 {
            let companionPart = Self.plural(companion, "matching passage", "matching passages") + " from a companion ebook"
            phrase = phrase.map { "\($0) and \(companionPart)" } ?? companionPart
        }
        return phrase
    }

    /// "2 saved thoughts you selected", or nil when there are none.
    var thoughtPhrase: String? {
        thoughts > 0 ? Self.plural(thoughts, "saved thought", "saved thoughts") + " you selected" : nil
    }
}

public enum ConsentDecision: Sendable, Equatable {
    case granted
    case required(Disclosure)
}

/// Consent ledger (plan 14.2, I-07). A destination is the provider's origin plus its classification and model.
/// Consent is required before the first request, again when any of those change, and again when a request would
/// share a broader scope than was granted. Nothing here ever switches providers: there is no fallback.
public struct ConsentLedger: Codable, Sendable, Equatable {
    public var grants: [UUID: ConsentGrant] = [:]

    public init() {}

    /// Consent for sending `pack` to its destination: its evidence and every earlier turn it resends, disclosed as such.
    public func evaluate(pack: ContextPack, providerID: UUID) -> ConsentDecision {
        evaluate(pack.endpoint, providerID: providerID, scopes: SharingScope.evidenceScopes(for: pack), workTitle: pack.work?.title,
                 evidence: EvidenceSummary(pack: pack), earlierTurnCount: pack.history.includedTurns.count,
                 earlierTurnScopes: SharingScope.historyScopes(for: pack))
    }

    /// `scopes` are what the request's own evidence (or audio) shares; `earlierTurnScopes` what the resent earlier turns
    /// shared. Consent covers both, and the disclosure names the earlier turns separately. `content` says whether the
    /// request carries a question; a transcription request sends only the clip. `evidence` counts what the evidence
    /// holds; without it the disclosure names the shared scopes without counts.
    public func evaluate(_ endpoint: EndpointIdentity, providerID: UUID, scopes evidenceScopes: Set<SharingScope>,
                         content: RequestContent = .question, workTitle: String? = nil, evidence: EvidenceSummary? = nil,
                         earlierTurnCount: Int = 0, earlierTurnScopes: Set<SharingScope> = []) -> ConsentDecision {
        let scopes = evidenceScopes.union(earlierTurnScopes)
        var reasons: [Disclosure.Reason] = []
        if let grant = grants[providerID] {
            if grant.origin != endpoint.origin { reasons.append(.destinationChanged(previousOrigin: grant.origin)) }
            if grant.classification != endpoint.classification { reasons.append(.classificationChanged(previous: grant.classification)) }
            if grant.model != endpoint.model { reasons.append(.modelChanged(previousModel: grant.model)) }
            let added = scopes.subtracting(grant.scopes).sorted()
            if !added.isEmpty { reasons.append(.broaderSharing(added: added)) }
        } else {
            reasons.append(.firstRequest)
        }
        guard !reasons.isEmpty else { return .granted }
        return .required(Disclosure(endpoint: endpoint, reasons: reasons, scopes: scopes.sorted(),
                                    lines: Self.lines(endpoint, scopes: evidenceScopes, content: content, workTitle: workTitle, evidence: evidence,
                                                      earlierTurnCount: earlierTurnCount, earlierTurnScopes: earlierTurnScopes)))
    }

    public mutating func grant(_ disclosure: Disclosure, providerID: UUID, at date: Date) {
        let previous = grants[providerID]
        let sameDestination = previous?.origin == disclosure.endpoint.origin && previous?.model == disclosure.endpoint.model
            && previous?.classification == disclosure.endpoint.classification
        let scopes = Set(disclosure.scopes).union(sameDestination ? Set(previous?.scopes ?? []) : [])
        grants[providerID] = ConsentGrant(providerID: providerID, origin: disclosure.endpoint.origin,
                                          classification: disclosure.endpoint.classification, model: disclosure.endpoint.model,
                                          scopes: scopes.sorted(), grantedAt: date)
    }

    static func lines(_ endpoint: EndpointIdentity, scopes: Set<SharingScope>, content: RequestContent, workTitle: String?, evidence: EvidenceSummary?,
                      earlierTurnCount: Int = 0, earlierTurnScopes: Set<SharingScope> = []) -> [String] {
        var lines = ["Destination: \(endpoint.disclosureRow)"]
        // Built from what the request carries: a transcription request has no question. Passages from the work and the
        // user's saved thoughts are counted apart, so a note is never described as a passage from the book.
        var sent: [String] = content == .question ? ["your question"] : []
        if scopes.contains(.sourceText) {
            sent.append(evidence?.passagePhrase(workTitle: workTitle) ?? "passages from the book")
        }
        if scopes.contains(.savedThoughts) { sent.append(evidence?.thoughtPhrase ?? "the saved thoughts you selected") }
        if scopes.contains(.audio) { sent.append("the audio clip you selected") }
        if earlierTurnCount > 0 {
            let plural = earlierTurnCount == 1 ? "" : "s"
            var earlier = "\(earlierTurnCount) earlier question\(plural) and answer\(plural) from this conversation"
            if earlierTurnScopes.contains(.savedThoughts) { earlier += ", including answers based on your saved thoughts" }
            sent.append(earlier)
        }
        lines.append("What is sent: " + sent.joined(separator: ", ") + ". Nothing else from your library is sent.")
        switch endpoint.classification {
        case .hosted:
            lines.append("\(endpoint.host) is a hosted service. Its operator's terms and data policies apply to what it receives.")
        case .userManaged:
            lines.append("\(endpoint.host) is a connection you set up. Sylvia can't check who operates it or whether it passes requests on to another service.")
        case .local:
            lines.append("\(endpoint.host) is an address on your local network. Sylvia can't check whether that server passes requests on to another service.")
        }
        return lines
    }
}
