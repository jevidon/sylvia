import Foundation
import G01EPUBCore

/// Turns reader selections into the portable capture shape (plan 7.5, 11.1, Appendix A.1).
public enum CaptureBuilder {
    /// A quotation made of one or more selections, in reading order. Readium renders each resource in its own web
    /// view, so one gesture can never select across a resource boundary; a quotation that continues into the next
    /// resource is captured as one selection per resource and stored as ordered anchors. Nothing is truncated:
    /// `quotedText` is the selections' exact text joined by `segmentSeparator`.
    public struct Quotation: Sendable, Equatable {
        public var quotedText: String
        public var anchors: [PortableEPUBAnchor]
    }

    public static let segmentSeparator = "\n\n"

    public static func anchor(for selection: ReaderSelection, assetID: String, assetDigest: String,
                              extraction: [EPUBExtraction.Resource]?, segment: PortableEPUBAnchor.Segment? = nil) throws -> PortableEPUBAnchor {
        let locatorJSON = try JSONValue(jsonString: selection.locator.json)
        return PortableEPUBAnchor(
            assetID: assetID, assetDigest: assetDigest,
            resourceHref: selection.locator.href, resourceMediaType: selection.locator.mediaType,
            exactText: selection.exactText, prefix: selection.prefix, suffix: selection.suffix,
            textOffsets: extraction.flatMap { offsets(for: selection, in: $0) },
            progression: selection.locator.progression, totalProgression: selection.locator.totalProgression,
            position: selection.locator.position, segment: segment,
            reader: .init(adapter: ReadiumReaderSession.adapterName, adapterVersion: ReadiumReaderSession.adapterVersion, locator: locatorJSON)
        )
    }

    public static func quotation(from selections: [ReaderSelection], assetID: String, assetDigest: String,
                                 extraction: [EPUBExtraction.Resource]?) throws -> Quotation {
        let anchors = try selections.enumerated().map { i, s in
            try anchor(for: s, assetID: assetID, assetDigest: assetDigest, extraction: extraction,
                       segment: selections.count > 1 ? .init(index: i, count: selections.count) : nil)
        }
        return Quotation(quotedText: selections.map(\.exactText).joined(separator: segmentSeparator), anchors: anchors)
    }

    /// Maps the selection onto Sylvia's extraction of the same resource, in Unicode scalars. Returns nil when the
    /// selected text is not inside a single extracted block (for example a selection spanning two paragraphs) or is
    /// ambiguous: the opaque reader locator and the exact text plus context still anchor it (plan 7.5 reanchoring).
    static func offsets(for selection: ReaderSelection, in extraction: [EPUBExtraction.Resource]) -> PortableEPUBAnchor.TextOffsetSpan? {
        guard let resource = extraction.first(where: { $0.href == selection.locator.href }) else { return nil }
        let exact = collapse(selection.exactText)
        guard !exact.isEmpty else { return nil }
        let prefixTail = String(collapse(selection.prefix).suffix(24))
        var matches: [(block: Int, range: Range<Int>, before: String)] = []
        for block in resource.blocks {
            var searchStart = block.text.startIndex
            while let r = block.text.range(of: exact, range: searchStart ..< block.text.endIndex) {
                matches.append((block.index, TextOffsets.scalarRange(of: r, in: block.text), collapse(String(block.text[..<r.lowerBound]))))
                searchStart = r.upperBound
            }
        }
        // Several occurrences: keep the one whose preceding text agrees with the reader's prefix context
        // (or, at the start of a block, whose prefix ends with the block's leading text).
        if matches.count > 1, !prefixTail.isEmpty {
            matches = matches.filter { $0.before.hasSuffix(prefixTail) || (!$0.before.isEmpty && prefixTail.hasSuffix($0.before)) || $0.before.isEmpty }
        }
        guard matches.count == 1, let match = matches.first else { return nil }
        return .init(unit: "unicode_scalar", basis: "sylvia-extraction", extractionVersion: EPUBExtraction.extractionVersion,
                     blockIndex: match.block, start: match.range.lowerBound, end: match.range.upperBound)
    }

    static func collapse(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
