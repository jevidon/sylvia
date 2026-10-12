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
                let range = selection.range(at: i, on: page)
                guard range.location != NSNotFound, range.length > 0 else { continue }
                let segment = try makeSegment(utf16Range: range, pageIndex: pageIndex, page: page, source: source, extraction: extraction)
                segments.append(segment)
                utf16Ranges.append(PDFAnchor.UTF16Range(pageIndex: pageIndex, location: range.location, length: range.length))
            }
        }
        guard !segments.isEmpty else { throw .emptySelection }
        return PDFAnchor(
            assetID: assetID,
            assetSHA256: source.sha256,
            exactText: exact,
            segments: segments,
            extraction: extraction.version,
            readerLocator: PDFAnchor.ReaderLocator(adapter: "pdfkit", utf16Ranges: utf16Ranges)
        )
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
