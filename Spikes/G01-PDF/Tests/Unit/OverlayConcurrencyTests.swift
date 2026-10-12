import CoreGraphics
import PDFAnchorKit
import PDFKit
import Synchronization
import XCTest

/// Hands a non-Sendable PDFKit object to worker threads. Only for tests whose subject is exactly that sharing: PDFView
/// itself draws pages on its tile threads while the main thread changes highlights.
final class UncheckedShare<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

final class StressCounters: Sendable {
    let stop = Mutex(false)
    let draws = Mutex(0)
    let mixedReads = Mutex(0)
}

/// Overlay drawing is safe while highlights change (ADR-0005, "Highlights and overlays"). PDFView draws page tiles
/// through `OverlayPage.draw(with:to:)` on PDFKit's tile threads (`PDFKit.PDFTilePool.workQueue`) while the main
/// thread sets `highlightRects` and calls `HighlightOverlay.apply`. Before the rectangles moved into a mutex-guarded
/// associated object the harness crashed in exactly these two places (`overlay-stored-property-crash.txt`).
///
/// `Scripts/ci.d/32-g01-pdf.sh` runs this class a second time with the Thread Sanitizer and fails on any report
/// (`overlay-concurrency-*-tsan.txt`); a one-off control with the mutex removed shows the sanitizer reporting the race
/// (`tsan-control-unguarded.txt`).
@MainActor
final class OverlayConcurrencyTests: XCTestCase {
    static var underThreadSanitizer: Bool {
        ProcessInfo.processInfo.environment["SYLVIA_G01_PDF_TSAN"] == "1"
    }

    /// One evidence file per test, so rerunning one test never drops the other's result.
    static func evidenceName(_ part: String) -> String {
        "overlay-concurrency-\(part)" + (underThreadSanitizer ? "-tsan" : "") + ".txt"
    }

    /// `count` line rectangles that all carry `generation` in their width, so a reader can tell an array that mixes
    /// two writes from a consistent one.
    nonisolated static func rects(generation: Int, count: Int, in box: CGRect) -> [CGRect] {
        (0..<count).map { i in
            CGRect(x: box.minX + 20, y: box.minY + 40 + CGFloat(i) * 30, width: 100 + CGFloat(generation % 200), height: 12)
        }
    }

    /// (a) Six worker threads draw every page of rotated.pdf through `PDFPage.draw(with:to:)` for 4 s while the main
    /// thread replaces each page's rectangles (0 to 6 of them) every round and calls `HighlightOverlay.apply([])`
    /// every fifth round.
    func testBackgroundDrawsWhileMainThreadChangesHighlights() throws {
        let source = try Fixture.open("rotated.pdf")
        let pages = (0..<source.document.pageCount).compactMap { source.page(at: $0) as? OverlayPage }
        XCTAssertEqual(pages.count, source.document.pageCount)
        let shared = UncheckedShare(pages)
        let counters = StressCounters()
        let group = DispatchGroup()
        let workers = 6
        for worker in 0..<workers {
            DispatchQueue.global(qos: .userInitiated).async(group: group) {
                guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                      let context = CGContext(data: nil, width: 160, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return }
                context.scaleBy(x: 0.25, y: 0.25)
                var i = worker
                while !counters.stop.withLock({ $0 }) {
                    let page = shared.value[i % shared.value.count]
                    page.draw(with: .cropBox, to: context)
                    let seen = page.highlightRects
                    if Set(seen.map(\.width)).count > 1 { counters.mixedReads.withLock { $0 += 1 } }
                    counters.draws.withLock { $0 += 1 }
                    i += 1
                }
            }
        }
        let started = Date()
        var rounds = 0
        while Date().timeIntervalSince(started) < 4 {
            for page in pages {
                page.highlightRects = Self.rects(generation: rounds, count: rounds % 7, in: page.bounds(for: .cropBox))
            }
            if rounds % 5 == 0 { HighlightOverlay.apply([], to: source.document) }
            rounds += 1
        }
        counters.stop.withLock { $0 = true }
        XCTAssertEqual(group.wait(timeout: .now() + 20), .success, "workers did not finish")
        let draws = counters.draws.withLock { $0 }
        let mixed = counters.mixedReads.withLock { $0 }
        XCTAssertGreaterThan(rounds, 50)
        XCTAssertGreaterThan(draws, 50)
        XCTAssertEqual(mixed, 0, "a reader saw rectangles from two different writes")
        writeEvidence("offscreen", """
            (a) offscreen: \(workers) worker threads drawing the \(pages.count) OverlayPages of rotated.pdf for 4 s while \
            the main thread replaced highlightRects (0-6 rects) on every page each round and called \
            HighlightOverlay.apply([]) every 5th round: \(rounds) rounds, \(draws) draws, \(mixed) reads mixing two writes, \
            no crash
            """)
    }

    /// (b) A live PDFView on rotated.pdf page 1 (/Rotate 90): each round changes the page's rectangles and the scale
    /// (forcing PDFKit to render new tiles), for 6 s.
    func testLivePDFViewDrawsWhileHighlightsAndScaleChange() throws {
        let source = try Fixture.open("rotated.pdf")
        let page = try XCTUnwrap(source.page(at: 1) as? OverlayPage)
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
        XCTAssertTrue(waitUntil(timeout: 8) { OverlayDrawLog.shared.snapshot.contains { $0.page == ObjectIdentifier(page) } })
        let fit = view.scaleFactorForSizeToFit
        view.autoScales = false
        OverlayDrawLog.shared.reset()

        let box = page.bounds(for: .cropBox)
        let started = Date()
        var rounds = 0
        var pageEvents: [OverlayDrawLog.Event] = []
        while Date().timeIntervalSince(started) < 6 {
            page.highlightRects = Self.rects(generation: rounds, count: rounds % 7, in: box)
            view.scaleFactor = fit * (1 + CGFloat(rounds % 4) * 0.35)
            if rounds % 3 == 0 { view.setNeedsDisplay() }
            spinRunLoop(seconds: 0.02)
            // The draw log keeps the latest 512 events; collect as we go.
            pageEvents += OverlayDrawLog.shared.snapshot.filter { $0.page == ObjectIdentifier(page) }
            OverlayDrawLog.shared.reset()
            rounds += 1
        }
        spinRunLoop(seconds: 0.5)
        pageEvents += OverlayDrawLog.shared.snapshot.filter { $0.page == ObjectIdentifier(page) }
        let offMain = pageEvents.filter { !$0.onMainThread }.count
        let counts = Set(pageEvents.map(\.highlightCount))
        XCTAssertGreaterThan(offMain, 10, "expected PDFKit tile rendering off the main thread while highlights change")
        XCTAssertGreaterThan(counts.count, 1, "draws should have seen several different highlight sets")
        writeEvidence("pdfview", """
            (b) live PDFView, rotated.pdf page 1: \(rounds) rounds in 6 s, each setting highlightRects (0-6 rects) and \
            scaleFactor = fit x (1 + (round % 4) x 0.35), setNeedsDisplay() every 3rd round: \(pageEvents.count) \
            OverlayPage.draw calls for the page, \(offMain) off the main thread, highlight counts drawn \
            \(counts.sorted()), no crash
            """)
    }

    private func writeEvidence(_ part: String, _ line: String) {
        let header = "Overlay drawing while highlights change, \(Evidence.environmentLabel)"
            + (Self.underThreadSanitizer ? ", built with -enableThreadSanitizer YES" : "")
        Evidence.write(Self.evidenceName(part), header + "\n" + line + "\n")
    }
}
