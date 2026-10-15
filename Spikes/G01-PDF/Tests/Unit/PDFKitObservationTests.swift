import PDFAnchorKit
import PDFKit
import XCTest

/// Records what PDFKit itself reports for every committed fixture (pages, labels, rotation, boxes, text, permissions,
/// annotation actions). This is the raw behaviour the adapter is built on; the other tests assert the parts Sylvia
/// depends on.
@MainActor
final class PDFKitObservationTests: XCTestCase {
    static let fixtures = ["labels-multipage.pdf", "rotated.pdf", "two-column.pdf", "mixed-scanned.pdf", "unicode.pdf",
                           "encrypted-user-password.pdf", "encrypted-owner-only-nocopy.pdf", "truncated.pdf", "actions.pdf",
                           "actions-nonurl.pdf", "actions-chained.pdf", "text-layout.pdf"]

    func testRecordPDFKitBehaviourForEveryFixture() throws {
        // The list above is every committed fixture: the PDFs bundled from Spikes/G01-PDF/Fixtures.
        let bundled = try FileManager.default.contentsOfDirectory(atPath: Fixture.url("rotated.pdf").deletingLastPathComponent().path)
            .filter { $0.hasSuffix(".pdf") }.sorted()
        XCTAssertEqual(bundled, Self.fixtures.sorted(), "every bundled fixture is observed")
        var out = ["PDFKit observations, \(Evidence.environmentLabel)", ""]
        var opened = 0
        for name in Self.fixtures {
            let digest = try PDFSourceDocument.sha256OfFile(at: Fixture.url(name))
            out.append("== \(name) (\(digest.1) bytes, sha256 \(digest.0))")
            guard let doc = PDFDocument(url: Fixture.url(name)) else {
                out.append("PDFDocument(url:) returned nil")
                out.append("")
                continue
            }
            opened += 1
            out.append("pages \(doc.pageCount); isEncrypted \(doc.isEncrypted); isLocked \(doc.isLocked); allowsCopying \(doc.allowsCopying); allowsContentAccessibility \(doc.allowsContentAccessibility)")
            for i in 0..<doc.pageCount {
                guard let p = doc.page(at: i) else { continue }
                out.append("page \(i): label \(p.label ?? "nil"); rotation \(p.rotation); mediaBox \(p.bounds(for: .mediaBox)); cropBox \(p.bounds(for: .cropBox)); characters \(p.numberOfCharacters)")
                out.append("  string: \(esc(p.string))")
                for a in p.annotations {
                    out.append("  annotation \(a.type ?? "?") bounds \(a.bounds) action \(a.action.map { "\(type(of: $0)) \($0)" } ?? "nil")")
                }
            }
            out.append("")
        }
        XCTAssertEqual(opened, Self.fixtures.count - 1, "every fixture except the truncated one opens in PDFKit")

        // Point-to-character hit testing as a drag uses it (labels-multipage.pdf page 3; baselines at y = 700, 685, 670).
        let doc = try XCTUnwrap(PDFDocument(url: Fixture.url("labels-multipage.pdf")))
        let page = try XCTUnwrap(doc.page(at: 3))
        out.append("== hit testing on labels-multipage.pdf page 3 (third body line: baseline y = 670, text from x = 72 to about x = 262)")
        for (x, y) in [(150.0, 668.0), (150.0, 673.0), (150.0, 679.0), (300.0, 673.0)] {
            let p = CGPoint(x: x, y: y)
            let index = page.characterIndex(at: p)
            let line = (index != NSNotFound && index >= 0) ? page.selection(for: NSRange(location: index, length: 1))?.selectionsByLine().first?.bounds(for: page) : nil
            let drag = page.selection(from: CGPoint(x: 200, y: 703), to: p)
            out.append("point (\(x), \(y)): characterIndex \(index == NSNotFound ? "NSNotFound" : String(index)), its line box \(line.map { "\($0)" } ?? "none"); drag from (200, 703) ends \"\(esc(drag?.string.map { String($0.suffix(12)) }))\"")
        }
        Evidence.write("pdfkit-observations.txt", out.joined(separator: "\n"))
    }

    /// Report finding 4: PDFKit creates `pageClass` instances without running Swift property initializers, so a
    /// stored property of a `PDFPage` subclass is zeroed memory. A non-zero default proves it without the crash the
    /// harness hit when the overlay rectangles were a stored array (`overlay-stored-property-crash.txt`).
    func testPageClassInstancesSkipSwiftPropertyInitializers() throws {
        let document = try XCTUnwrap(StoredPropertyProbeDocument(url: Fixture.url("rotated.pdf")))
        let fromPDFKit = try XCTUnwrap(document.page(at: 0) as? StoredPropertyProbePage, "PDFKit used the page class")
        let fromSwift = StoredPropertyProbePage()
        XCTAssertEqual(fromSwift.marker, StoredPropertyProbePage.initialMarker, "control: a page made by Swift runs the initializer")
        XCTAssertEqual(fromPDFKit.marker, 0, "a page made by PDFKit skips the Swift initializer (zeroed storage)")
        Evidence.write("pdfkit-page-class-initializers.txt", """
            PDFPage subclass with a stored property `var marker: Int = \(StoredPropertyProbePage.initialMarker)`, \(Evidence.environmentLabel)
            page made by Swift (StoredPropertyProbePage()): marker = \(fromSwift.marker)
            page made by PDFKit from pageClass (document.page(at: 0)): marker = \(fromPDFKit.marker)
            Conclusion: PDFKit does not run Swift property initializers for pageClass instances; per-page overlay state
            lives in an associated object (HighlightOverlay.swift).

            """)
    }
}

/// A page subclass with one stored property whose default is not zero (see the test above).
final class StoredPropertyProbePage: PDFPage {
    static let initialMarker = 0x5157
    var marker: Int = StoredPropertyProbePage.initialMarker
}

final class StoredPropertyProbeDocument: PDFDocument {
    override var pageClass: AnyClass { StoredPropertyProbePage.self }
}
