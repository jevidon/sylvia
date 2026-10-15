import PDFAnchorKit
import PDFKit
import XCTest

/// Brief item 5 and T16 (image-only pages): per-page extraction status, no OCR, no guessed text.
@MainActor
final class ExtractionStatusTests: XCTestCase {
    func testMixedDocumentKeepsTextFeaturesOnlyOnPagesWithText() throws {
        let source = try Fixture.open("mixed-scanned.pdf")
        let extraction = PageTextExtractor.extract(source)
        XCTAssertEqual(extraction.pages.count, 4)
        XCTAssertEqual(extraction.pagesWithText, 2)
        XCTAssertEqual(extraction.pages.map(\.status.hasText), [true, false, true, false])
        for index in [1, 3] {
            let page = extraction.pages[index]
            XCTAssertEqual(page.status, .noSelectableText)
            XCTAssertEqual(page.status.unavailableMessage, "No selectable text on this page")
            XCTAssertNil(page.text, "no guessed or OCR text for an image-only page")
            XCTAssertNil(page.textSHA256)
            XCTAssertNil(page.textForAIContext, "nothing from an image-only page may be offered to AI")
            XCTAssertFalse(page.supportsTextFeatures)
        }
        for index in [0, 2] {
            let page = extraction.pages[index]
            XCTAssertTrue(page.supportsTextFeatures)
            XCTAssertNil(page.status.unavailableMessage)
            XCTAssertEqual(page.textForAIContext, page.text)
            XCTAssertNotNil(page.textSHA256)
        }
        XCTAssertTrue(try XCTUnwrap(extraction.pages[2].text).contains("Text features return on this page"))

        // A selection gesture on the image-only page produces no text, so no capture is possible there.
        let imagePage = try XCTUnwrap(source.page(at: 1))
        let drag = imagePage.selection(from: CGPoint(x: 80, y: 700), to: CGPoint(x: 500, y: 200))
        XCTAssertTrue(drag?.string?.isEmpty ?? true, "PDFKit must not invent text on an image-only page")
        // Capture on the text page next to it still works.
        let textPage = try XCTUnwrap(source.page(at: 2))
        let selection = try XCTUnwrap(textPage.selection(for: NSRange(location: 17, length: 60)))
        let anchor = try PDFAnchorBuilder.capture(selection: selection, in: source, extraction: extraction)
        XCTAssertEqual(anchor.segments.map(\.pageIndex), [2])
        // Search never reports a hit on an image-only page.
        XCTAssertTrue(LexicalSearch.find("page", in: extraction).allSatisfy { [0, 2].contains($0.pageIndex) })

        // Even if a selection object claimed the image-only page, the capture refuses rather than guessing.
        var forged = extraction
        forged.pages[2].status = .noSelectableText
        forged.pages[2].text = nil
        forged.pages[2].textSHA256 = nil
        XCTAssertThrowsError(try PDFAnchorBuilder.capture(selection: selection, in: source, extraction: forged)) { error in
            XCTAssertEqual(error as? AnchorCaptureError, .noSelectableText(pageIndex: 2))
        }

        var lines = ["Per-page extraction status for mixed-scanned.pdf, \(Evidence.environmentLabel)",
                     "extraction version: \(extraction.version.extractor) adapter v\(extraction.version.adapterVersion) on \(extraction.version.platform)"]
        for page in extraction.pages {
            let status: String
            switch page.status {
            case .text(let n): status = "text (\(n) scalars, sha256 \(page.textSHA256 ?? "-"))"
            case .noSelectableText: status = "no text -> \"\(page.status.unavailableMessage ?? "")\"; AI context: none"
            case .restrictedByPermissions: status = "restricted"
            }
            lines.append("page \(page.pageIndex) label \(page.pageLabel ?? "none"): \(status)")
        }
        lines.append("image-only page drag selection string: \(esc(drag?.string))")
        Evidence.write("t16-extraction-status.txt", lines.joined(separator: "\n") + "\n")
    }

    func testExtractionVersionIsRecorded() throws {
        let extraction = PageTextExtractor.extract(try Fixture.open("labels-multipage.pdf"))
        XCTAssertEqual(extraction.version.extractor, "pdfkit.PDFPage.string")
        XCTAssertEqual(extraction.version.adapterVersion, 1)
        XCTAssertTrue(extraction.version.platform.hasPrefix("iOS "), extraction.version.platform)
        XCTAssertTrue(extraction.version.platform.contains("("), "the OS build is part of the version: \(extraction.version.platform)")
    }

    func testPrintedLabelsComeOnlyFromPageLabels() throws {
        let labelled = try Fixture.open("labels-multipage.pdf")
        XCTAssertTrue(labelled.pageLabelsSupplied)
        XCTAssertEqual((0..<8).map { labelled.printedLabel(forPageAt: $0) }, ["i", "ii", "iii", "1", "2", "3", "4", "A-1"])
        let unlabelled = try Fixture.open("two-column.pdf")
        XCTAssertFalse(unlabelled.pageLabelsSupplied)
        XCTAssertEqual(unlabelled.page(at: 0)?.label, "1", "observation: PDFKit invents \"1\" without /PageLabels")
        XCTAssertNil(unlabelled.printedLabel(forPageAt: 0), "Sylvia does not store an invented label")
    }

    func testTextOutsideTheCropBoxIsNotExtracted() throws {
        // rotated.pdf page 5 draws its header at y = 760, above its CropBox (top edge y = 700).
        let source = try Fixture.open("rotated.pdf")
        let page = try XCTUnwrap(source.page(at: 5))
        XCTAssertEqual(page.bounds(for: .cropBox), CGRect(x: 20, y: 30, width: 520, height: 670))
        XCTAssertFalse(try XCTUnwrap(page.string).contains("offset MediaBox"))
        XCTAssertTrue(try XCTUnwrap(source.page(at: 4)?.string).contains("inherited from the page tree"))
    }
}
