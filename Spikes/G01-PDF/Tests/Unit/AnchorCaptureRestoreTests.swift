import PDFAnchorKit
import PDFKit
import XCTest

/// A selection made the way a finger drag makes it: from one point to another in page space.
struct SampleSelection {
    var name: String
    var fixture: String
    var make: (PDFSourceDocument) -> PDFSelection?
}

@MainActor
enum Samples {
    /// Deterministic asset IDs so the evidence file is reproducible.
    static func assetID(_ fixture: String) -> UUID {
        let n = ["labels-multipage.pdf": 1, "two-column.pdf": 2, "rotated.pdf": 3, "unicode.pdf": 4, "mixed-scanned.pdf": 5][fixture] ?? 9
        return UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))!
    }

    static func drag(_ page: Int, _ from: CGPoint, _ to: CGPoint) -> (PDFSourceDocument) -> PDFSelection? {
        { source in source.page(at: page)?.selection(from: from, to: to) }
    }

    static let all: [SampleSelection] = [
        // Three lines on physical page 3, printed label "1" (the third line is short: it ends near x = 262).
        SampleSelection(name: "multiline", fixture: "labels-multipage.pdf",
                        make: drag(3, CGPoint(x: 200, y: 703), CGPoint(x: 150, y: 673))),
        // From the end of the left column into the right column.
        SampleSelection(name: "cross-column", fixture: "two-column.pdf",
                        make: drag(0, CGPoint(x: 150, y: 640), CGPoint(x: 400, y: 690))),
        SampleSelection(name: "rotate-0", fixture: "rotated.pdf",
                        make: drag(0, CGPoint(x: 300, y: 703), CGPoint(x: 200, y: 658))),
        SampleSelection(name: "rotate-90", fixture: "rotated.pdf",
                        make: drag(1, CGPoint(x: 300, y: 703), CGPoint(x: 200, y: 658))),
        SampleSelection(name: "rotate-180", fixture: "rotated.pdf",
                        make: drag(2, CGPoint(x: 300, y: 703), CGPoint(x: 200, y: 658))),
        SampleSelection(name: "rotate-270", fixture: "rotated.pdf",
                        make: drag(3, CGPoint(x: 300, y: 703), CGPoint(x: 200, y: 658))),
        SampleSelection(name: "rotate-90-inherited", fixture: "rotated.pdf",
                        make: drag(4, CGPoint(x: 300, y: 703), CGPoint(x: 200, y: 658))),
        SampleSelection(name: "rotate-270-offset-cropbox", fixture: "rotated.pdf",
                        make: drag(5, CGPoint(x: 250, y: 643), CGPoint(x: 150, y: 598))),
        // From near the end of physical page 3 to the start of physical page 4.
        SampleSelection(name: "multi-page", fixture: "labels-multipage.pdf", make: { source in
            source.document.selection(from: source.page(at: 3)!, atCharacterIndex: 300, to: source.page(at: 4)!, atCharacterIndex: 40)
        }),
        // Two lines with non-BMP scalars and a combining mark.
        SampleSelection(name: "unicode-multiline", fixture: "unicode.pdf",
                        make: drag(0, CGPoint(x: 130, y: 683), CGPoint(x: 160, y: 663))),
    ]
}

/// Brief items 2 and 3, T16: capture anchors from selections, store them Sylvia-side, restore them exactly.
@MainActor
final class AnchorCaptureRestoreTests: XCTestCase {
    /// Normalized coordinates are stored to 6 decimals; restored rectangles must match within this tolerance
    /// (0.0005 of a US Letter page is 0.31 pt horizontally, 0.40 pt vertically).
    static let geometryTolerance = 0.0005

    func capture(_ sample: SampleSelection) throws -> (PDFSourceDocument, DocumentExtraction, PDFSelection, PDFAnchor) {
        let source = try Fixture.open(sample.fixture)
        let extraction = PageTextExtractor.extract(source)
        let selection = try XCTUnwrap(sample.make(source), "\(sample.name): no selection")
        let anchor = try PDFAnchorBuilder.capture(selection: selection, in: source, extraction: extraction,
                                                  assetID: Samples.assetID(sample.fixture))
        return (source, extraction, selection, anchor)
    }

    func testCaptureAndRestoreEverySample() throws {
        var report = ["Anchor capture and restore, \(Evidence.environmentLabel)",
                      "tolerance for restored line rectangles: \(Self.geometryTolerance) (normalized to the CropBox)"]
        for sample in Samples.all {
            let (source, extraction, selection, anchor) = try capture(sample)
            let exact = try XCTUnwrap(selection.string)
            XCTAssertTrue(UnicodeOffsets.scalarsEqual(anchor.exactText, exact), sample.name)
            XCTAssertEqual(anchor.kind, "pdf")
            XCTAssertEqual(anchor.assetSHA256, source.sha256)
            XCTAssertFalse(anchor.segments.isEmpty)
            for segment in anchor.segments {
                XCTAssertEqual(segment.textRange.unit, "unicode_scalar")
                XCTAssertEqual(segment.pageBox.name, "crop")
                XCTAssertFalse(segment.lineRects.isEmpty, "\(sample.name): every segment has line rectangles")
                for r in segment.lineRects {
                    XCTAssertTrue((0...1).contains(r.x) && (0...1).contains(r.y) && r.width > 0 && r.height > 0
                                  && r.x + r.width <= 1.000001 && r.y + r.height <= 1.000001, "\(sample.name): \(r)")
                }
                let pageText = try XCTUnwrap(extraction.page(segment.pageIndex)?.text)
                XCTAssertTrue(UnicodeOffsets.scalarsEqual(try UnicodeOffsets.substring(pageText, scalars: segment.textRange.scalarRange), segment.text))
                // The rebuilt-from-range lines equal the lines of the user's own selection on that page.
                if anchor.segments.filter({ $0.pageIndex == segment.pageIndex }).count == 1 {
                    let page = try XCTUnwrap(source.page(at: segment.pageIndex))
                    let box = page.bounds(for: .cropBox)
                    let original = try selection.selectionsByLine()
                        .filter { $0.pages.contains(page) }
                        .map { $0.bounds(for: page) }
                        .filter { $0.width > 0 && $0.height > 0 }
                        .map { try PageGeometry.normalize($0, in: box) }
                    XCTAssertEqual(original, segment.lineRects, "\(sample.name): line rects from the range differ from the selection's lines")
                }
            }
            // Each sample has one segment per page, and PDFKit joins a selection's pages with "\n". (Several pieces on one
            // page are composed differently: ComposedSelectionTests.)
            XCTAssertEqual(Set(anchor.segments.map(\.pageIndex)).count, anchor.segments.count, "\(sample.name): one segment per page")
            XCTAssertTrue(UnicodeOffsets.scalarsEqual(anchor.segments.map(\.text).joined(separator: "\n"), anchor.exactText), sample.name)

            // Store-and-reload through JSON, then restore against a freshly opened copy of the document.
            let decoded = try AnchorJSON.decoder().decode(PDFAnchor.self, from: AnchorJSON.encoder().encode(anchor))
            XCTAssertEqual(decoded, anchor)
            let reopened = try Fixture.open(sample.fixture)
            let reExtraction = PageTextExtractor.extract(reopened)
            guard case .exact(let resolved) = PDFAnchorResolver.resolve(decoded, in: reopened, extraction: reExtraction) else {
                XCTFail("\(sample.name): not restored exactly")
                continue
            }
            XCTAssertTrue(UnicodeOffsets.scalarsEqual(try XCTUnwrap(resolved.selection.string), anchor.exactText), "\(sample.name): restored text differs")
            var worst = 0.0
            for (stored, restored) in zip(anchor.segments, resolved.segments) {
                XCTAssertEqual(stored.pageIndex, restored.pageIndex)
                XCTAssertEqual(stored.textRange.scalarRange, restored.scalarRange)
                XCTAssertEqual(stored.lineRects.count, restored.lineRects.count, sample.name)
                for (a, b) in zip(stored.lineRects, restored.lineRects) {
                    worst = max(worst, a.maxDeviation(from: b))
                }
            }
            XCTAssertLessThanOrEqual(worst, Self.geometryTolerance, sample.name)
            let pages = anchor.segments.map { "p\($0.pageIndex)/\($0.pageLabel ?? "-")/rot\($0.pageRotation)/\($0.lineRects.count) lines" }
            report.append("\(sample.name) [\(sample.fixture)]: \(anchor.segments.count) segment(s) \(pages.joined(separator: ", ")); "
                          + "\(UnicodeOffsets.scalarCount(anchor.exactText)) scalars / \(anchor.exactText.utf16.count) UTF-16 units; "
                          + "restored exact, identical text, max line-rect deviation \(worst)")
        }
        Evidence.write("anchor-capture-restore.txt", report.joined(separator: "\n") + "\n")
    }

    func testSpecificFacts() throws {
        // Multiline: physical index and printed label differ.
        let (_, _, _, multiline) = try capture(Samples.all[0])
        XCTAssertEqual(multiline.segments.count, 1)
        XCTAssertEqual(multiline.segments[0].pageIndex, 3)
        XCTAssertEqual(multiline.segments[0].pageLabel, "1")
        XCTAssertEqual(multiline.segments[0].lineRects.count, 3)
        // One rectangle per line: the quotation has one line break fewer than it has lines.
        XCTAssertEqual(multiline.segments[0].lineRects.count, multiline.exactText.split(separator: "\n", omittingEmptySubsequences: false).count)

        // Cross-column: one contiguous range in PDFKit's column order, with lines in both columns.
        let (_, _, _, cross) = try capture(Samples.all[1])
        XCTAssertEqual(cross.segments.count, 1)
        XCTAssertNil(cross.segments[0].pageLabel)
        let xs = Set(cross.segments[0].lineRects.map { ($0.x * 612).rounded() })
        XCTAssertTrue(xs.contains(72) && xs.contains(324), "lines start in both columns: \(xs)")
        XCTAssertTrue(cross.exactText.contains("closed books.\nRight column."))

        // Rotation values and the offset crop box.
        let expected = [("rotate-0", 0), ("rotate-90", 90), ("rotate-180", 180), ("rotate-270", 270),
                        ("rotate-90-inherited", 90), ("rotate-270-offset-cropbox", 270)]
        for (name, rotation) in expected {
            let sample = try XCTUnwrap(Samples.all.first { $0.name == name })
            let (_, _, _, anchor) = try capture(sample)
            XCTAssertEqual(anchor.segments.map(\.pageRotation), [rotation], name)
            XCTAssertGreaterThanOrEqual(anchor.segments[0].lineRects.count, 2, name)
        }
        let (_, _, _, offset) = try capture(try XCTUnwrap(Samples.all.first { $0.name == "rotate-270-offset-cropbox" }))
        XCTAssertEqual(offset.segments[0].pageBox.rect, [20, 30, 520, 670])

        // Multi-page: one segment per page, labels "1" and "2".
        let (_, _, _, multiPage) = try capture(try XCTUnwrap(Samples.all.first { $0.name == "multi-page" }))
        XCTAssertEqual(multiPage.segments.map(\.pageIndex), [3, 4])
        XCTAssertEqual(multiPage.segments.map(\.pageLabel), ["1", "2"])
    }

    func testHighlightsAreStoredSylviaSideAndTheFileIsUnchanged() throws {
        var lines = ["Original bytes unchanged, \(Evidence.environmentLabel)"]
        let storeDir = FileManager.default.temporaryDirectory.appendingPathComponent("g01-store-\(UUID().uuidString)")
        let store = HighlightStore(directory: storeDir)
        for fixture in ["labels-multipage.pdf", "two-column.pdf", "rotated.pdf", "unicode.pdf"] {
            let copy = try Fixture.copy(fixture)
            let before = try PDFSourceDocument.sha256OfFile(at: copy)
            let attributesBefore = try FileManager.default.attributesOfItem(atPath: copy.path)
            let source = try PDFSourceDocument.open(url: copy)
            let extraction = PageTextExtractor.extract(source)
            let annotationCounts = (0..<source.document.pageCount).map { source.page(at: $0)!.annotations.count }

            var anchors: [PDFAnchor] = []
            for sample in Samples.all where sample.fixture == fixture {
                let selection = try XCTUnwrap(sample.make(source))
                let anchor = try PDFAnchorBuilder.capture(selection: selection, in: source, extraction: extraction)
                try store.append(HighlightRecord(anchor: anchor))
                anchors.append(anchor)
            }
            XCTAssertFalse(anchors.isEmpty)
            // Draw the overlays offscreen and in a PDFView, exactly as the reader would.
            HighlightOverlay.apply(anchors, to: source.document)
            for i in 0..<source.document.pageCount { _ = PageRenderer.render(source.page(at: i)!, scale: 1) }
            let window = makeHostWindow()
            let view = PDFView(frame: window.bounds)
            window.rootViewController?.view.addSubview(view)
            view.document = source.document
            view.layoutIfNeeded()
            spinRunLoop(seconds: 0.3)
            window.isHidden = true

            let after = try PDFSourceDocument.sha256OfFile(at: copy)
            let attributesAfter = try FileManager.default.attributesOfItem(atPath: copy.path)
            XCTAssertEqual(before.0, after.0, "\(fixture): file bytes changed")
            XCTAssertEqual(before.1, after.1)
            XCTAssertEqual(attributesBefore[.modificationDate] as? Date, attributesAfter[.modificationDate] as? Date)
            XCTAssertEqual(annotationCounts, (0..<source.document.pageCount).map { source.page(at: $0)!.annotations.count },
                           "\(fixture): overlays must not be PDF annotations")
            let stored = try store.load(assetSHA256: source.sha256)
            XCTAssertEqual(stored.map(\.anchor), anchors)
            lines.append("\(fixture): sha256 before \(before.0) after \(after.0), \(before.1) bytes; "
                         + "\(anchors.count) highlight(s) stored in \(storeDir.lastPathComponent)/\(source.sha256.prefix(12))….highlights.json; "
                         + "annotations per page unchanged \(annotationCounts)")
        }
        Evidence.write("original-bytes-unchanged.txt", lines.joined(separator: "\n") + "\n")
    }

    func testReanchoringFallbacks() throws {
        let (source, extraction, _, anchor) = try capture(Samples.all[0])

        // Extraction drift: the stored page digest no longer matches, so step 1 fails; text plus context relocates.
        var drifted = anchor
        drifted.segments[0].pageTextSHA256 = String(repeating: "0", count: 64)
        drifted.segments[0].textRange.start += 5
        drifted.segments[0].textRange.end += 5
        guard case .relocated(let relocated) = PDFAnchorResolver.resolve(drifted, in: source, extraction: extraction) else {
            return XCTFail("expected relocation by exact text plus context")
        }
        XCTAssertEqual(relocated.segments[0].scalarRange, anchor.segments[0].textRange.scalarRange)

        // Ambiguous: the text alone occurs on several pages and the context no longer matches.
        var ambiguous = anchor
        ambiguous.segments[0].pageTextSHA256 = String(repeating: "0", count: 64)
        ambiguous.segments[0].text = "the"
        ambiguous.segments[0].prefix = "zzz"
        ambiguous.exactText = "the"
        guard case .needsReview(let n) = PDFAnchorResolver.resolve(ambiguous, in: source, extraction: extraction) else {
            return XCTFail("expected Location needs review")
        }
        XCTAssertGreaterThan(n, 1)

        // Missing text: not found, and the anchor (with its quotation) is untouched by resolution.
        var missing = anchor
        missing.segments[0].pageTextSHA256 = String(repeating: "0", count: 64)
        missing.segments[0].text = "words that are not in this document"
        missing.exactText = missing.segments[0].text
        let before = missing
        guard case .notFound = PDFAnchorResolver.resolve(missing, in: source, extraction: extraction) else {
            return XCTFail("expected not found")
        }
        XCTAssertEqual(missing, before)

        // Different asset: never relocated automatically.
        var other = anchor
        other.assetSHA256 = String(repeating: "a", count: 64)
        guard case .differentAsset = PDFAnchorResolver.resolve(other, in: source, extraction: extraction) else {
            return XCTFail("expected differentAsset")
        }
    }

    func testWriteAnchorSamples() throws {
        var samples: [[String: Any]] = []
        for sample in Samples.all {
            let (source, _, _, anchor) = try capture(sample)
            let json = try JSONSerialization.jsonObject(with: AnchorJSON.encoder().encode(anchor))
            samples.append(["name": sample.name, "fixture": "Spikes/G01-PDF/Fixtures/\(sample.fixture)",
                            "fixture_sha256": source.sha256, "anchor": json])
        }
        let (_, _, _, first) = try capture(Samples.all[0])
        let anchorJSON = try JSONSerialization.jsonObject(with: AnchorJSON.encoder().encode(first))
        let envelope: [String: Any] = [
            "schema_version": 1,
            "capture_id": "4d76e6bc-9e23-4d23-8b1a-1b3b8c487fe9",
            "work_id": "e8b1c045-32a7-47bc-9f0c-5f6788c405bb",
            "edition_id": "f95a48f1-c7b9-4bcb-8886-7728e490c5c2",
            "kind": "text_quote",
            "quoted_text": first.exactText,
            "source_snapshot": ["title": "Sylvia G0.1 PDF fixture: page labels", "author_display": "Fixture generator",
                                "location_label": "Page 1", "source_kind": "local_pdf"],
            "anchors": [anchorJSON],
            "created_at": "2026-10-06T00:00:00Z",
            "revision": 1,
        ]
        let document: [String: Any] = [
            "description": "Real PDF anchors captured by AnchorCaptureRestoreTests.testWriteAnchorSamples from the committed G0.1 fixtures, plus the proposed portable PDF anchor envelope. Generated; do not edit by hand.",
            "environment": Evidence.environmentLabel,
            "proposed_pdf_anchor": Self.proposedEnvelopeDescription,
            "capture_envelope_example": envelope,
            "samples": samples,
        ]
        let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        Evidence.write("anchor-samples.json", String(decoding: data, as: UTF8.self) + "\n")
    }

    static let proposedEnvelopeDescription: [String: Any] = [
        "version": "integer, 1",
        "kind": "\"pdf\"",
        "asset_id": "UUID of the stored PDF asset, or null in fixtures",
        "asset_sha256": "lowercase hex SHA-256 of the PDF bytes; the anchor is exact only for this file",
        "exact_text": "the quotation exactly as selected (scalar-exact, never normalized). With one segment it equals that segment's text; with several it is the reader's own composition of the pieces (PDFKit: pages joined by \\n, pieces on one page next to each other, a piece ending at a line's end keeping that break when another follows on its page), so it is not the segments' texts joined by one separator. Capture stores an anchor only if its segments, rebuilt as the resolver rebuilds them, give back exactly this text",
        "extraction": "{extractor, adapter_version, platform}: which text extraction the offsets index into",
        "segments[]": [
            "page_index": "zero-based physical page index",
            "page_label": "printed label from /PageLabels, or null when the file supplies none (never invented)",
            "page_rotation": "0, 90, 180 or 270: the page's /Rotate (inherited), clockwise for display",
            "page_box": "{name: \"crop\", rect: [x, y, w, h]} in PDF user-space points; rectangles are normalized to it",
            "text": "this segment's text, equal to the page text at text_range",
            "text_range": "{unit: \"unicode_scalar\", start, end}: half-open range into the page's extracted text",
            "prefix": "up to 32 scalars of page text before the segment",
            "suffix": "up to 32 scalars of page text after the segment",
            "line_rects": "[[x, y, w, h], ...] one per line, fractions of page_box, unrotated page space (origin lower-left, y up), 6 decimals",
            "page_text_sha256": "SHA-256 of the page text's UTF-8 bytes, to detect extraction drift before trusting text_range",
        ],
        "reader_locator": "adapter-opaque: {adapter: \"pdfkit\", utf16_ranges: [{page_index, location, length}]}; other platforms ignore it",
        "display_mapping": "a client draws a rect r on a page shown rotated by R clockwise as: R=0 (x, 1-y-h, w, h); R=90 (y, x, h, w); R=180 (1-x-w, y, w, h); R=270 (1-y-h, 1-x-w, h, w), normalized to the displayed page with origin top-left",
    ]
}
