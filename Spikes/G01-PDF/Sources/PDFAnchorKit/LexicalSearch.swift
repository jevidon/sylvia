import Foundation

/// A hit in a page's extracted text, in Unicode scalar offsets (the unit anchors use).
public struct SearchHit: Hashable, Sendable {
    public var pageIndex: Int
    public var pageLabel: String?
    public var range: ScalarRange
    /// The page text at `range`, exactly.
    public var text: String
}

/// "Search this book" over Sylvia's own extracted page text (plan 11.3). The product uses FTS5 over the same text;
/// this spike only needs to prove that a hit in extracted text maps back to a page and a selection.
///
/// The query is matched literally (no pattern syntax), case-insensitively. Pages without selectable text are
/// never searched and never produce hits.
public enum LexicalSearch {
    public static func find(_ query: String, in extraction: DocumentExtraction) -> [SearchHit] {
        guard !query.isEmpty else { return [] }
        var hits: [SearchHit] = []
        for page in extraction.pages {
            guard page.supportsTextFeatures, let text = page.text else { continue }
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let r = text.range(of: query, options: [.caseInsensitive, .literal], range: searchStart..<text.endIndex)
            {
                let start = text.unicodeScalars.distance(from: text.unicodeScalars.startIndex, to: r.lowerBound)
                let end = start + text.unicodeScalars.distance(from: r.lowerBound, to: r.upperBound)
                let range = ScalarRange(start: start, end: end)
                if let hitText = try? UnicodeOffsets.substring(text, scalars: range) {
                    hits.append(SearchHit(pageIndex: page.pageIndex, pageLabel: page.pageLabel, range: range, text: hitText))
                }
                searchStart = r.upperBound
            }
        }
        return hits
    }
}
