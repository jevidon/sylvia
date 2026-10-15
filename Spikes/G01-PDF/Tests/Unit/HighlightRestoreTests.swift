import PDFAnchorKit
import PDFKit
import XCTest

/// Plan 9.4 ("survives an extraction-cache rebuild") through the restore path the harness uses on every open
/// (`HighlightRestorer`, called by `ReaderViewController.restoreHighlights`): a record whose page text changed since
/// capture relocates by exact text plus context, is drawn at its new location (not at its stale rectangles), and its
/// rebuilt anchor is saved, so the next open restores it exactly. Records that need review or are not found are not
/// drawn and stay byte-for-byte as stored. The same path on screen: `HighlightUITests.testRelocatedHighlightIsDrawnAndSaved`.
@MainActor
final class HighlightRestoreTests: XCTestCase {
    /// The same simulated drift the harness applies with `-seedDrift`: page-text digest mismatch, range 5 scalars
    /// later, line rectangles 0.05 of the page lower.
    static func drift(_ anchor: PDFAnchor) -> PDFAnchor {
        var drifted = anchor
        for i in drifted.segments.indices {
            drifted.segments[i].pageTextSHA256 = String(repeating: "0", count: 64)
            drifted.segments[i].textRange.start += 5
            drifted.segments[i].textRange.end += 5
            drifted.segments[i].lineRects = drifted.segments[i].lineRects.map {
                NormalizedRect(x: $0.x, y: $0.y - 0.05, width: $0.width, height: $0.height)
            }
        }
        return drifted
    }

    func testRelocatedHighlightIsDrawnAndItsNewLocationSaved() throws {
        let source = try Fixture.open("labels-multipage.pdf")
        let extraction = PageTextExtractor.extract(source)
        let assetID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")
        // The multiline sample (page index 3, three lines) and a one-line passage on page index 4.
        let original = try PDFAnchorBuilder.anchor(forScalarRange: ScalarRange(start: 48, end: 193), onPage: 3,
                                                   in: source, extraction: extraction, assetID: assetID)
        let other = try PDFAnchorBuilder.anchor(forScalarRange: ScalarRange(start: 0, end: 40), onPage: 4,
                                                in: source, extraction: extraction, assetID: assetID)
        XCTAssertEqual(original.segments.first?.lineRects.count, 3)

        var ambiguous = original
        ambiguous.segments[0].pageTextSHA256 = String(repeating: "0", count: 64)
        ambiguous.segments[0].text = "the"
        ambiguous.segments[0].prefix = "zzz"
        ambiguous.exactText = "the"
        var missing = original
        missing.segments[0].pageTextSHA256 = String(repeating: "0", count: 64)
        missing.segments[0].text = "words that are not in this document"
        missing.exactText = missing.segments[0].text

        let drifted = Self.drift(original)
        // Whole seconds: the store writes ISO 8601 dates, so loaded records compare equal to these.
        let created = Date(timeIntervalSince1970: 1_791_000_000)
        let stored = [other, drifted, ambiguous, missing].map { HighlightRecord(createdAt: created, anchor: $0) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("restore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HighlightStore(directory: directory)
        try store.save(stored, assetSHA256: source.sha256)

        // First open after the change: one exact, one relocated, one needs review, one not found.
        let loaded = try store.load(assetSHA256: source.sha256)
        XCTAssertEqual(loaded, stored)
        let first = HighlightRestorer.restore(loaded, in: source, extraction: extraction)
        XCTAssertEqual([first.exact, first.relocated, first.relocationNotRebuilt, first.needsReview, first.notFound], [1, 1, 0, 1, 1])
        XCTAssertTrue(first.needsSave)
        // The relocated record keeps its identity and quotation; its anchor is rebuilt at the current location,
        // identical to a fresh capture of the same passage (range, page digest, context, line rectangles).
        let relocated = first.records[1]
        XCTAssertEqual(relocated.id, stored[1].id)
        XCTAssertEqual(relocated.createdAt, stored[1].createdAt)
        XCTAssertEqual(relocated.anchor, original, "the rebuilt anchor equals a fresh capture of the same passage")
        XCTAssertNotEqual(relocated.anchor.segments[0].lineRects, drifted.segments[0].lineRects)
        // Records that need review or are not found are kept exactly as stored (the quotation is never lost).
        XCTAssertEqual(first.records[0], stored[0])
        XCTAssertEqual(first.records[2], stored[2])
        XCTAssertEqual(first.records[3], stored[3])
        XCTAssertEqual(first.drawable, [other, original])

        // Drawing: page 3 carries the relocated passage's current rectangles, not the stale stored ones.
        HighlightOverlay.apply(first.drawable, to: source.document)
        let page3 = try XCTUnwrap(source.page(at: 3) as? OverlayPage)
        let box = page3.bounds(for: PDFSourceDocument.anchorBox)
        let current = HighlightOverlay.userSpaceRects(for: original, pageIndex: 3, box: box)
        let stale = HighlightOverlay.userSpaceRects(for: drifted, pageIndex: 3, box: box)
        XCTAssertEqual(page3.highlightRects, current)
        XCTAssertNotEqual(page3.highlightRects, stale)
        XCTAssertEqual(HighlightOverlay.highlightedPageIndices(in: source.document), [3, 4])

        // The harness saves the outcome; the next open restores both drawable records exactly and saves nothing.
        try store.save(first.records, assetSHA256: source.sha256)
        let reopened = try PDFSourceDocument.open(url: Fixture.url("labels-multipage.pdf"))
        let second = HighlightRestorer.restore(try store.load(assetSHA256: reopened.sha256), in: reopened,
                                               extraction: PageTextExtractor.extract(reopened))
        XCTAssertEqual([second.exact, second.relocated, second.relocationNotRebuilt, second.needsReview, second.notFound], [2, 0, 0, 1, 1])
        XCTAssertFalse(second.needsSave)
        XCTAssertEqual(second.records, first.records)

        func shape(_ a: PDFAnchor) -> String {
            a.segments.map { s in
                "page \(s.pageIndex) range \(s.textRange.start)..<\(s.textRange.end) digest \(s.pageTextSHA256.prefix(12)) lines "
                    + s.lineRects.map { String(format: "[%.6f,%.6f,%.6f,%.6f]", $0.x, $0.y, $0.width, $0.height) }.joined(separator: " ")
            }.joined(separator: "; ")
        }
        Evidence.write("highlight-restore-relocated.txt", """
            HighlightRestorer (the harness's restore path) on labels-multipage.pdf, \(Evidence.environmentLabel)
            stored record 1 (simulated extraction drift): \(shape(drifted))
            first open: exact \(first.exact), relocated \(first.relocated), needs review \(first.needsReview), not found \(first.notFound); needsSave \(first.needsSave)
            relocated record rebuilt: \(shape(relocated.anchor)); equals a fresh capture: \(relocated.anchor == original); same id and quotation: \(relocated.id == stored[1].id && relocated.anchor.exactText == stored[1].anchor.exactText)
            page 3 overlay rectangles (user space) = current passage: \(page3.highlightRects == current); = stale stored rectangles: \(page3.highlightRects == stale)
            review and not-found records unchanged: \(first.records[2] == stored[2] && first.records[3] == stored[3])
            after saving and reopening: exact \(second.exact), relocated \(second.relocated), needs review \(second.needsReview), not found \(second.notFound); needsSave \(second.needsSave)

            """)
    }
}
