import Foundation
import G01EPUBCore
@preconcurrency import ReadiumShared

/// Resource-by-resource text extraction for "Search this book" (plan 9.1, 11.3), using Readium's content iterator.
/// Offsets inside the extraction are Unicode scalars (plan 7.5); Readium's own locators carry no offsets.
public enum EPUBExtraction {
    /// Bump when Readium, the sanitizer or the chunker changes in a way that can move text.
    public static let extractionVersion = "readium-swift-3.11.0+html-content-iterator+sylvia-sanitizer-2+chunker-1"

    public struct Resource: Sendable {
        public var href: String
        public var blocks: [ExtractedBlock]
        public var chunks: [TextChunk]
        /// Per-resource coverage for "Search this book" (plan 11.3): `indexed`, `no_text`, or, when the adapter served
        /// a placeholder instead of the resource (plan 8.3), `unavailable_` + the reason: `excessive_nesting`,
        /// `unsupported_markup`, `time_budget`, `verification_failed` or `active_content`.
        public var status: String = "indexed"
    }

    /// Extracts through the adapter's sanitized publication and reports a status for every reading-order resource,
    /// including ones with no text and ones the sanitizer withheld.
    public static func extract(_ opened: OpenedEPUB, isolation: isolated (any Actor)? = #isolation) async -> [Resource] {
        let extracted = await extract(opened.publication)
        let withheld = opened.sanitizer.withheldReasons
        var byHref = Dictionary(extracted.map { ($0.href, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [Resource] = []
        for link in opened.publication.readingOrder {
            let href = link.url().normalized.string
            if let reason = withheld[href] {
                // The placeholder's own text is never indexed.
                byHref.removeValue(forKey: href)
                out.append(Resource(href: href, blocks: [], chunks: [], status: reason.extractionStatus))
            } else if let r = byHref.removeValue(forKey: href) {
                out.append(r)
            } else {
                out.append(Resource(href: href, blocks: [], chunks: [], status: "no_text"))
            }
        }
        return out
    }

    /// Runs in the caller's isolation (Readium's `Publication` is not `Sendable`). A product indexer would open its
    /// own `Publication` on a background actor.
    public static func extract(_ publication: Publication, chunker: Chunker = Chunker(extractionVersion: extractionVersion),
                               isolation: isolated (any Actor)? = #isolation) async -> [Resource] {
        guard let content = publication.content() else { return [] }
        var order: [String] = []
        var blocksByHref: [String: [ExtractedBlock]] = [:]
        let iterator = content.iterator()
        var failures = 0
        while true {
            let element: ContentElement?
            do { element = try await iterator.next() } catch {
                // Readium skips to the next element after a failure; stop if it keeps failing.
                failures += 1
                if failures > 100 { break }
                continue
            }
            guard let element else { break }
            guard let text = element as? TextContentElement, let body = text.text,
                  !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let href = text.locator.href.string
            if blocksByHref[href] == nil { order.append(href); blocksByHref[href] = [] }
            let index = blocksByHref[href]!.count
            blocksByHref[href]!.append(ExtractedBlock(
                resourceHref: href, index: index, text: body, role: String(describing: text.role),
                locatorJSON: (try? text.locator.jsonString()) ?? "{}"
            ))
        }
        return order.map { href in
            let blocks = blocksByHref[href] ?? []
            return Resource(href: href, blocks: blocks, chunks: chunker.chunk(resourceHref: href, blocks: blocks))
        }
    }

    /// Builds the reader locator that reopens a lexical hit: the block's own locator (CSS selector, progression)
    /// with the exact matched text and up to `context` scalars of surrounding block text.
    public static func locator(for hit: ChunkHit, blocks: [ExtractedBlock], context: Int = 64) throws -> Locator {
        let block = blocks[hit.blockIndex]
        let base = try Locator(jsonString: block.locatorJSON)
        guard let exact = TextOffsets.substring(block.text, scalarRange: hit.blockScalarRange) else {
            throw ReaderOpenError.unreadable("block locator")
        }
        let count = block.text.unicodeScalars.count
        let before = TextOffsets.substring(block.text, scalarRange: max(0, hit.blockScalarRange.lowerBound - context) ..< hit.blockScalarRange.lowerBound) ?? ""
        let after = TextOffsets.substring(block.text, scalarRange: hit.blockScalarRange.upperBound ..< min(count, hit.blockScalarRange.upperBound + context)) ?? ""
        return base.copy(text: { $0 = Locator.Text(after: after, before: before, highlight: exact) })
    }
}
