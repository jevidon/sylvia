import PDFAnchorKit
import PDFKit
import XCTest

/// A selection whose `string` is not the text its ranges hold: the base selection's ranges with another quotation.
/// No PDFKit selection seen in this spike behaves like this; it stands in for any selection whose stored ranges could
/// not give back its quotation, so the refusal in `PDFAnchorBuilder.capture` can be tested.
final class MisquotingSelection: PDFSelection {
    let quotation: String

    init(document: PDFDocument, pieces: [PDFSelection], quotation: String) {
        self.quotation = quotation
        super.init(document: document)
        for piece in pieces { add(piece) }
    }

    override var string: String? { quotation }
}

/// Brief items 2 and 3 for selections made of several pieces (`PDFSelection.add`, as a reader composes a selection
/// from separate ranges), and for a selection across two pages that ends at a line's end.
///
/// PDFKit composes such a selection's text itself, and not with one fixed separator. In the shapes below (iOS 26.5):
/// pieces on one page come out next to each other with nothing between them; a piece that ends at a line's end keeps
/// that line break when another piece follows on its page (PDFKit's range for the piece covers the break, and the
/// break is dropped only at the end); pages are joined with one "\n"; pieces that touch or overlap become one range;
/// pieces are ordered by page and position whatever order they were added in. The anchor's segments exclude trailing
/// breaks (`LineEndSelectionTests`), so `exact_text` is not the segments' texts joined by a separator.
/// `PDFAnchorBuilder` therefore checks a new anchor by restoring it: its ranges, rebuilt the way `PDFAnchorResolver`
/// rebuilds a stored anchor, must give back the quotation. The gate's review (R4-01) found that the earlier check,
/// which joined the segments with "\n", refused selections with two or more pieces on a page; the evidence says for
/// each shape whether that check would have accepted it.
@MainActor
final class ComposedSelectionTests: XCTestCase {
    struct Shape {
        var name: String
        /// (page index, UTF-16 location, length) of each piece, added in this order.
        var pieces: [(page: Int, location: Int, length: Int)]
        /// The quotation PDFKit gives for the composed selection.
        var expectedText: String
        /// The stored segments: page index and scalar range (all page text here is ASCII, so UTF-16 and scalars agree).
        var expectedSegments: [(page: Int, start: Int, end: Int)]
    }

    /// labels-multipage.pdf, page index 3 ("Body, physical page 4\nThe pond in winter ... the water\nstill moves, ...
    /// A walker\nwho stops ...") and page index 4 ("Body, physical page 5\nThe heron ...").
    static let shapes: [Shape] = [
        Shape(name: "two pieces on one page, two lines apart", pieces: [(3, 22, 10), (3, 120, 10)],
              expectedText: "The pond iturning ov", expectedSegments: [(3, 22, 32), (3, 120, 130)]),
        Shape(name: "two pieces on one line", pieces: [(3, 22, 5), (3, 40, 5)],
              expectedText: "The p keep", expectedSegments: [(3, 22, 27), (3, 40, 45)]),
        Shape(name: "three pieces on one page", pieces: [(3, 22, 5), (3, 60, 5), (3, 120, 5)],
              expectedText: "The pel. Uturni", expectedSegments: [(3, 22, 27), (3, 60, 65), (3, 120, 125)]),
        Shape(name: "pieces added in reverse order", pieces: [(3, 120, 10), (3, 22, 10)],
              expectedText: "The pond iturning ov", expectedSegments: [(3, 22, 32), (3, 120, 130)]),
        Shape(name: "a middle piece that ends at a line's end", pieces: [(3, 22, 5), (3, 80, 18), (3, 180, 5)],
              expectedText: "The pgrey ice the water\n stop", expectedSegments: [(3, 22, 27), (3, 80, 98), (3, 180, 185)]),
        Shape(name: "two pieces, each ending at a line's end", pieces: [(3, 80, 18), (3, 157, 20)],
              expectedText: "grey ice the water\nthe night. A walker", expectedSegments: [(3, 80, 98), (3, 157, 176)]),
        Shape(name: "two pieces on one page, then one on the next page", pieces: [(3, 22, 5), (3, 40, 5), (4, 0, 10)],
              expectedText: "The p keep\nBody, phys", expectedSegments: [(3, 22, 27), (3, 40, 45), (4, 0, 10)]),
        Shape(name: "a piece that ends at a line's end, then one on the next page", pieces: [(3, 22, 76), (4, 0, 10)],
              expectedText: "The pond in winter keeps its own counsel. Under a skin of grey ice the water\nBody, phys",
              expectedSegments: [(3, 22, 98), (4, 0, 10)]),
        Shape(name: "pages added in reverse order", pieces: [(4, 0, 10), (3, 22, 10)],
              expectedText: "The pond i\nBody, phys", expectedSegments: [(3, 22, 32), (4, 0, 10)]),
        Shape(name: "two pieces that touch (PDFKit merges them)", pieces: [(3, 22, 10), (3, 32, 10)],
              expectedText: "The pond in winter k", expectedSegments: [(3, 22, 42)]),
        Shape(name: "two pieces that overlap (PDFKit merges them)", pieces: [(3, 22, 10), (3, 27, 10)],
              expectedText: "The pond in win", expectedSegments: [(3, 22, 37)]),
    ]

    func describe(_ resolution: AnchorResolution) -> String {
        switch resolution {
        case .exact: return "exact"
        case .relocated: return "relocated"
        case .needsReview(let n): return "location needs review (\(n) candidates)"
        case .notFound: return "not found"
        case .differentAsset: return "different asset"
        }
    }

    /// PDFKit's ranges for a selection, page by page, marking a range whose last character is a line break.
    func ranges(_ selection: PDFSelection, in source: PDFSourceDocument) -> String {
        selection.pages.map { page in
            let units = (page.string ?? "") as NSString
            let pieces = (0..<selection.numberOfTextRanges(on: page)).map { i -> String in
                let r = selection.range(at: i, on: page)
                let breakAtEnd = r.length > 0 && NSMaxRange(r) <= units.length && units.character(at: NSMaxRange(r) - 1) == 0x0A
                return "\(r.location)+\(r.length)" + (breakAtEnd ? " (ends with the line break)" : "")
            }
            return "page \(source.index(of: page)) [\(pieces.joined(separator: ", "))]"
        }.joined(separator: "; ")
    }

    func segments(_ anchor: PDFAnchor) -> String {
        anchor.segments.map { "page \($0.pageIndex) \($0.textRange.start)..<\($0.textRange.end)" }.joined(separator: ", ")
    }

    /// Restores an anchor after a JSON round trip against a freshly opened copy of the fixture.
    func restoreAfterRoundTrip(_ anchor: PDFAnchor, fixture: String) throws -> (AnchorResolution, String?) {
        let decoded = try AnchorJSON.decoder().decode(PDFAnchor.self, from: AnchorJSON.encoder().encode(anchor))
        XCTAssertEqual(decoded, anchor)
        let reopened = try Fixture.open(fixture)
        let resolution = PDFAnchorResolver.resolve(decoded, in: reopened, extraction: PageTextExtractor.extract(reopened))
        if case .exact(let resolved) = resolution { return (resolution, resolved.selection.string) }
        return (resolution, nil)
    }

    func testComposedSelectionsCaptureAndRestoreExactly() throws {
        let fixture = "labels-multipage.pdf"
        let source = try Fixture.open(fixture)
        let extraction = PageTextExtractor.extract(source)
        var report = ["Selections composed of several pieces (PDFSelection.add) on \(fixture): capture, JSON round trip, fresh open, "
                      + "\(Evidence.environmentLabel)"]
        var refusedByEarlierCheck = 0
        var samples: [[String: Any]] = []
        for shape in Self.shapes {
            let selection = PDFSelection(document: source.document)
            for piece in shape.pieces {
                let page = try XCTUnwrap(source.page(at: piece.page))
                selection.add(try XCTUnwrap(page.selection(for: NSRange(location: piece.location, length: piece.length))))
            }
            let text = try XCTUnwrap(selection.string)
            // PDFKit's composition for this shape (an observation, pinned so a change in PDFKit shows here).
            XCTAssertEqual(text, shape.expectedText, "\(shape.name): PDFKit's text for the composed selection")
            let anchor = try PDFAnchorBuilder.capture(selection: selection, in: source, extraction: extraction,
                                                      assetID: Samples.assetID(fixture))
            // The stored anchor as JSON, for the anchor contract's checks and fixtures (M0 final review R1-02: the
            // contract's rule A3 refused these, and no sample showed it).
            samples.append(["name": shape.name, "fixture": "Spikes/G01-PDF/Fixtures/\(fixture)", "fixture_sha256": source.sha256,
                            "anchor": try JSONSerialization.jsonObject(with: AnchorJSON.encoder().encode(anchor))])
            XCTAssertTrue(UnicodeOffsets.scalarsEqual(anchor.exactText, text), shape.name)
            XCTAssertEqual(anchor.segments.map { [$0.pageIndex, $0.textRange.start, $0.textRange.end] },
                           shape.expectedSegments.map { [$0.page, $0.start, $0.end] }, "\(shape.name): stored segments")
            for segment in anchor.segments {
                XCTAssertFalse(segment.text.unicodeScalars.last == "\n", "\(shape.name): no trailing line break is stored")
            }
            let (resolution, restored) = try restoreAfterRoundTrip(anchor, fixture: fixture)
            if case .exact = resolution {
                XCTAssertTrue(UnicodeOffsets.scalarsEqual(try XCTUnwrap(restored), text), "\(shape.name): restored text")
            } else {
                XCTFail("\(shape.name): \(describe(resolution)), expected exact")
            }
            // The check this replaced: the segments' texts joined by "\n" had to equal the quotation.
            let earlier = UnicodeOffsets.scalarsEqual(anchor.segments.map(\.text).joined(separator: "\n"), text)
            if !earlier { refusedByEarlierCheck += 1 }
            report.append("\(shape.name): PDFKit ranges \(ranges(selection, in: source)); text \"\(esc(text))\"; stored segments "
                          + "\(segments(anchor)); restored: \(describe(resolution)); the earlier \"\\n\"-join check would have "
                          + (earlier ? "accepted it" : "refused it"))
        }
        // Every shape with two or more separate pieces on one page except "two pieces, each ending at a line's end",
        // where the "\n" it expected happens to be the line break PDFKit keeps after the first piece.
        XCTAssertEqual(refusedByEarlierCheck, 6, "the shapes the earlier check refused (R4-01)")
        report.append("\(refusedByEarlierCheck) of \(Self.shapes.count) shapes would have been refused by the earlier check; all \(Self.shapes.count) restore exactly now")
        Evidence.write("anchor-composed-selections.txt", report.joined(separator: "\n") + "\n")
        let document: [String: Any] = [
            "description": "Real PDF anchors of selections composed of several pieces (PDFSelection.add), one per shape of ComposedSelectionTests, each captured and restored exactly by testComposedSelectionsCaptureAndRestoreExactly. Generated; do not edit by hand.",
            "environment": Evidence.environmentLabel,
            "samples": samples,
        ]
        let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        Evidence.write("anchor-composed-samples.json", String(decoding: data, as: UTF8.self) + "\n")
    }

    /// A selection from page index 3 to the end of page index 4's first body line ("... a long breath."), made by
    /// character index and by a drag ending 6 pt past the line's last character. PDFKit's range on page 4 ends with
    /// the line break; the stored range does not; pages are joined with "\n"; the anchor restores exactly. Control: the
    /// anchor stored with PDFKit's range for page 4 (what the builder stored before the line-end fix) does not.
    func testSelectionAcrossPagesEndingAtALineEndRestoresExactly() throws {
        let fixture = "labels-multipage.pdf"
        let source = try Fixture.open(fixture)
        let extraction = PageTextExtractor.extract(source)
        let page3 = try XCTUnwrap(source.page(at: 3))
        let page4 = try XCTUnwrap(source.page(at: 4))
        let units = try XCTUnwrap(page4.string) as NSString
        let breaks = (0..<units.length).filter { units.character(at: $0) == 0x0A }
        // Page 4's text: line 0 is the header; line 1, the first body line, ends at breaks[1].
        let lineEnd = breaks[1]
        XCTAssertTrue(units.substring(to: lineEnd).hasSuffix("for the length of a long breath."))
        let start = try XCTUnwrap(page3.selection(for: NSRange(location: 100, length: 1))).bounds(for: page3)
        let last = try XCTUnwrap(page4.selection(for: NSRange(location: lineEnd - 1, length: 1))).bounds(for: page4)
        let shapes: [(String, PDFSelection?)] = [
            ("by character index, to the line's last character", source.document.selection(
                from: page3, atCharacterIndex: 100, to: page4, atCharacterIndex: lineEnd - 1)),
            ("by a drag ending 6 pt past the line's last character", source.document.selection(
                from: page3, at: CGPoint(x: start.midX, y: start.midY), to: page4, at: CGPoint(x: last.maxX + 6, y: last.midY))),
        ]
        var report = ["A selection across pages that ends at a line's end (\(fixture), page index 3 to the end of page index 4's first body line), "
                      + "\(Evidence.environmentLabel)"]
        for (name, made) in shapes {
            let selection = try XCTUnwrap(made, name)
            let text = try XCTUnwrap(selection.string)
            XCTAssertEqual(selection.pages.map { source.index(of: $0) }, [3, 4], name)
            let reported = selection.range(at: selection.numberOfTextRanges(on: page4) - 1, on: page4)
            XCTAssertEqual(NSMaxRange(reported), lineEnd + 1, "\(name): PDFKit's range on page 4 ends with the line break")
            XCTAssertFalse(text.unicodeScalars.last == "\n", "\(name): the selection's text stops before the break")

            let anchor = try PDFAnchorBuilder.capture(selection: selection, in: source, extraction: extraction)
            XCTAssertEqual(anchor.segments.map(\.pageIndex), [3, 4], name)
            XCTAssertEqual(anchor.segments.last?.textRange.end, lineEnd, "\(name): the stored range stops before the break")
            // One piece per page: PDFKit joins the pages with "\n".
            XCTAssertTrue(UnicodeOffsets.scalarsEqual(anchor.segments.map(\.text).joined(separator: "\n"), text), name)
            let (resolution, restored) = try restoreAfterRoundTrip(anchor, fixture: fixture)
            if case .exact = resolution {
                XCTAssertTrue(UnicodeOffsets.scalarsEqual(try XCTUnwrap(restored), text), "\(name): restored text")
            } else {
                XCTFail("\(name): \(describe(resolution)), expected exact")
            }

            // Control: the last segment stored with PDFKit's reported range, its text and context.
            let pageText = try XCTUnwrap(extraction.page(4)?.text)
            let range = try UnicodeOffsets.scalarRange(fromUTF16: reported, in: pageText)
            let total = UnicodeOffsets.scalarCount(pageText)
            var old = anchor
            let i = old.segments.count - 1
            old.segments[i].textRange = PDFAnchor.TextRange(range)
            old.segments[i].text = try UnicodeOffsets.substring(pageText, scalars: range)
            old.segments[i].suffix = try UnicodeOffsets.substring(
                pageText, scalars: ScalarRange(start: range.end, end: min(total, range.end + PDFAnchorBuilder.contextScalars)))
            let control = PDFAnchorResolver.resolve(old, in: source, extraction: extraction)
            if case .exact = control { XCTFail("\(name): control: the anchor with PDFKit's range restored exactly") }
            report.append("\(name): PDFKit ranges \(ranges(selection, in: source)); \(UnicodeOffsets.scalarCount(text)) scalars ending "
                          + "\"\(esc(String(text.suffix(16))))\"; stored segments \(segments(anchor)); restored: \(describe(resolution)); "
                          + "control with PDFKit's range on page 4: \(describe(control))")
        }
        Evidence.write("anchor-cross-page-line-end.txt", report.joined(separator: "\n") + "\n")
    }

    /// The restore path the harness runs on every open (`HighlightRestorer`) with a composed record whose page text
    /// changed since capture (the simulated drift of `HighlightRestoreTests`): it relocates by exact text plus context,
    /// its anchor is rebuilt (the capture check passes for the composed selection) and saved, and it then restores
    /// exactly. Before the fix, the rebuild of such a record failed and it was not drawn.
    func testRelocatedComposedRecordIsRebuiltAndSaved() throws {
        let source = try Fixture.open("labels-multipage.pdf")
        let extraction = PageTextExtractor.extract(source)
        var report = ["HighlightRestorer with composed records whose page text changed (simulated drift), labels-multipage.pdf, "
                      + "\(Evidence.environmentLabel)"]
        for shape in [Self.shapes[0], Self.shapes[4], Self.shapes[6]] {
            let selection = PDFSelection(document: source.document)
            for piece in shape.pieces {
                selection.add(try XCTUnwrap(source.page(at: piece.page)?.selection(for: NSRange(location: piece.location, length: piece.length))))
            }
            let original = try PDFAnchorBuilder.capture(selection: selection, in: source, extraction: extraction)
            let record = HighlightRecord(createdAt: Date(timeIntervalSince1970: 1_791_000_000), anchor: HighlightRestoreTests.drift(original))
            let first = HighlightRestorer.restore([record], in: source, extraction: extraction)
            XCTAssertEqual([first.exact, first.relocated, first.relocationNotRebuilt, first.needsReview, first.notFound], [0, 1, 0, 0, 0], shape.name)
            XCTAssertTrue(first.needsSave, shape.name)
            XCTAssertEqual(first.records.first?.id, record.id, shape.name)
            XCTAssertEqual(first.records.first?.anchor, original, "\(shape.name): the rebuilt anchor equals a fresh capture")
            XCTAssertEqual(first.drawable, [original], shape.name)
            let second = HighlightRestorer.restore(first.records, in: source, extraction: extraction)
            XCTAssertEqual([second.exact, second.relocated], [1, 0], shape.name)
            report.append("\(shape.name): first open relocated \(first.relocated), not rebuilt \(first.relocationNotRebuilt), drawn \(first.drawable.count), "
                          + "rebuilt anchor equals a fresh capture: \(first.records.first?.anchor == original); after saving: exact \(second.exact)")
        }
        Evidence.write("highlight-restore-relocated-composed.txt", report.joined(separator: "\n") + "\n")
    }

    /// A selection whose ranges cannot give back its quotation is refused with `quotationMismatch`: a two-piece
    /// selection that claims the pieces joined by "\n" (what the earlier check expected) and a one-piece selection that
    /// claims a changed letter. Control: the same ranges with PDFKit's own text are captured.
    func testSelectionWhoseRangesCannotGiveBackItsQuotationIsRefused() throws {
        let source = try Fixture.open("labels-multipage.pdf")
        let extraction = PageTextExtractor.extract(source)
        let page = try XCTUnwrap(source.page(at: 3))
        func piece(_ location: Int, _ length: Int) throws -> PDFSelection {
            try XCTUnwrap(page.selection(for: NSRange(location: location, length: length)))
        }
        var report = ["Selections whose ranges cannot give back their quotation (labels-multipage.pdf page index 3), \(Evidence.environmentLabel)"]
        let cases: [(String, [PDFSelection], String)] = [
            ("two pieces claiming \"The pond i\\nturning ov\"", [try piece(22, 10), try piece(120, 10)], "The pond i\nturning ov"),
            ("one piece claiming \"The pond I\"", [try piece(22, 10)], "The pond I"),
        ]
        for (name, pieces, quotation) in cases {
            let misquoting = MisquotingSelection(document: source.document, pieces: pieces, quotation: quotation)
            var outcome = "captured"
            do {
                _ = try PDFAnchorBuilder.capture(selection: misquoting, in: source, extraction: extraction)
                XCTFail("\(name): an anchor that cannot give back its quotation was stored")
            } catch {
                XCTAssertEqual(error, .quotationMismatch, name)
                outcome = "refused: \(error)"
            }
            // Control: the same pieces with PDFKit's own text.
            let honest = PDFSelection(document: source.document)
            for p in pieces { honest.add(p) }
            let control = try PDFAnchorBuilder.capture(selection: honest, in: source, extraction: extraction)
            report.append("\(name): \(outcome); control with PDFKit's own text \"\(esc(honest.string))\": captured, segments \(segments(control))")
        }
        Evidence.write("anchor-quotation-mismatch.txt", report.joined(separator: "\n") + "\n")
    }
}
