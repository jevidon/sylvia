import Foundation
import PDFKit

/// The result of re-anchoring a file's stored highlight records when it is opened (ADR-0005 "Restoring").
public struct HighlightRestoreOutcome {
    /// Anchors to draw: exact ones as stored, relocated ones rebuilt at their new location.
    public var drawable: [PDFAnchor]
    /// Every record, in stored order. A relocated record carries its rebuilt anchor (same id, creation date, asset ID
    /// and quotation); every other record is unchanged.
    public var records: [HighlightRecord]
    public var exact = 0
    /// Relocated by exact text plus context and rebuilt; their new location should be saved (`needsSave`).
    public var relocated = 0
    /// Relocated, but a fresh anchor could not be built from the relocated selection; not drawn, record unchanged.
    public var relocationNotRebuilt = 0
    /// "Location needs review": not drawn, record unchanged.
    public var needsReview = 0
    /// Not found, or a different asset: not drawn, record unchanged (the quotation is never deleted).
    public var notFound = 0

    /// True when at least one record was relocated and rebuilt, so `records` differs from what was loaded.
    public var needsSave: Bool { relocated > 0 }
}

/// Re-anchors stored records against an opened file in the order of plan 7.5 and returns what to draw and what to
/// save. The reader draws `drawable` and, when `needsSave`, writes `records` back, so a relocated highlight is shown
/// at once and restores exactly on the next open.
public enum HighlightRestorer {
    public static func restore(_ records: [HighlightRecord], in source: PDFSourceDocument,
                               extraction: DocumentExtraction) -> HighlightRestoreOutcome {
        var outcome = HighlightRestoreOutcome(drawable: [], records: records)
        for (i, record) in records.enumerated() {
            switch PDFAnchorResolver.resolve(record.anchor, in: source, extraction: extraction) {
            case .exact:
                outcome.exact += 1
                outcome.drawable.append(record.anchor)
            case .relocated(let resolved):
                guard let rebuilt = rebuild(record.anchor, from: resolved, in: source, extraction: extraction) else {
                    outcome.relocationNotRebuilt += 1
                    continue
                }
                outcome.relocated += 1
                outcome.records[i].anchor = rebuilt
                outcome.drawable.append(rebuilt)
            case .needsReview:
                outcome.needsReview += 1
            case .notFound, .differentAsset:
                outcome.notFound += 1
            }
        }
        return outcome
    }

    /// A fresh anchor for the relocated selection, built by the same capture path as a new highlight (current page
    /// text digests, scalar ranges, context and line rectangles), keeping the stored asset ID. Accepted only if it
    /// quotes exactly the stored text and covers exactly the resolver's relocated ranges.
    static func rebuild(_ stored: PDFAnchor, from resolved: ResolvedAnchor, in source: PDFSourceDocument,
                        extraction: DocumentExtraction) -> PDFAnchor? {
        guard let anchor = try? PDFAnchorBuilder.capture(selection: resolved.selection, in: source, extraction: extraction,
                                                         assetID: stored.assetID),
              UnicodeOffsets.scalarsEqual(anchor.exactText, stored.exactText),
              anchor.segments.map(\.pageIndex) == resolved.segments.map(\.pageIndex),
              anchor.segments.map(\.textRange.scalarRange) == resolved.segments.map(\.scalarRange)
        else { return nil }
        return anchor
    }
}
