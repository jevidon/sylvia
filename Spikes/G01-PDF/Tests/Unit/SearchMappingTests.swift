import PDFAnchorKit
import PDFKit
import XCTest

/// Brief item 6: a lexical hit in extracted page text reopens at the right page and selection.
@MainActor
final class SearchMappingTests: XCTestCase {
    func testSearchHitsReopenAtTheRightPageAndSelection() throws {
        let source = try Fixture.open("labels-multipage.pdf")
        let extraction = PageTextExtractor.extract(source)
        let window = makeHostWindow()
        defer { window.isHidden = true }
        let view = PDFView(frame: window.bounds)
        view.autoScales = true
        window.rootViewController?.view.addSubview(view)
        view.document = source.document
        view.go(to: try XCTUnwrap(source.page(at: 0)))

        var report = ["Search hit to page and selection, labels-multipage.pdf, \(Evidence.environmentLabel)"]
        for query in ["heron", "Ledger of small things", "map of attention", "roman numerals", "page labels"] {
            let hits = LexicalSearch.find(query, in: extraction)
            XCTAssertFalse(hits.isEmpty, query)
            // PDFKit's own find agrees on the pages.
            let pdfkitPages = source.document.findString(query, withOptions: [.caseInsensitive])
                .flatMap { $0.pages.map { source.index(of: $0) } }
            XCTAssertEqual(hits.map(\.pageIndex), pdfkitPages, query)
            for hit in hits {
                XCTAssertEqual(hit.text.lowercased(), query.lowercased())
                let anchor = try PDFAnchorBuilder.anchor(forScalarRange: hit.range, onPage: hit.pageIndex, in: source, extraction: extraction)
                guard case .exact(let resolved) = PDFAnchorResolver.resolve(anchor, in: source, extraction: extraction) else {
                    XCTFail("\(query): hit did not resolve")
                    continue
                }
                // Reopen: go to the hit and select it.
                view.go(to: resolved.selection)
                view.setCurrentSelection(resolved.selection, animate: false)
                view.layoutIfNeeded()
                XCTAssertEqual(view.currentPage.map { source.index(of: $0) }, hit.pageIndex, query)
                XCTAssertTrue(UnicodeOffsets.scalarsEqual(try XCTUnwrap(view.currentSelection?.string), hit.text))
                XCTAssertEqual(anchor.segments[0].textRange.scalarRange, hit.range)
                report.append("\"\(query)\": page \(hit.pageIndex) (label \(hit.pageLabel ?? "-")), scalars [\(hit.range.start), \(hit.range.end)) -> PDFView page \(view.currentPage.map { source.index(of: $0) } ?? -1), selection \"\(esc(view.currentSelection?.string))\"")
            }
        }
        Evidence.write("search-mapping.txt", report.joined(separator: "\n") + "\n")
    }

    func testSearchWithNonBMPTextAndMixedDocument() throws {
        let unicode = try Fixture.open("unicode.pdf")
        let ux = PageTextExtractor.extract(unicode)
        let hits = LexicalSearch.find("\u{1D400}\u{1D401} end", in: ux)
        XCTAssertEqual(hits.count, 1)
        let anchor = try PDFAnchorBuilder.anchor(forScalarRange: hits[0].range, onPage: 0, in: unicode, extraction: ux)
        guard case .exact(let resolved) = PDFAnchorResolver.resolve(anchor, in: unicode, extraction: ux) else { return XCTFail() }
        XCTAssertTrue(UnicodeOffsets.scalarsEqual(try XCTUnwrap(resolved.selection.string), "\u{1D400}\u{1D401} end"))

        let mixed = try Fixture.open("mixed-scanned.pdf")
        let mx = PageTextExtractor.extract(mixed)
        XCTAssertEqual(LexicalSearch.find("lantern", in: mx).map(\.pageIndex), [2])
        XCTAssertEqual(Set(LexicalSearch.find("mixed", in: mx).map(\.pageIndex)), [0, 2])
        XCTAssertTrue(LexicalSearch.find("", in: mx).isEmpty)
    }
}
