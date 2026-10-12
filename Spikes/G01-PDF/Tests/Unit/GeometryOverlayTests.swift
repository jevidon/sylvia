import PDFAnchorKit
import PDFKit
import UIKit
import XCTest

@MainActor
func makeHostWindow(size: CGSize = CGSize(width: 393, height: 852)) -> UIWindow {
    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
        fatalError("unit tests run hosted in the harness app, which always has a window scene")
    }
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(origin: .zero, size: size)
    window.rootViewController = UIViewController()
    window.isHidden = false
    return window
}

/// Brief item 3 and gate G0.1 "rotation anchors": geometry conventions, overlay drawing and their round trip on
/// rotated pages.
@MainActor
final class GeometryOverlayTests: XCTestCase {
    static let rotationSamples = ["rotate-0", "rotate-90", "rotate-180", "rotate-270", "rotate-90-inherited", "rotate-270-offset-cropbox"]

    func anchor(_ name: String) throws -> (PDFSourceDocument, PDFAnchor) {
        let sample = try XCTUnwrap(Samples.all.first { $0.name == name })
        let source = try Fixture.open(sample.fixture)
        let extraction = PageTextExtractor.extract(source)
        let selection = try XCTUnwrap(sample.make(source))
        return (source, try PDFAnchorBuilder.capture(selection: selection, in: source, extraction: extraction))
    }

    /// Random rectangles from a fixed seed, so a failure names reproducible inputs.
    func testDisplayMappingIsInvertible() {
        var generator = SplitMix64(seed: 0x5917_7A01)
        for rotation in PageRotation.allCases {
            for _ in 0..<200 {
                let x = Double.random(in: 0..<0.9, using: &generator)
                let y = Double.random(in: 0..<0.9, using: &generator)
                let r = NormalizedRect(x: x, y: y, width: Double.random(in: 0.001..<(1 - x), using: &generator),
                                       height: Double.random(in: 0.001..<(1 - y), using: &generator))
                let back = PageGeometry.unrotatedRect(fromDisplay: PageGeometry.displayRect(r, rotation: rotation), rotation: rotation)
                XCTAssertLessThan(back.maxDeviation(from: r), 1e-12, "rotation \(rotation.rawValue), rect \(r)")
            }
        }
    }

    /// The portable mapping (stored rect + rotation -> displayed rect) agrees with PDFKit's own page transform.
    func testPortableDisplayMappingMatchesPDFKitTransform() throws {
        var report = ["Portable display mapping vs PDFKit transform(for: .cropBox), \(Evidence.environmentLabel)"]
        for name in Self.rotationSamples {
            let (source, anchor) = try anchor(name)
            let segment = anchor.segments[0]
            let page = try XCTUnwrap(source.page(at: segment.pageIndex))
            let box = page.bounds(for: .cropBox)
            let rotation = try PageRotation(degrees: segment.pageRotation)
            let display = PageGeometry.displaySize(of: box, rotation: rotation)
            let t = page.transform(for: .cropBox)
            var worst = 0.0
            for n in segment.lineRects {
                let d = PageGeometry.denormalize(n, in: box).applying(t)
                let pdfkit = NormalizedRect(x: d.minX / display.width, y: (display.height - d.maxY) / display.height,
                                            width: d.width / display.width, height: d.height / display.height)
                worst = max(worst, PageGeometry.displayRect(n, rotation: rotation).maxDeviation(from: pdfkit))
            }
            XCTAssertLessThan(worst, 1e-6, name)
            report.append("\(name): rotation \(segment.pageRotation), box \(segment.pageBox.rect), transform \(t), \(segment.lineRects.count) lines, max deviation \(worst)")
        }
        Evidence.write("geometry-transform-check.txt", report.joined(separator: "\n") + "\n")
    }

    /// The same check against a live PDFView's coordinate conversion, page by page.
    func testPDFViewConversionMatchesPortableMapping() throws {
        var report = ["Portable display mapping vs PDFView.convert(_:from:), \(Evidence.environmentLabel)",
                      "tolerance 0.001 of the displayed page"]
        let window = makeHostWindow()
        defer { window.isHidden = true }
        for name in Self.rotationSamples {
            let (source, anchor) = try anchor(name)
            let segment = anchor.segments[0]
            let view = PDFView(frame: window.bounds)
            view.autoScales = true
            view.displayMode = .singlePage
            window.rootViewController?.view.addSubview(view)
            defer { view.removeFromSuperview() }
            view.document = source.document
            let page = try XCTUnwrap(source.page(at: segment.pageIndex))
            view.go(to: page)
            view.layoutIfNeeded()
            spinRunLoop(seconds: 0.1)
            let rotation = try PageRotation(degrees: segment.pageRotation)
            let box = page.bounds(for: .cropBox)
            let frame = view.convert(box, from: page)
            var worst = 0.0
            for n in segment.lineRects {
                let r = view.convert(PageGeometry.denormalize(n, in: box), from: page)
                let observed = NormalizedRect(x: (r.minX - frame.minX) / frame.width, y: (r.minY - frame.minY) / frame.height,
                                              width: r.width / frame.width, height: r.height / frame.height)
                worst = max(worst, PageGeometry.displayRect(n, rotation: rotation).maxDeviation(from: observed))
            }
            XCTAssertLessThan(worst, 0.001, name)
            report.append("\(name): page frame in view \(frame.integral), max deviation \(String(format: "%.6f", worst))")
        }
        Evidence.write("geometry-pdfview-check.txt", report.joined(separator: "\n") + "\n")
    }

    func testOverlayPagesAreTheSubclass() throws {
        let source = try Fixture.open("rotated.pdf")
        XCTAssertTrue(source.document is OverlayPDFDocument)
        for i in 0..<source.document.pageCount {
            XCTAssertTrue(source.page(at: i) is OverlayPage, "page \(i)")
        }
    }

    /// Offscreen render through `PDFPage.draw(with:to:)`: the fill and underline land on the stored lines on every
    /// rotation, are absent without the overlay, and stay distinguishable in grayscale.
    func testOverlayDrawsOchreFillAndUnderlineOnEveryRotation() throws {
        var report = ["Overlay pixels, offscreen render at 2 px/pt, \(Evidence.environmentLabel)",
                      "expected fill \(Expected.ochreTint) (ochre.tint multiplied over white paper), underline \(Expected.ochre) (ochre), paper \(Expected.paper)"]
        let scale: CGFloat = 2
        for name in Self.rotationSamples + ["multiline", "cross-column"] {
            let (source, anchor) = try anchor(name)
            let segment = anchor.segments[0]
            let page = try XCTUnwrap(source.page(at: segment.pageIndex) as? OverlayPage)
            let box = page.bounds(for: .cropBox)
            let rotation = try PageRotation(degrees: segment.pageRotation)

            page.highlightRects = []
            let plain = Pixels(try XCTUnwrap(PageRenderer.render(page, scale: scale)))
            HighlightOverlay.apply([anchor], to: source.document)
            XCTAssertEqual(page.highlightRects.count, segment.lineRects.count)
            let image = try XCTUnwrap(PageRenderer.render(page, scale: scale))
            let lit = Pixels(image)
            let gray = Pixels(try XCTUnwrap(grayscale(image)))

            func px(_ userRect: CGRect, inset: CGFloat = 1) -> CGRect {
                let n = try! PageGeometry.normalize(userRect, in: box)
                return pixelRect(PageGeometry.displayRect(n, rotation: rotation), imageWidth: lit.width, imageHeight: lit.height)
                    .insetBy(dx: inset, dy: inset)
            }
            var worstFill = 0, worstUnderline = 0
            var maxUnderlineLum = 0.0, maxFillLum = 0.0
            for n in segment.lineRects {
                let line = PageGeometry.denormalize(n, in: box)
                let underline = HighlightStyle.underlineRect(for: line)
                let body = CGRect(x: line.minX, y: underline.maxY, width: line.width, height: line.maxY - underline.maxY)
                let gap = CGRect(x: line.minX, y: line.minY - 2, width: line.width, height: 1.5)

                let u = lit.dominant(in: px(underline, inset: 0.5))
                let f = lit.dominant(in: px(body))
                worstUnderline = max(worstUnderline, u.distance(to: Expected.ochre))
                worstFill = max(worstFill, f.distance(to: Expected.ochreTint))
                XCTAssertLessThanOrEqual(u.distance(to: Expected.ochre), 8, "\(name): underline \(u)")
                XCTAssertLessThanOrEqual(f.distance(to: Expected.ochreTint), 8, "\(name): fill \(f)")
                XCTAssertLessThanOrEqual(lit.dominant(in: px(gap, inset: 0.5)).distance(to: Expected.paper), 2, "\(name): paper outside the highlight")
                XCTAssertLessThanOrEqual(plain.dominant(in: px(underline, inset: 0.5)).distance(to: Expected.paper), 2, "\(name): no underline without overlay")
                XCTAssertLessThanOrEqual(plain.dominant(in: px(body)).distance(to: Expected.paper), 2, "\(name): no fill without overlay")
                // Grayscale: the underline is dark and the fill is visibly darker than paper.
                let gu = Double(gray.dominant(in: px(underline, inset: 0.5)).r) / 255
                let gf = Double(gray.dominant(in: px(body)).r) / 255
                maxUnderlineLum = max(maxUnderlineLum, gu)
                maxFillLum = max(maxFillLum, gf)
                XCTAssertLessThan(gu, 0.5, "\(name): underline must read in grayscale")
                XCTAssertLessThan(gf, 0.95, "\(name): fill must differ from paper in grayscale")
                XCTAssertGreaterThan(Double(gray.dominant(in: px(gap, inset: 0.5)).r) / 255, 0.99)
            }
            report.append("\(name): rotation \(rotation.rawValue), \(segment.lineRects.count) lines; worst channel error fill \(worstFill), underline \(worstUnderline); "
                          + "grayscale level underline <= \(String(format: "%.2f", maxUnderlineLum)), fill <= \(String(format: "%.2f", maxFillLum)), paper 1.00")
            if name.hasPrefix("rotate-") || name == "cross-column" {
                let small = try XCTUnwrap(PageRenderer.render(page, scale: 1))
                Evidence.writePNG("overlay-\(name).png", small)
                if name == "rotate-90" || name == "cross-column" {
                    Evidence.writePNG("overlay-\(name)-grayscale.png", try XCTUnwrap(grayscale(small)))
                }
            }
        }
        Evidence.write("overlay-pixels.txt", report.joined(separator: "\n") + "\n")
    }

    /// A live PDFView draws its page tiles through `OverlayPage.draw(with:to:)` (on PDFKit's tile threads), so the
    /// overlay drawn and pixel-checked offscreen above is what the reader shows. `drawHierarchy` does not capture
    /// PDFView's tile surfaces on the simulator (the snapshot is a blank page), so the on-screen pixels are checked by
    /// the UI tests in `HighlightUITests` from real screen captures instead.
    func testPDFViewDrawsPagesThroughTheOverlay() throws {
        let (source, anchor) = try anchor("rotate-90")
        HighlightOverlay.apply([anchor], to: source.document)
        let page = try XCTUnwrap(source.page(at: anchor.segments[0].pageIndex) as? OverlayPage)
        OverlayDrawLog.shared.reset()
        let window = makeHostWindow()
        defer { window.isHidden = true }
        let view = PDFView(frame: window.bounds)
        view.displayMode = .singlePage
        window.rootViewController?.view.addSubview(view)
        view.document = source.document
        view.go(to: page)
        view.autoScales = true
        view.layoutIfNeeded()
        let drawn = waitUntil(timeout: 8) {
            OverlayDrawLog.shared.snapshot.contains { $0.page == ObjectIdentifier(page) && $0.highlightCount == anchor.segments[0].lineRects.count }
        }
        XCTAssertTrue(drawn, "PDFView never drew the highlighted page through OverlayPage.draw(with:to:)")
        let events = OverlayDrawLog.shared.snapshot.filter { $0.page == ObjectIdentifier(page) }
        XCTAssertTrue(events.contains { !$0.onMainThread }, "expected PDFKit tile rendering off the main thread")
        Evidence.write("pdfview-overlay-draws.txt", "Live PDFView on rotated.pdf page 1 (/Rotate 90), \(Evidence.environmentLabel)\n"
                       + "OverlayPage.draw(with:to:) calls for the page: \(events.count); with \(anchor.segments[0].lineRects.count) highlight lines: \(events.filter { $0.highlightCount > 0 }.count); "
                       + "off the main thread: \(events.filter { !$0.onMainThread }.count); boxes \(Set(events.map(\.box)).sorted())\n")
    }

    /// Restored highlights are drawn where PDFKit puts the restored selection. The overlay's user-space rectangles
    /// come from the stored, normalized `line_rects`; the comparison is PDFKit's own line bounds of the selection
    /// rebuilt from the stored scalar range on a freshly opened copy, in user space and after a live
    /// `PDFView.convert(_:from:)`, on every rotation.
    func testOverlayRectsMatchRestoredSelectionLines() throws {
        let userTolerance = 0.005 // points; 6-decimal rounding of a US Letter coordinate is at most 0.0004 pt
        var report = ["Overlay rectangles vs the restored selection's line bounds, \(Evidence.environmentLabel)",
                      "tolerance \(userTolerance) pt in user space, and the same times the view scale in view points"]
        let window = makeHostWindow()
        defer { window.isHidden = true }
        for name in Self.rotationSamples + ["multiline", "cross-column"] {
            let (_, captured) = try anchor(name)
            let stored = try AnchorJSON.decoder().decode(PDFAnchor.self, from: AnchorJSON.encoder().encode(captured))
            let sample = try XCTUnwrap(Samples.all.first { $0.name == name })
            let reopened = try Fixture.open(sample.fixture)
            guard case .exact(let resolved) = PDFAnchorResolver.resolve(stored, in: reopened, extraction: PageTextExtractor.extract(reopened)) else {
                XCTFail("\(name): not restored exactly")
                continue
            }
            HighlightOverlay.apply([stored], to: reopened.document)
            let segment = stored.segments[0]
            let page = try XCTUnwrap(reopened.page(at: segment.pageIndex) as? OverlayPage)
            let overlay = page.highlightRects
            let selectionLines = resolved.selection.selectionsByLine()
                .map { $0.bounds(for: page) }
                .filter { !$0.isNull && $0.width > 0 && $0.height > 0 }
            XCTAssertEqual(overlay.count, selectionLines.count, name)

            let view = PDFView(frame: window.bounds)
            view.autoScales = true
            view.displayMode = .singlePage
            window.rootViewController?.view.addSubview(view)
            defer { view.removeFromSuperview() }
            view.document = reopened.document
            view.go(to: page)
            view.layoutIfNeeded()
            spinRunLoop(seconds: 0.1)
            var worstUser = 0.0, worstView = 0.0
            for (o, l) in zip(overlay, selectionLines) {
                worstUser = max(worstUser, Self.maxEdgeDistance(o, l))
                worstView = max(worstView, Self.maxEdgeDistance(view.convert(o, from: page), view.convert(l, from: page)))
            }
            XCTAssertLessThanOrEqual(worstUser, userTolerance, name)
            XCTAssertLessThanOrEqual(worstView, userTolerance * max(1, Double(view.scaleFactor)), name)
            report.append("\(name): rotation \(segment.pageRotation), \(overlay.count) overlay rects vs \(selectionLines.count) selection lines; "
                          + "max edge distance \(String(format: "%.6f", worstUser)) pt (user space), \(String(format: "%.6f", worstView)) pt (PDFView, scale \(String(format: "%.3f", Double(view.scaleFactor))))")
        }
        Evidence.write("overlay-vs-restored-selection.txt", report.joined(separator: "\n") + "\n")
    }

    static func maxEdgeDistance(_ a: CGRect, _ b: CGRect) -> Double {
        Double(max(abs(a.minX - b.minX), abs(a.minY - b.minY), abs(a.maxX - b.maxX), abs(a.maxY - b.maxY)))
    }
}

/// SplitMix64: a small seeded generator for reproducible random test inputs.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
