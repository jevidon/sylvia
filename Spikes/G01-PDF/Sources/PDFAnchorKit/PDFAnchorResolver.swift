import CoreGraphics
import Foundation
import PDFKit

/// The result of restoring a stored anchor against an opened PDF (plan 7.5 re-anchoring order).
public enum AnchorResolution {
    /// The stored locator still points at exactly the stored text: same asset, same page text, same scalar range.
    case exact(ResolvedAnchor)
    /// The stored range no longer matched (for example the extraction changed), but the exact text plus its stored
    /// context was found exactly once in the same asset. The UI can show it; the new range should be saved.
    case relocated(ResolvedAnchor)
    /// More than one place matches. UI: "Location needs review". The quotation is kept unchanged.
    case needsReview(candidateCount: Int)
    /// The text was not found. The quotation is kept unchanged; only its precise location is lost.
    case notFound
    /// The anchor belongs to a different file (digest differs). Cross-edition relocation always needs the user's
    /// confirmation, so nothing is resolved automatically.
    case differentAsset
}

public struct ResolvedAnchor {
    /// The rebuilt selection, one PDFKit selection per segment combined in document order.
    public var selection: PDFSelection
    /// Per segment, the scalar range the selection covers now.
    public var segments: [ResolvedSegment]
}

public struct ResolvedSegment {
    public var pageIndex: Int
    public var scalarRange: ScalarRange
    public var utf16Range: NSRange
    public var text: String
    /// Line rectangles PDFKit reports now, normalized to the anchor box (same convention as the anchor).
    public var lineRects: [NormalizedRect]
}

public enum PDFAnchorResolver {
    public static func resolve(_ anchor: PDFAnchor, in source: PDFSourceDocument, extraction: DocumentExtraction) -> AnchorResolution {
        guard anchor.assetSHA256 == source.sha256 else { return .differentAsset }
        if let exact = resolveExactly(anchor, in: source, extraction: extraction) {
            return .exact(exact)
        }
        return relocate(anchor, in: source, extraction: extraction)
    }

    /// Step 1: the original locator. Every segment must find identical page text (by digest) and identical text at
    /// its stored scalar range, and the combined selection must reproduce `exact_text` scalar for scalar.
    static func resolveExactly(_ anchor: PDFAnchor, in source: PDFSourceDocument, extraction: DocumentExtraction) -> ResolvedAnchor? {
        var resolved: [ResolvedSegment] = []
        for segment in anchor.segments {
            guard segment.textRange.unit == PDFAnchor.TextRange.unicodeScalarUnit,
                  let pageExtraction = extraction.page(segment.pageIndex),
                  pageExtraction.textSHA256 == segment.pageTextSHA256,
                  let pageText = pageExtraction.text
            else { return nil }
            guard let r = resolveSegment(range: segment.textRange.scalarRange, pageIndex: segment.pageIndex, pageText: pageText, in: source),
                  UnicodeOffsets.scalarsEqual(r.text, segment.text)
            else { return nil }
            resolved.append(r)
        }
        return combine(resolved, in: source, expecting: anchor.exactText)
    }

    /// Step 2: exact text plus stored context within the same asset. A segment matches where its text occurs with
    /// its stored prefix immediately before and suffix immediately after. Exactly one match per segment relocates;
    /// several matches need review; none is not found.
    static func relocate(_ anchor: PDFAnchor, in source: PDFSourceDocument, extraction: DocumentExtraction) -> AnchorResolution {
        var resolved: [ResolvedSegment] = []
        for segment in anchor.segments {
            var candidates: [(pageIndex: Int, range: ScalarRange, text: String)] = []
            for page in extraction.pages {
                guard let text = page.text else { continue }
                for range in occurrences(of: segment.text, prefix: segment.prefix, suffix: segment.suffix, in: text) {
                    candidates.append((page.pageIndex, range, text))
                }
            }
            if candidates.isEmpty {
                // Without its context the text alone is not proof of the same passage: any bare match needs review.
                let bare = extraction.pages.reduce(0) { n, page in
                    n + (page.text.map { occurrences(of: segment.text, prefix: "", suffix: "", in: $0).count } ?? 0)
                }
                return bare == 0 ? .notFound : .needsReview(candidateCount: bare)
            }
            if candidates.count > 1 { return .needsReview(candidateCount: candidates.count) }
            let c = candidates[0]
            guard let r = resolveSegment(range: c.range, pageIndex: c.pageIndex, pageText: c.text, in: source),
                  UnicodeOffsets.scalarsEqual(r.text, segment.text)
            else { return .notFound }
            resolved.append(r)
        }
        guard let combined = combine(resolved, in: source, expecting: anchor.exactText) else { return .notFound }
        return .relocated(combined)
    }

    static func resolveSegment(range: ScalarRange, pageIndex: Int, pageText: String, in source: PDFSourceDocument) -> ResolvedSegment? {
        guard let page = source.page(at: pageIndex),
              let utf16 = try? UnicodeOffsets.utf16Range(fromScalar: range, in: pageText),
              let selection = page.selection(for: utf16),
              let text = selection.string
        else { return nil }
        let box = page.bounds(for: PDFSourceDocument.anchorBox)
        guard let lines = try? PDFAnchorBuilder.lineRects(forUTF16Range: utf16, on: page, box: box) else { return nil }
        return ResolvedSegment(pageIndex: pageIndex, scalarRange: range, utf16Range: utf16, text: text, lineRects: lines)
    }

    static func combine(_ segments: [ResolvedSegment], in source: PDFSourceDocument, expecting exactText: String) -> ResolvedAnchor? {
        guard !segments.isEmpty else { return nil }
        let combined = PDFSelection(document: source.document)
        for s in segments {
            guard let page = source.page(at: s.pageIndex), let sel = page.selection(for: s.utf16Range) else { return nil }
            combined.add(sel)
        }
        guard let text = combined.string, UnicodeOffsets.scalarsEqual(text, exactText) else { return nil }
        return ResolvedAnchor(selection: combined, segments: segments)
    }

    /// Scalar ranges of `needle` in `haystack` that are immediately preceded by `prefix` and followed by `suffix`.
    /// Matching is scalar-exact (no case folding, no Unicode normalization), because a quotation must not be
    /// re-attached to text that merely looks equivalent.
    public static func occurrences(of needle: String, prefix: String, suffix: String, in haystack: String) -> [ScalarRange] {
        let h = Array(haystack.unicodeScalars)
        let n = Array(needle.unicodeScalars)
        let p = Array(prefix.unicodeScalars)
        let s = Array(suffix.unicodeScalars)
        guard !n.isEmpty, n.count <= h.count else { return [] }
        var out: [ScalarRange] = []
        var i = 0
        while i + n.count <= h.count {
            if h[i] == n[0], h[i..<(i + n.count)].elementsEqual(n) {
                let end = i + n.count
                let prefixOK = i >= p.count && h[(i - p.count)..<i].elementsEqual(p)
                let suffixOK = end + s.count <= h.count && h[end..<(end + s.count)].elementsEqual(s)
                if prefixOK && suffixOK { out.append(ScalarRange(start: i, end: end)) }
            }
            i += 1
        }
        return out
    }
}
