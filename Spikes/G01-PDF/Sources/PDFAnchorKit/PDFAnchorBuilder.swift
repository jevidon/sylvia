import CoreGraphics
import Foundation
import PDFKit

public enum AnchorCaptureError: Error, Equatable, Sendable {
    /// PDFKit returned no text for the selection.
    case emptySelection
    /// The selection touches a page without selectable text (plan 9.2: no guessed text).
    case noSelectableText(pageIndex: Int)
    /// The PDF does not allow copying text, so Sylvia does not capture a quotation from it.
    case textRestricted
    /// The selection's page is not in the source document.
    case pageNotInDocument
    /// The page text PDFKit returns now differs from the stored extraction (the extraction cache is stale).
    case extractionMismatch(pageIndex: Int)
    /// The anchor's stored ranges, rebuilt into a selection the way `PDFAnchorResolver` rebuilds a stored anchor, would
    /// not give back the quotation the selection shows, scalar for scalar (or a range would not give back its
    /// segment's text). Sylvia never stores an anchor that cannot give back its own quotation (plan 2.2 I-05).
    case quotationMismatch
    case offsetConversion(OffsetConversionError)
    case geometry(GeometryError)
}

/// Builds a `PDFAnchor` from a PDFKit selection. This is the adapter boundary: PDFKit's UTF-16 character ranges
/// are converted to Unicode scalar offsets here and nowhere else (plan 7.5).
public enum PDFAnchorBuilder {
    /// Scalars of page text kept before and after each segment for re-anchoring.
    public static let contextScalars = 32

    public static func capture(
        selection: PDFSelection,
        in source: PDFSourceDocument,
        extraction: DocumentExtraction,
        assetID: UUID? = nil
    ) throws(AnchorCaptureError) -> PDFAnchor {
        guard source.permissions.allowsCopying else { throw .textRestricted }
        guard let exact = selection.string, !exact.isEmpty else { throw .emptySelection }

        var segments: [PDFAnchor.Segment] = []
        var utf16Ranges: [PDFAnchor.UTF16Range] = []
        let pages = selection.pages
            .map { (index: source.index(of: $0), page: $0) }
            .sorted { $0.index < $1.index }
        for (pageIndex, page) in pages {
            guard pageIndex != NSNotFound, pageIndex >= 0 else { throw .pageNotInDocument }
            let count = selection.numberOfTextRanges(on: page)
            guard count > 0 else { continue }
            for i in 0..<count {
                let reported = selection.range(at: i, on: page)
                guard reported.location != NSNotFound, reported.length > 0 else { continue }
                let range = withoutTrailingLineBreaks(reported, on: page)
                let segment = try makeSegment(utf16Range: range, pageIndex: pageIndex, page: page, source: source, extraction: extraction)
                segments.append(segment)
                utf16Ranges.append(PDFAnchor.UTF16Range(pageIndex: pageIndex, location: range.location, length: range.length))
            }
        }
        guard !segments.isEmpty else { throw .emptySelection }
        let anchor = PDFAnchor(
            assetID: assetID,
            assetSHA256: source.sha256,
            exactText: exact,
            segments: segments,
            extraction: extraction.version,
            readerLocator: PDFAnchor.ReaderLocator(adapter: "pdfkit", utf16Ranges: utf16Ranges)
        )
        // The stored ranges must give back exactly the quotation when the anchor is restored. PDFKit composes a
        // selection's text itself, and not with one fixed separator: in the shapes `ComposedSelectionTests` checks,
        // pieces on one page come out next to each other with nothing between them, a piece that ends at a line's end
        // keeps that line break when another piece follows on its page, and pages are joined with "\n". So the check is
        // the restore itself: the same extraction, each stored range rebuilt into a selection on its page and combined
        // in document order exactly as `PDFAnchorResolver` does it, must give back each segment's text and `exact`.
        guard PDFAnchorResolver.resolveExactly(anchor, in: source, extraction: extraction) != nil else { throw .quotationMismatch }
        return anchor
    }

    /// An anchor for a known scalar range of a page's extracted text (used for search hits and tests).
    public static func anchor(
        forScalarRange range: ScalarRange,
        onPage pageIndex: Int,
        in source: PDFSourceDocument,
        extraction: DocumentExtraction,
        assetID: UUID? = nil
    ) throws(AnchorCaptureError) -> PDFAnchor {
        guard let pageText = extraction.page(pageIndex)?.text else { throw .noSelectableText(pageIndex: pageIndex) }
        let utf16: NSRange
        do {
            utf16 = try UnicodeOffsets.utf16Range(fromScalar: range, in: pageText)
        } catch {
            throw .offsetConversion(error)
        }
        guard let page = source.page(at: pageIndex), let selection = page.selection(for: utf16) else {
            throw .pageNotInDocument
        }
        return try capture(selection: selection, in: source, extraction: extraction, assetID: assetID)
    }

    /// PDFKit reports a selection that ends with a line's last character with a range that also covers the line
    /// break after it, although the selection's text stops before the break. `LineEndSelectionTests` asserts this on
    /// iOS 26.5 for a range to a line's end, the last word, the whole line, a drag ending 6 pt past the line's last
    /// character and two lines ending at a line's end, on three pages (labels-multipage.pdf page index 3, the first
    /// left-column line of two-column.pdf and the /Rotate 90 page of rotated.pdf), and for every line but the last of
    /// text-layout.pdf's rotated-text page; `ComposedSelectionTests` for the end of a selection across two pages and
    /// for pieces of a composed selection. Stored as reported, the range would quote "water\n" for a selection of
    /// "water", and the anchor would never restore. Trailing line breaks are dropped while PDFKit gives the same text
    /// without them; a break that changes the text is kept (and the restore check in `capture` then decides).
    static func withoutTrailingLineBreaks(_ range: NSRange, on page: PDFPage) -> NSRange {
        guard let pageText = page.string, let reported = page.selection(for: range)?.string else { return range }
        let units = pageText as NSString
        var trimmed = range
        while trimmed.length > 1, NSMaxRange(trimmed) <= units.length {
            let last = units.character(at: NSMaxRange(trimmed) - 1)
            guard last == 0x0A || last == 0x0D else { break } // "\n" or "\r"
            let shorter = NSRange(location: trimmed.location, length: trimmed.length - 1)
            guard let shorterText = page.selection(for: shorter)?.string, UnicodeOffsets.scalarsEqual(shorterText, reported) else { break }
            trimmed = shorter
        }
        return trimmed
    }

    static func makeSegment(
        utf16Range: NSRange,
        pageIndex: Int,
        page: PDFPage,
        source: PDFSourceDocument,
        extraction: DocumentExtraction
    ) throws(AnchorCaptureError) -> PDFAnchor.Segment {
        guard let pageExtraction = extraction.page(pageIndex), let pageText = pageExtraction.text,
              let pageTextSHA = pageExtraction.textSHA256
        else {
            throw .noSelectableText(pageIndex: pageIndex)
        }
        // PDFKit's ranges index into the live `PDFPage.string`; the anchor's offsets index into the stored
        // extraction. They must be the same text or the conversion would be silently wrong.
        guard let live = page.string, UnicodeOffsets.scalarsEqual(live, pageText) else {
            throw .extractionMismatch(pageIndex: pageIndex)
        }
        let scalarRange: ScalarRange
        let text: String
        let prefix: String
        let suffix: String
        do {
            scalarRange = try UnicodeOffsets.scalarRange(fromUTF16: utf16Range, in: pageText)
            text = try UnicodeOffsets.substring(pageText, scalars: scalarRange)
            let total = UnicodeOffsets.scalarCount(pageText)
            prefix = try UnicodeOffsets.substring(
                pageText, scalars: ScalarRange(start: max(0, scalarRange.start - contextScalars), end: scalarRange.start))
            suffix = try UnicodeOffsets.substring(
                pageText, scalars: ScalarRange(start: scalarRange.end, end: min(total, scalarRange.end + contextScalars)))
        } catch {
            throw .offsetConversion(error)
        }
        let box = page.bounds(for: PDFSourceDocument.anchorBox)
        let rotation: PageRotation
        do {
            rotation = try PageRotation(degrees: page.rotation)
        } catch {
            throw .geometry(error)
        }
        let lines = try lineRects(forUTF16Range: utf16Range, on: page, box: box)
        return PDFAnchor.Segment(
            pageIndex: pageIndex,
            pageLabel: source.printedLabel(forPageAt: pageIndex),
            pageRotation: rotation.rawValue,
            pageBox: PDFAnchor.PageBox(
                name: PDFSourceDocument.anchorBoxName,
                rect: [box.minX, box.minY, box.width, box.height].map(Double.init)
            ),
            text: text,
            textRange: PDFAnchor.TextRange(scalarRange),
            prefix: prefix,
            suffix: suffix,
            lineRects: lines,
            pageTextSHA256: pageTextSHA
        )
    }

    /// One normalized rectangle per line of the range, in unrotated page space, in reading order.
    static func lineRects(forUTF16Range range: NSRange, on page: PDFPage, box: CGRect) throws(AnchorCaptureError) -> [NormalizedRect] {
        guard let selection = page.selection(for: range) else { return [] }
        var out: [NormalizedRect] = []
        for line in selection.selectionsByLine() {
            let r = line.bounds(for: page)
            guard r.width > 0, r.height > 0, !r.isNull else { continue }
            do {
                out.append(try PageGeometry.normalize(r, in: box))
            } catch {
                throw .geometry(error)
            }
        }
        return out
    }
}
