import PDFAnchorKit
import PDFKit
import XCTest

/// Open-time measurement on the generated 1,000-page PDF (plan 19.2 "Open typical local EPUB/PDF", p95 <= 2 s on
/// a device). These are simulator numbers on the build Mac: they show the work the adapter adds, not device
/// performance. The device measurement is in the device checklist.
@MainActor
final class LargePDFTimingTests: XCTestCase {
    func testOpenAndFirstPageTimesOnLargePDF() throws {
        guard let path = ProcessInfo.processInfo.environment["SYLVIA_G01_PDF_LARGE"], !path.isEmpty else {
            throw XCTSkip("SYLVIA_G01_PDF_LARGE is not set; Scripts/ci.d/32-g01-pdf.sh sets it and fails on any skip")
        }
        let url = URL(fileURLWithPath: path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "run Scripts/fixtures/generate-g01-pdf-large.sh first")
        let loadBefore = hostLoadAverages()

        func ms(_ start: ContinuousClock.Instant) -> Double {
            let d = ContinuousClock.now - start
            return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
        }
        var openMs: [Double] = [], firstRenderMs: [Double] = [], viewFirstDrawMs: [Double] = [], extractMs: [Double] = []
        var pageCount = 0
        let window = makeHostWindow()
        defer { window.isHidden = true }
        for _ in 0..<5 {
            // 1. Open: SHA-256 of the file, structure check, PDFKit parse.
            var t = ContinuousClock.now
            let source = try PDFSourceDocument.open(url: url)
            openMs.append(ms(t))
            pageCount = source.document.pageCount
            // 2. First page rendered offscreen at 2x.
            t = ContinuousClock.now
            XCTAssertNotNil(PageRenderer.render(try XCTUnwrap(source.page(at: 0)), scale: 2))
            firstRenderMs.append(ms(t))
            // 3. A fresh document shown in a PDFView until PDFKit draws page 0 (tile renderer).
            let fresh = try PDFSourceDocument.open(url: url)
            let page0 = try XCTUnwrap(fresh.page(at: 0))
            OverlayDrawLog.shared.reset()
            let view = PDFView(frame: window.bounds)
            window.rootViewController?.view.addSubview(view)
            t = ContinuousClock.now
            view.document = fresh.document
            view.autoScales = true
            view.layoutIfNeeded()
            let drawn = waitUntil(timeout: 10) { OverlayDrawLog.shared.snapshot.contains { $0.page == ObjectIdentifier(page0) } }
            viewFirstDrawMs.append(ms(t))
            XCTAssertTrue(drawn)
            view.removeFromSuperview()
            // 4. Text extraction of every page (the cost of building the per-page text index once).
            t = ContinuousClock.now
            let extraction = PageTextExtractor.extract(source)
            extractMs.append(ms(t))
            XCTAssertEqual(extraction.pagesWithText, pageCount)
        }
        XCTAssertEqual(pageCount, 1000)
        // Sanity bound only (catches pathological regressions); not the plan's device budget.
        XCTAssertLessThan(openMs.max()!, 10_000)

        // Capture and restore deep in the document still work.
        let source = try PDFSourceDocument.open(url: url)
        let extraction = PageTextExtractor.extract(source)
        let anchor = try PDFAnchorBuilder.anchor(forScalarRange: ScalarRange(start: 30, end: 160), onPage: 777, in: source, extraction: extraction)
        guard case .exact = PDFAnchorResolver.resolve(anchor, in: source, extraction: extraction) else { return XCTFail("restore on page 777") }
        XCTAssertEqual(anchor.segments[0].pageLabel, "768", "labels i-x then 1...: physical index 777 is printed 768")

        // Restoring highlights on open (the harness does it before display) touches only the pages that carry them.
        var applyNoneMs: [Double] = [], applyOneMs: [Double] = []
        for _ in 0..<5 {
            let empty = try PDFSourceDocument.open(url: url)
            var t = ContinuousClock.now
            HighlightOverlay.apply([], to: empty.document)
            applyNoneMs.append(ms(t))
            let one = try PDFSourceDocument.open(url: url)
            t = ContinuousClock.now
            HighlightOverlay.apply([anchor], to: one.document)
            applyOneMs.append(ms(t))
            XCTAssertEqual(HighlightOverlay.highlightedPageIndices(in: one.document), [777])
        }

        func summary(_ name: String, _ v: [Double]) -> String {
            let s = v.sorted()
            return "\(name): median \(String(format: "%.1f", s[s.count / 2])) ms, max \(String(format: "%.1f", s.last!)) ms, runs \(s.map { String(format: "%.1f", $0) })"
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        let loadAfter = hostLoadAverages()
        Evidence.write("large-pdf-timing.txt", """
            Large PDF timing, \(Evidence.environmentLabel). SIMULATOR ON THE BUILD MAC; NOT A DEVICE RESULT.
            build Mac load averages (1, 5, 15 min, from getloadavg, which reads the Mac's kernel): \(loadBefore) before, \(loadAfter) after; other jobs share the Mac, so these timings are indicative only
            file: generated/g01-pdf/large-1000.pdf, \(pageCount) pages, \(size) bytes (Scripts/fixtures/generate-g01-pdf-large.sh)
            \(summary("open (sha256 + structure check + PDFKit parse)", openMs))
            \(summary("first page offscreen render at 2x", firstRenderMs))
            \(summary("PDFView: document set -> page 0 drawn by the tile renderer", viewFirstDrawMs))
            \(summary("extract text of all pages", extractMs))
            \(summary("HighlightOverlay.apply, no highlights, fresh document", applyNoneMs))
            \(summary("HighlightOverlay.apply, one highlight on page 777, fresh document", applyOneMs))
            capture + exact restore on physical page 777 (printed label \(anchor.segments[0].pageLabel ?? "-")): ok

            """)
    }
}
