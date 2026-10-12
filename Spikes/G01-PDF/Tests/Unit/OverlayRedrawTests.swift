import PDFAnchorKit
import PDFKit
import XCTest

/// How a new or removed highlight reaches the screen in a live PDFView (report finding 5), and that replacing
/// highlights touches only the pages that carry them (report row 28, device checklist step 10).
@MainActor
final class OverlayRedrawTests: XCTestCase {
    func captureSample(_ name: String) throws -> (PDFSourceDocument, PDFAnchor) {
        let sample = try XCTUnwrap(Samples.all.first { $0.name == name })
        let source = try Fixture.open(sample.fixture)
        let extraction = PageTextExtractor.extract(source)
        let selection = try XCTUnwrap(sample.make(source))
        return (source, try PDFAnchorBuilder.capture(selection: selection, in: source, extraction: extraction))
    }

    func draws(of page: PDFPage, withHighlights count: Int) -> [OverlayDrawLog.Event] {
        OverlayDrawLog.shared.snapshot.filter { $0.page == ObjectIdentifier(page) && $0.highlightCount == count }
    }

    /// PDFView keeps its rendered tiles when a page's overlay changes; `setNeedsDisplay()` redraws them through the
    /// overlay and keeps the selection, page and scale. Resetting the document (the harness's earlier strategy) is
    /// recorded for comparison.
    func testNewHighlightIsDrawnAfterSetNeedsDisplayAndSelectionIsKept() throws {
        let (source, anchor) = try captureSample("rotate-90")
        let page = try XCTUnwrap(source.page(at: anchor.segments[0].pageIndex) as? OverlayPage)
        let lines = anchor.segments[0].lineRects.count
        HighlightOverlay.apply([], to: source.document)
        let window = makeHostWindow()
        defer { window.isHidden = true }
        let view = PDFView(frame: window.bounds)
        view.displayMode = .singlePage
        window.rootViewController?.view.addSubview(view)
        defer { view.removeFromSuperview() }
        OverlayDrawLog.shared.reset()
        view.document = source.document
        view.go(to: page)
        view.autoScales = true
        view.layoutIfNeeded()
        XCTAssertTrue(waitUntil(timeout: 8) { !self.draws(of: page, withHighlights: 0).isEmpty }, "the page was never drawn")
        // A selection elsewhere on the page, as a reader would have one while saving another highlight.
        let selection = try XCTUnwrap(page.selection(for: NSRange(location: 0, length: 24)))
        view.setCurrentSelection(selection, animate: false)
        spinRunLoop(seconds: 1.5)
        let selectedBefore = try XCTUnwrap(view.currentSelection?.string)
        let pageBefore = view.currentPage
        let scaleBefore = view.scaleFactor
        var report = ["New highlight in a live PDFView (rotated.pdf page 1, /Rotate 90), \(Evidence.environmentLabel)"]

        // 1. The overlay changes and nothing tells PDFView.
        OverlayDrawLog.shared.reset()
        HighlightOverlay.apply([anchor], to: source.document)
        spinRunLoop(seconds: 3)
        let withoutInvalidation = draws(of: page, withHighlights: lines).count
        let anyDraw = OverlayDrawLog.shared.snapshot.filter { $0.page == ObjectIdentifier(page) }.count
        XCTAssertEqual(withoutInvalidation, 0, "observation: PDFView redrew the page by itself")
        report.append("1. highlightRects set (\(lines) lines), no invalidation, 3 s: \(anyDraw) draws of the page, \(withoutInvalidation) with the new highlight")

        // 2. setNeedsDisplay() alone.
        OverlayDrawLog.shared.reset()
        view.setNeedsDisplay()
        XCTAssertTrue(waitUntil(timeout: 5) { !self.draws(of: page, withHighlights: lines).isEmpty }, "setNeedsDisplay did not redraw the page")
        spinRunLoop(seconds: 0.5)
        let afterInvalidation = draws(of: page, withHighlights: lines)
        XCTAssertEqual(view.currentSelection?.string, selectedBefore, "the selection must survive the redraw")
        XCTAssertTrue(view.currentPage === pageBefore)
        XCTAssertEqual(view.scaleFactor, scaleBefore)
        report.append("2. view.setNeedsDisplay(): \(afterInvalidation.count) draws with the new highlight, \(afterInvalidation.filter { !$0.onMainThread }.count) off the main thread; "
                      + "selection kept \(view.currentSelection?.string == selectedBefore), page kept \(view.currentPage === pageBefore), scale kept \(view.scaleFactor == scaleBefore)")

        // 3. A second change (one line removed) plus setNeedsDisplay().
        OverlayDrawLog.shared.reset()
        page.highlightRects = Array(page.highlightRects.dropLast())
        view.setNeedsDisplay()
        XCTAssertTrue(waitUntil(timeout: 5) { !self.draws(of: page, withHighlights: lines - 1).isEmpty })
        XCTAssertEqual(view.currentSelection?.string, selectedBefore)
        report.append("3. second change (\(lines - 1) lines) + setNeedsDisplay(): \(draws(of: page, withHighlights: lines - 1).count) draws with it; selection kept \(view.currentSelection?.string == selectedBefore)")

        // 4. For comparison, the earlier harness strategy: reset the document. Recorded, not asserted.
        OverlayDrawLog.shared.reset()
        view.document = nil
        view.document = source.document
        view.go(to: page)
        spinRunLoop(seconds: 1)
        let resetDraws = draws(of: page, withHighlights: lines - 1).count
        report.append("4. comparison, document reset (document = nil, then the same document, go(to: page)): \(resetDraws) draws with the current highlight; "
                      + "selection text unchanged \(view.currentSelection?.string == selectedBefore), scale unchanged \(view.scaleFactor == scaleBefore)")
        Evidence.write("overlay-redraw-invalidation.txt", report.joined(separator: "\n") + "\n")
    }

    /// `HighlightOverlay.apply` touches only the pages that had or get highlights; other pages get no storage.
    func testApplyTouchesOnlyHighlightedPages() throws {
        let (source, anchor) = try captureSample("multi-page")
        XCTAssertEqual(anchor.segments.map(\.pageIndex), [3, 4])
        XCTAssertEqual(HighlightOverlay.apply([], to: source.document), 0)
        XCTAssertEqual(HighlightOverlay.highlightedPageIndices(in: source.document), [])
        XCTAssertEqual(HighlightOverlay.apply([anchor], to: source.document), 2)
        XCTAssertEqual(HighlightOverlay.highlightedPageIndices(in: source.document), [3, 4])
        for i in 0..<source.document.pageCount {
            let page = try XCTUnwrap(source.page(at: i) as? OverlayPage)
            XCTAssertEqual(page.hasOverlayStorage, [3, 4].contains(i), "page \(i)")
        }
        // Removing every highlight clears exactly those pages.
        XCTAssertEqual(HighlightOverlay.apply([], to: source.document), 2)
        XCTAssertEqual(HighlightOverlay.highlightedPageIndices(in: source.document), [])
        for i in [3, 4] {
            XCTAssertEqual((source.page(at: i) as? OverlayPage)?.highlightRects, [])
        }
        // Rectangles set directly on a page are tracked too, so the next apply clears them.
        let other = try XCTUnwrap(source.page(at: 6) as? OverlayPage)
        other.highlightRects = [CGRect(x: 72, y: 600, width: 100, height: 12)]
        XCTAssertEqual(HighlightOverlay.highlightedPageIndices(in: source.document), [6])
        XCTAssertEqual(HighlightOverlay.apply([], to: source.document), 1)
        XCTAssertEqual(other.highlightRects, [])
    }
}
