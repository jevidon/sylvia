import PDFAnchorKit
import PDFKit
import XCTest

/// Brief items 2 and 3 for selections that end with a line's last character. PDFKit reports such a selection's range
/// (`range(at:on:)`) with the line break that follows it, although the selection's text (`string`) stops before the
/// break. `PDFAnchorBuilder` drops the break. Before it did, an anchor quoted "water" but stored the range of
/// "water\n" and never restored; the control here rebuilds that anchor and shows it still fails. Shapes: a range to
/// the end of a line, the last word (as a long press selects it), the whole line, a drag from the line's first
/// character to 6 pt past its last one, and two lines ending at a line's end, on three lines: the first body line of
/// labels-multipage.pdf page index 3, the first line of two-column.pdf's left column (its end is followed by a gutter
/// and the right column) and the first body line of the /Rotate 90 page of rotated.pdf. PDFKit's range ends with the
/// line break for all five shapes on all three lines (asserted). Then every line of the rotated-text page of
/// text-layout.pdf (PDFKit's range ends with the break for every line but the page's last, which has none after it;
/// asserted), and a search hit at a line's end. A drag that ends 40 pt past each of the three lines' ends is recorded,
/// not asserted: where such a drag lands depends on the text around the line (an earlier version of this test used it
/// on two-column.pdf's full-width title, and it selected into the right column). Selections across pages and composed
/// of several pieces: `ComposedSelectionTests`.
@MainActor
final class LineEndSelectionTests: XCTestCase {
    struct Outcome {
        var reportedEndsWithBreak: Bool
        var line: String
    }

    func describe(_ resolution: AnchorResolution) -> String {
        switch resolution {
        case .exact: return "exact"
        case .relocated: return "relocated"
        case .needsReview(let n): return "location needs review (\(n) candidates)"
        case .notFound: return "not found"
        case .differentAsset: return "different asset"
        }
    }

    /// Captures `selection` (made on `source`'s page `pageIndex`), checks the anchor quotes exactly the selection,
    /// restores it after a JSON round trip and a fresh open, and, when PDFKit's reported range ends with a line break,
    /// restores the anchor as it would have been stored with that range (control: it must not restore exactly).
    func check(_ name: String, _ selection: PDFSelection?, in source: PDFSourceDocument, extraction: DocumentExtraction,
               fixture: String, pageIndex: Int) throws -> Outcome {
        let page = try XCTUnwrap(source.page(at: pageIndex))
        let selection = try XCTUnwrap(selection, "\(fixture) \(name): no selection")
        let units = try XCTUnwrap(page.string) as NSString
        let exact = try XCTUnwrap(selection.string)
        let count = selection.numberOfTextRanges(on: page)
        XCTAssertGreaterThan(count, 0, "\(fixture) \(name)")
        let reported = selection.range(at: count - 1, on: page)
        let endsWithBreak = NSMaxRange(reported) <= units.length && units.character(at: NSMaxRange(reported) - 1) == 0x0A
        let selectionEndsWithBreak = exact.unicodeScalars.last == "\n"

        let anchor = try PDFAnchorBuilder.capture(selection: selection, in: source, extraction: extraction)
        let last = try XCTUnwrap(anchor.segments.last)
        XCTAssertTrue(UnicodeOffsets.scalarsEqual(anchor.exactText, exact), "\(fixture) \(name)")
        // Every shape here is one range on one page, so its one segment quotes exactly the selection.
        XCTAssertEqual(anchor.segments.count, 1, "\(fixture) \(name)")
        XCTAssertTrue(UnicodeOffsets.scalarsEqual(last.text, anchor.exactText), "\(fixture) \(name): the stored range quotes exactly the selection")
        XCTAssertFalse(last.text.unicodeScalars.last == "\n", "\(fixture) \(name): no trailing line break is stored")

        let decoded = try AnchorJSON.decoder().decode(PDFAnchor.self, from: AnchorJSON.encoder().encode(anchor))
        let reopened = try Fixture.open(fixture)
        let reExtraction = PageTextExtractor.extract(reopened)
        let resolution = PDFAnchorResolver.resolve(decoded, in: reopened, extraction: reExtraction)
        if case .exact(let resolved) = resolution {
            XCTAssertTrue(UnicodeOffsets.scalarsEqual(try XCTUnwrap(resolved.selection.string), exact), "\(fixture) \(name): restored text")
        } else {
            XCTFail("\(fixture) \(name): \(describe(resolution)), expected exact")
        }

        var control = "not applicable (PDFKit's range has no trailing break)"
        if endsWithBreak, !selectionEndsWithBreak {
            // The anchor as the builder stored it before this round: PDFKit's reported range, its text and context.
            let pageText = try XCTUnwrap(extraction.page(pageIndex)?.text)
            let range = try UnicodeOffsets.scalarRange(fromUTF16: reported, in: pageText)
            let total = UnicodeOffsets.scalarCount(pageText)
            var old = anchor
            let i = old.segments.count - 1
            old.segments[i].textRange = PDFAnchor.TextRange(range)
            old.segments[i].text = try UnicodeOffsets.substring(pageText, scalars: range)
            old.segments[i].suffix = try UnicodeOffsets.substring(
                pageText, scalars: ScalarRange(start: range.end, end: min(total, range.end + PDFAnchorBuilder.contextScalars)))
            let outcome = PDFAnchorResolver.resolve(old, in: reopened, extraction: reExtraction)
            if case .exact = outcome { XCTFail("\(fixture) \(name): control: the anchor with PDFKit's range restored exactly") }
            control = describe(outcome)
        }
        let stored = anchor.segments.map { "\($0.textRange.start)..<\($0.textRange.end)" }.joined(separator: ", ")
        let line = "\(fixture) page \(pageIndex), \(name): selection \(UnicodeOffsets.scalarCount(exact)) scalars ending \"\(esc(String(exact.suffix(12))))\"; "
            + "PDFKit range \(reported.location)+\(reported.length) ends with a line break: \(endsWithBreak); stored scalar range \(stored); "
            + "restored: \(describe(resolution)); control with PDFKit's range: \(control)"
        return Outcome(reportedEndsWithBreak: endsWithBreak, line: line)
    }

    func testSelectionsEndingAtALineBreakRestoreExactly() throws {
        var report = ["Selections ending with a line's last character: capture, JSON round trip, fresh open, \(Evidence.environmentLabel)"]
        // (fixture, page index, index of the line in the page text): the first body line of labels-multipage.pdf page 3
        // (line 0 is the page header), the first line of two-column.pdf's left column (line 0 is the header and line 1
        // the full-width title) and the first body line of rotated.pdf's /Rotate 90 page.
        for (fixture, pageIndex, lineIndex) in [("labels-multipage.pdf", 3, 1), ("two-column.pdf", 0, 2), ("rotated.pdf", 1, 1)] {
            let source = try Fixture.open(fixture)
            let extraction = PageTextExtractor.extract(source)
            let page = try XCTUnwrap(source.page(at: pageIndex))
            let units = try XCTUnwrap(page.string) as NSString
            let breaks = (0..<units.length).filter { units.character(at: $0) == 0x0A }
            XCTAssertGreaterThan(breaks.count, lineIndex + 1, fixture)
            // The line is [start, end); its line break is at `end`; the line after it ends at `nextEnd`.
            let start = breaks[lineIndex - 1] + 1, end = breaks[lineIndex], nextEnd = breaks[lineIndex + 1]
            let first = try XCTUnwrap(page.selection(for: NSRange(location: start, length: 1))).bounds(for: page)
            let last = try XCTUnwrap(page.selection(for: NSRange(location: end - 1, length: 1))).bounds(for: page)
            let lastPoint = CGPoint(x: last.midX, y: last.midY)
            report.append("\(fixture) page \(pageIndex), line \(lineIndex) of the page text: \"\(esc(units.substring(with: NSRange(location: start, length: end - start))))\"")
            let shapes: [(String, PDFSelection?)] = [
                ("range to the line's end", page.selection(for: NSRange(location: start, length: end - start))),
                ("last word (selectionForWord)", page.selectionForWord(at: lastPoint)),
                ("whole line (selectionForLine)", page.selectionForLine(at: lastPoint)),
                ("drag from the line's first character to 6 pt past its last", page.selection(
                    from: CGPoint(x: first.midX, y: first.midY), to: CGPoint(x: last.maxX + 6, y: last.midY))),
                ("two lines to the second's end", page.selection(for: NSRange(location: start, length: nextEnd - start))),
            ]
            for (name, selection) in shapes {
                let outcome = try check(name, selection, in: source, extraction: extraction, fixture: fixture, pageIndex: pageIndex)
                report.append(outcome.line)
                // PDFKit's behaviour that makes the trimming necessary, for every shape on every line here.
                XCTAssertTrue(outcome.reportedEndsWithBreak, "\(fixture) \(name): PDFKit's range ends with the line break")
            }
            // Recorded, not asserted: a drag ending 40 pt past the line's end (where it lands depends on the text around).
            if let overshoot = page.selection(from: CGPoint(x: first.midX, y: first.midY), to: CGPoint(x: last.maxX + 40, y: last.midY)),
               let text = overshoot.string {
                let n = overshoot.numberOfTextRanges(on: page)
                let r = n > 0 ? overshoot.range(at: n - 1, on: page) : NSRange(location: NSNotFound, length: 0)
                report.append("\(fixture) page \(pageIndex), observation (not asserted): a drag from the line's first character to 40 pt past its last "
                              + "selects \(UnicodeOffsets.scalarCount(text)) scalars \"\(esc(String(text.prefix(12))))...\(esc(String(text.suffix(12))))\", "
                              + "PDFKit range \(r.location)+\(r.length); the line is \(start)+\(end - start + 1) with its break")
            }
        }

        // Every line of the rotated-text page (lines drawn with rotated text matrices), selected by its range.
        let layoutSource = try Fixture.open("text-layout.pdf")
        let layoutExtraction = PageTextExtractor.extract(layoutSource)
        let layout = try XCTUnwrap(layoutSource.page(at: 0))
        let text = try XCTUnwrap(layout.string)
        var location = 0
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let range = NSRange(location: location, length: (line as NSString).length)
            location += range.length + 1
            let outcome = try check("line \"\(line.prefix(24))\"", layout.selection(for: range), in: layoutSource,
                                    extraction: layoutExtraction, fixture: "text-layout.pdf", pageIndex: 0)
            report.append(outcome.line)
            // Every line but the page's last is followed by a break, and PDFKit's range for it covers that break.
            XCTAssertEqual(outcome.reportedEndsWithBreak, index < lines.count - 1, "text-layout.pdf line \(index): PDFKit's range ends with the line break")
        }

        // A search hit that ends at a line's end becomes an anchor through the same builder.
        let source = try Fixture.open("labels-multipage.pdf")
        let extraction = PageTextExtractor.extract(source)
        let hits = LexicalSearch.find("grey ice the water", in: extraction)
        XCTAssertEqual(hits.count, 1)
        let hit = try XCTUnwrap(hits.first)
        let anchor = try PDFAnchorBuilder.anchor(forScalarRange: hit.range, onPage: hit.pageIndex, in: source, extraction: extraction)
        XCTAssertEqual(anchor.exactText, "grey ice the water")
        XCTAssertEqual(anchor.segments.map(\.textRange.scalarRange), [hit.range])
        guard case .exact = PDFAnchorResolver.resolve(anchor, in: source, extraction: extraction) else {
            return XCTFail("the search hit at a line's end must restore exactly")
        }
        report.append("search hit \"grey ice the water\" (ends at a line's end, page \(hit.pageIndex), scalars \(hit.range.start)..<\(hit.range.end)): "
                      + "anchor range \(anchor.segments.map { "\($0.textRange.start)..<\($0.textRange.end)" }); restored exact")
        Evidence.write("anchor-line-end-selections.txt", report.joined(separator: "\n") + "\n")
    }
}
