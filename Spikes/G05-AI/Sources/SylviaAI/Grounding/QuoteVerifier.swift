import Foundation

public struct QuoteCheck: Sendable, Equatable {
    public enum Verdict: Sendable, Equatable {
        /// Every word and punctuation mark matches one supplied evidence item as whole tokens, letter case included
        /// (only the quotation's first letter may differ in case), after whitespace, quote-mark, dash and
        /// invisible-character normalization. Ellipses may join segments that occur in that order; each segment needs
        /// at least `QuoteVerifier.minimumWords` words.
        case exact(citationID: String)
        /// Close to supplied evidence but not its wording: labelled as a paraphrase, never as a quotation.
        case paraphrase(closestCitationID: String, overlap: Double)
        /// Not supported by any supplied evidence.
        case unsupported
        /// One or two quoted words. Too short to establish a quotation (it may be a term or scare quotes), so it is
        /// never labelled exact; the label says whether the words occur, as whole words in that order, in a supplied
        /// passage (`foundIn` names the first such passage, preferring the cited one).
        case shortPhrase(foundIn: String?)
    }

    public let quote: String
    public let verdict: Verdict
    /// The citation marker placed right after the quote, if any.
    public let citedID: String?

    /// True when the quote matched exactly but the model cited a different passage.
    public var citationMismatch: Bool {
        if case .exact(let id) = verdict, let citedID { return id != citedID }
        return false
    }

    public var label: String {
        switch verdict {
        case .exact: "Exact quotation"
        case .paraphrase: "Paraphrase · not an exact quotation"
        case .unsupported: "Unsupported quotation · not found in the passages sent"
        case .shortPhrase(let found): found == nil ? "Short quoted phrase · not found in the passages sent"
            : "Short quoted phrase · not checked as a quotation"
        }
    }
}

/// Validates claimed direct quotations in an answer against the evidence actually supplied (plan 13.4).
///
/// A claimed quotation is either a Markdown block quote (consecutive lines starting with `>`, nested `> >` included)
/// or text between a matching pair of quotation marks in any of these styles: “…”, "…", ‘…’, '…', «…», ‹…›, „…“ or
/// „…”. In a block quote, citation markers are taken as its citation and are not part of the quoted words, and a
/// final line starting with a dash ("— Thoreau") is an attribution, not quoted text. Single marks only count at word
/// boundaries (an opening mark not preceded by a letter or digit, a closing mark not followed by one), so apostrophes
/// in "don’t" or "the boys' room" are not quotation marks. A quotation nested inside another (including quotation
/// marks inside a block quote) is part of the outer one and is not checked separately. Quotations of `minimumWords`
/// or more words get exact, paraphrase or unsupported; shorter ones get `shortPhrase`, so no quoted wording goes
/// unlabelled.
public enum QuoteVerifier {
    public static let minimumWords = 3
    /// Share of the quote's content words that must appear in one evidence item for the "paraphrase" label.
    /// Lexical overlap cannot establish that a passage supports a claim; it only separates "close to a supplied
    /// passage" from "nowhere in the supplied passages". Both labels say "not an exact quotation".
    public static let paraphraseThreshold = 0.75
    public static let paraphraseMinimumMatches = 3
    static let functionWords: Set<String> = [
        "the", "and", "for", "but", "not", "with", "that", "this", "from", "was", "were", "are", "his", "her", "its", "had", "has",
        "have", "him", "she", "they", "them", "their", "there", "then", "than", "who", "whom", "which", "what", "when", "where",
        "would", "could", "should", "will", "shall", "into", "upon", "most", "more", "very", "all", "any", "some", "one", "our",
        "you", "your", "been", "being", "such", "only", "also", "just", "own", "out", "may", "might", "must", "can", "did", "does",
    ]

    /// Quotation styles, outermost conventions first. Each pattern's group 1 is the quoted text.
    static let quotePatterns = [
        #"\u201C([^\u201C\u201D]{1,4000})\u201D"#,                                       // “English double”
        #""([^"]{1,4000})""#,                                                              // "straight double"
        #"\u201E([^\u201C\u201D\u201E]{1,4000})[\u201C\u201D]"#,                           // „German or Polish“
        #"\u00AB\s*([^\u00AB\u00BB]{1,4000}?)\s*\u00BB"#,                                   // «guillemets»
        #"\u2039\s*([^\u2039\u203A]{1,4000}?)\s*\u203A"#,                                   // ‹single guillemets›
        #"(?<![\p{L}\p{N}])\u2018([^\u2018]{1,4000}?)\u2019(?![\p{L}\p{N}])"#,                // ‘English single’
        #"(?<![\p{L}\p{N}])'(?=[\p{L}\p{N}])([^'\n]{0,4000}?[^\s'])'(?![\p{L}\p{N}])"#,   // 'straight single'
    ].map { try! NSRegularExpression(pattern: $0) }
    static let trailingCitation = try! NSRegularExpression(pattern: #"^[\s,.;:]*\[\s*([cC][0-9]{1,4})"#)
    /// A Markdown block quote: one or more consecutive lines starting with up to three spaces and `>`.
    static let blockQuote = try! NSRegularExpression(pattern: #"(?m)^[ \t]{0,3}>[^\n]*(?:\n[ \t]{0,3}>[^\n]*)*"#)
    /// The block-quote markers at the start of one line, nested ones included ("> > ").
    static let blockQuotePrefix = try! NSRegularExpression(pattern: #"^[ \t]{0,3}(?:>[ \t]?)+"#)
    /// An attribution line under a block quote: "— Thoreau", "-- Walden", "– Thoreau, Walden".
    static let attributionLine = try! NSRegularExpression(pattern: #"^\s*(?:—|–|-{1,3})\s*\S"#)

    /// The claimed quotations in `answer`, in reading order, without those nested inside another. `citedInside` is the
    /// first citation of a block quote's last citation marker, when the marker is inside the block.
    static func quotations(in answer: String) -> [(quote: String, range: NSRange, citedInside: String?)] {
        let ns = answer as NSString
        var found: [(quote: String, range: NSRange, citedInside: String?)] = []
        for match in blockQuote.matches(in: answer, range: NSRange(location: 0, length: ns.length)) {
            let (quote, cited) = blockQuoteContent(ns.substring(with: match.range))
            found.append((quote, match.range, cited))
        }
        for pattern in quotePatterns {
            for match in pattern.matches(in: answer, range: NSRange(location: 0, length: ns.length))
            where !found.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) {
                found.append((ns.substring(with: match.range(at: 1)), match.range, nil))
            }
        }
        return found.sorted { $0.range.location < $1.range.location }
    }

    /// The quoted words of a block quote (markers removed, a final attribution line dropped, citation markers taken
    /// out) and the citation its last marker names.
    static func blockQuoteContent(_ block: String) -> (quote: String, cited: String?) {
        var lines = block.components(separatedBy: "\n").map { line -> String in
            let ns = line as NSString
            let prefix = blockQuotePrefix.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))
            return prefix.map { ns.substring(from: $0.range.length) } ?? line
        }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        if lines.count > 1, let last = lines.last,
           attributionLine.firstMatch(in: last, range: NSRange(location: 0, length: (last as NSString).length)) != nil {
            lines.removeLast()
        }
        let joined = lines.joined(separator: "\n")
        let ns = joined as NSString
        let markers = CitationResolver.marker.matches(in: joined, range: NSRange(location: 0, length: ns.length))
        let cited = markers.last.map { ns.substring(with: $0.range(at: 1)) }
            .flatMap { $0.split(whereSeparator: { $0 == "," || $0 == ";" }).first }
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let quote = CitationResolver.marker.stringByReplacingMatches(in: joined, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        return (quote.trimmingCharacters(in: .whitespacesAndNewlines), cited)
    }

    public static func verify(_ answer: String, evidence: [EvidenceItem]) -> [QuoteCheck] {
        let ns = answer as NSString
        let normalizedEvidence = evidence.map {
            (id: $0.citationID, text: normalize($0.text), tokens: tokens($0.text), exactTokens: tokens($0.text, foldCase: false))
        }
        var checks: [QuoteCheck] = []
        for (quote, range, citedInside) in quotations(in: answer) {
            let words = trimPunctuation(tokens(quote)).filter(isWord).count
            guard words > 0 else { continue }  // punctuation only, for example a quoted "?"
            let tail = ns.substring(from: range.location + range.length)
            let tailNS = tail as NSString
            let cited = citedInside ?? trailingCitation.firstMatch(in: tail, range: NSRange(location: 0, length: min(tailNS.length, 40)))
                .map { tailNS.substring(with: $0.range(at: 1)).lowercased() }
            let verdict = words < minimumWords ? shortVerdict(for: quote, evidence: normalizedEvidence, citedID: cited)
                : verdict(for: quote, evidence: normalizedEvidence, citedID: cited)
            checks.append(QuoteCheck(quote: quote, verdict: verdict, citedID: cited))
        }
        return checks
    }

    typealias NormalizedEvidence = (id: String, text: String, tokens: [String], exactTokens: [String])

    static func shortVerdict(for quote: String, evidence: [NormalizedEvidence], citedID: String?) -> QuoteCheck.Verdict {
        let run = trimPunctuation(tokens(quote))
        let ordered = evidence.filter { $0.id == citedID } + evidence.filter { $0.id != citedID }
        return .shortPhrase(foundIn: ordered.first { firstRun(of: run, in: $0.tokens, from: 0) != nil }?.id)
    }

    static func verdict(for quote: String, evidence: [NormalizedEvidence], citedID: String?) -> QuoteCheck.Verdict {
        if let segments = exactSegments(quote) {
            // Letter case is significant for an exact quotation, except the first letter of the quotation, which may be
            // capitalized or lowercased to fit the answer's sentence (a standard quoting convention).
            let variants = initialCaseVariants(segments)
            // Prefer the cited passage when it matches.
            let ordered = evidence.filter { $0.id == citedID } + evidence.filter { $0.id != citedID }
            for item in ordered where variants.contains(where: { containsInOrder(item.exactTokens, $0) }) {
                return .exact(citationID: item.id)
            }
        }
        let quoteWords = wordSet(normalize(quote)).filter { $0.count >= 3 && !functionWords.contains($0) }
        guard quoteWords.count >= paraphraseMinimumMatches else { return .unsupported }
        var best: (id: String, overlap: Double, matches: Int)?
        for item in evidence {
            let matches = quoteWords.intersection(wordSet(item.text)).count
            let overlap = Double(matches) / Double(quoteWords.count)
            if overlap > (best?.overlap ?? 0) { best = (item.id, overlap, matches) }
        }
        if let best, best.overlap >= paraphraseThreshold, best.matches >= paraphraseMinimumMatches {
            return .paraphrase(closestCitationID: best.id, overlap: best.overlap)
        }
        return .unsupported
    }

    /// The token runs a quotation must match, in order, to count as exact; nil when it cannot be exact.
    /// Each ellipsis-separated segment needs at least `minimumWords` words, so a "quotation" stitched from one- or
    /// two-word fragments ("the … of … and") can never be labelled exact.
    static func exactSegments(_ quote: String) -> [[String]]? {
        let segments = splitOnEllipsis(quote).map { trimPunctuation(tokens($0, foldCase: false)) }.filter { !$0.isEmpty }
        guard !segments.isEmpty,
              segments.allSatisfy({ segment in segment.filter(isWord).count >= minimumWords }) else { return nil }
        return segments
    }

    /// The segments as quoted, and with only the first letter of the quotation's first word lowercased or capitalized.
    /// Every other letter must match the evidence's case.
    static func initialCaseVariants(_ segments: [[String]]) -> [[[String]]] {
        guard let firstWord = segments.first?.first, let initial = firstWord.first else { return [segments] }
        let rest = firstWord.dropFirst()
        var variants = [segments]
        for changed in [initial.lowercased() + rest, initial.uppercased() + rest] where changed != firstWord {
            var variant = segments
            variant[0][0] = changed
            variants.append(variant)
        }
        return variants
    }

    static func wordSet(_ text: String) -> Set<String> {
        Set(text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
    }

    static func splitOnEllipsis(_ text: String) -> [String] {
        text.replacingOccurrences(of: "[...]", with: "\u{2026}").replacingOccurrences(of: "[…]", with: "\u{2026}")
            .replacingOccurrences(of: "...", with: "\u{2026}").replacingOccurrences(of: ". . .", with: "\u{2026}")
            .split(separator: "\u{2026}").map(String.init)
    }

    /// True when every segment occurs as a contiguous run of tokens in `text`, in order and without overlap.
    /// Matching whole tokens means "at the end" never matches inside "that the endless".
    static func containsInOrder(_ text: [String], _ segments: [[String]]) -> Bool {
        var start = 0
        for segment in segments {
            guard let found = firstRun(of: segment, in: text, from: start) else { return false }
            start = found + segment.count
        }
        return true
    }

    static func firstRun(of segment: [String], in text: [String], from start: Int) -> Int? {
        guard !segment.isEmpty, text.count - start >= segment.count else { return nil }
        var index = start
        while index + segment.count <= text.count {
            if text[index] == segment[0] && Array(text[index..<(index + segment.count)]) == segment { return index }
            index += 1
        }
        return nil
    }

    /// Comparison tokens: words (letters, digits and apostrophes inside a word) and single punctuation marks,
    /// after `normalize`. Quotation marks and whitespace are not tokens. Stored evidence keeps its exact text.
    /// `foldCase: false` keeps letter case (the exact-quotation check).
    static func tokens(_ text: String, foldCase: Bool = true) -> [String] {
        var out: [String] = []
        var word = ""
        func flush() {
            // An apostrophe at either end of a word is a quotation mark, not part of the word.
            while word.hasSuffix("'") { word.removeLast() }
            while word.hasPrefix("'") { word.removeFirst() }
            if !word.isEmpty { out.append(word) }
            word = ""
        }
        for character in normalize(text, foldCase: foldCase) {
            if character.isLetter || character.isNumber || (character == "'" && !word.isEmpty) {
                word.append(character)
            } else {
                flush()
                if character.isWhitespace || character == "\"" || character == "'" { continue }
                // A run of dashes is one dash ("--", "---" and an em dash all normalize to "-").
                if character == "-" && out.last == "-" && word.isEmpty { continue }
                out.append(String(character))
            }
        }
        flush()
        return out
    }

    static func isWord(_ token: String) -> Bool { token.first.map { $0.isLetter || $0.isNumber } ?? false }

    static func trimPunctuation(_ tokens: [String]) -> [String] {
        var slice = tokens[...]
        while let first = slice.first, !isWord(first) { slice = slice.dropFirst() }
        while let last = slice.last, !isWord(last) { slice = slice.dropLast() }
        return Array(slice)
    }

    /// Normalization used only for comparison; stored evidence keeps its exact text. Letter case is folded unless
    /// `foldCase` is false.
    static func normalize(_ text: String, foldCase: Bool = true) -> String {
        var out = text.precomposedStringWithCompatibilityMapping
        for invisible in ["\u{2060}", "\u{FEFF}", "\u{00AD}", "\u{200B}", "\u{200C}", "\u{200D}"] {
            out = out.replacingOccurrences(of: invisible, with: "")
        }
        out = out.replacingOccurrences(of: "\u{2018}", with: "'").replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2014}", with: "-").replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "--", with: "-")
        if foldCase { out = out.lowercased() }
        // Treat punctuation-adjacent whitespace uniformly and collapse runs.
        out = out.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let trimSet = CharacterSet(charactersIn: " .,;:!?'\"-")
        return out.trimmingCharacters(in: trimSet)
    }
}
