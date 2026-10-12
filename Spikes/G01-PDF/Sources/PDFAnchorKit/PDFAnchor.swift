import Foundation

/// Proposed portable PDF anchor (plan 7.5, A.1). JSON keys are snake_case.
///
/// One anchor describes one captured selection. A selection that spans pages, or that PDFKit returns as more than
/// one contiguous text range on a page, has one segment per contiguous range, in document order.
///
/// Everything outside `reader_locator` is portable: another platform can resolve it with its own PDF text
/// extractor (by page index, scalar range and exact text) and draw it (from normalized rectangles and rotation).
/// `reader_locator` holds PDFKit's native UTF-16 ranges, which only this adapter interprets.
public struct PDFAnchor: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    /// Always "pdf".
    public var kind: String
    public var assetID: UUID?
    /// Lowercase hex SHA-256 of the PDF file's bytes. The anchor is only exact for this asset.
    public var assetSHA256: String
    /// The quotation exactly as PDFKit returned it for the user's selection (scalar-exact; never normalized).
    /// For a selection with several segments PDFKit joins the segment texts with one "\n".
    public var exactText: String
    public var segments: [Segment]
    public var extraction: ExtractionVersion
    /// Adapter-opaque: PDFKit's native UTF-16 ranges. Other platforms ignore it (Contracts/README.md, Units).
    public var readerLocator: ReaderLocator

    public init(
        version: Int = PDFAnchor.currentVersion,
        assetID: UUID?,
        assetSHA256: String,
        exactText: String,
        segments: [Segment],
        extraction: ExtractionVersion,
        readerLocator: ReaderLocator
    ) {
        self.version = version
        self.kind = "pdf"
        self.assetID = assetID
        self.assetSHA256 = assetSHA256
        self.exactText = exactText
        self.segments = segments
        self.extraction = extraction
        self.readerLocator = readerLocator
    }

    public struct Segment: Codable, Hashable, Sendable {
        /// Zero-based physical page index in the file.
        public var pageIndex: Int
        /// Printed label from the PDF's /PageLabels, or nil when the file supplies none.
        public var pageLabel: String?
        /// The page's /Rotate (inherited if needed), normalized to 0, 90, 180 or 270 degrees clockwise.
        public var pageRotation: Int
        /// The box the rectangles are normalized to, with its rectangle in PDF user-space points.
        public var pageBox: PageBox
        /// This segment's text, exactly as it appears in the page text at `textRange`.
        public var text: String
        public var textRange: TextRange
        /// Up to `PDFAnchorBuilder.contextScalars` scalars of page text before and after, for re-anchoring.
        public var prefix: String
        public var suffix: String
        /// One rectangle per line, normalized to `pageBox`, in unrotated page space (origin lower-left, y up).
        public var lineRects: [NormalizedRect]
        /// SHA-256 of the page text's UTF-8 bytes; detects extraction drift before `textRange` is trusted.
        public var pageTextSHA256: String

        public init(
            pageIndex: Int,
            pageLabel: String?,
            pageRotation: Int,
            pageBox: PageBox,
            text: String,
            textRange: TextRange,
            prefix: String,
            suffix: String,
            lineRects: [NormalizedRect],
            pageTextSHA256: String
        ) {
            self.pageIndex = pageIndex
            self.pageLabel = pageLabel
            self.pageRotation = pageRotation
            self.pageBox = pageBox
            self.text = text
            self.textRange = textRange
            self.prefix = prefix
            self.suffix = suffix
            self.lineRects = lineRects
            self.pageTextSHA256 = pageTextSHA256
        }
    }

    public struct PageBox: Codable, Hashable, Sendable {
        /// "crop": the PDF CropBox (defaulting to the MediaBox), which is what PDFKit displays and extracts.
        public var name: String
        /// [x, y, width, height] in PDF user-space points.
        public var rect: [Double]

        public init(name: String, rect: [Double]) {
            self.name = name
            self.rect = rect
        }
    }

    public struct TextRange: Codable, Hashable, Sendable {
        /// Always "unicode_scalar" in the portable envelope.
        public var unit: String
        /// Half-open range [start, end) into the page text.
        public var start: Int
        public var end: Int

        public static let unicodeScalarUnit = "unicode_scalar"

        public init(_ range: ScalarRange) {
            self.unit = TextRange.unicodeScalarUnit
            self.start = range.start
            self.end = range.end
        }

        public var scalarRange: ScalarRange { ScalarRange(start: start, end: end) }
    }

    public struct ReaderLocator: Codable, Hashable, Sendable {
        /// "pdfkit": ranges are PDFKit character indices (UTF-16 code units of `PDFPage.string`).
        public var adapter: String
        public var utf16Ranges: [UTF16Range]

        public init(adapter: String, utf16Ranges: [UTF16Range]) {
            self.adapter = adapter
            self.utf16Ranges = utf16Ranges
        }
    }

    public struct UTF16Range: Codable, Hashable, Sendable {
        public var pageIndex: Int
        public var location: Int
        public var length: Int

        public init(pageIndex: Int, location: Int, length: Int) {
            self.pageIndex = pageIndex
            self.location = location
            self.length = length
        }
    }

    enum CodingKeys: String, CodingKey {
        case version, kind
        case assetID = "asset_id"
        case assetSHA256 = "asset_sha256"
        case exactText = "exact_text"
        case segments, extraction
        case readerLocator = "reader_locator"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(kind, forKey: .kind)
        try c.encode(assetID, forKey: .assetID)
        try c.encode(assetSHA256, forKey: .assetSHA256)
        try c.encode(exactText, forKey: .exactText)
        try c.encode(segments, forKey: .segments)
        try c.encode(extraction, forKey: .extraction)
        try c.encode(readerLocator, forKey: .readerLocator)
    }
}

extension PDFAnchor.Segment {
    enum CodingKeys: String, CodingKey {
        case pageIndex = "page_index"
        case pageLabel = "page_label"
        case pageRotation = "page_rotation"
        case pageBox = "page_box"
        case text
        case textRange = "text_range"
        case prefix, suffix
        case lineRects = "line_rects"
        case pageTextSHA256 = "page_text_sha256"
    }

    // Encode page_label explicitly as null when absent so the envelope always states it.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pageIndex, forKey: .pageIndex)
        try c.encode(pageLabel, forKey: .pageLabel)
        try c.encode(pageRotation, forKey: .pageRotation)
        try c.encode(pageBox, forKey: .pageBox)
        try c.encode(text, forKey: .text)
        try c.encode(textRange, forKey: .textRange)
        try c.encode(prefix, forKey: .prefix)
        try c.encode(suffix, forKey: .suffix)
        try c.encode(lineRects, forKey: .lineRects)
        try c.encode(pageTextSHA256, forKey: .pageTextSHA256)
    }
}

extension PDFAnchor.ReaderLocator {
    enum CodingKeys: String, CodingKey {
        case adapter
        case utf16Ranges = "utf16_ranges"
    }
}

extension PDFAnchor.UTF16Range {
    enum CodingKeys: String, CodingKey {
        case pageIndex = "page_index"
        case location, length
    }
}

public enum AnchorJSON {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
