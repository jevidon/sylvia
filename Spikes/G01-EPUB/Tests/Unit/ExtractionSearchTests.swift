@testable import EPUBHarness
import Foundation
import G01EPUBCore
@preconcurrency import ReadiumShared
import XCTest

/// Deliverable 7: resource-by-resource extraction with Readium's content iterator, 300-600 word chunks that keep
/// paragraph boundaries, an FTS5 lexical index, and a hit that reopens the navigator at the passage. Simulator.
@MainActor final class ExtractionSearchTests: XCTestCase {
    override func tearDown() async throws { TestHost.tearDown() }

    func testChunksAndALexicalHitReopenThePassage() async throws {
        let screen = try await TestHost.open("se-meditations.epub")
        let s = screen.session
        let clock = ContinuousClock()
        let start = clock.now
        let extraction = await EPUBExtraction.extract(s.publication)
        let seconds = (clock.now - start).seconds
        XCTAssertEqual(extraction.map(\.href), s.publication.readingOrder.map(\.href).filter { href in extraction.contains { $0.href == href } },
                       "resources come out in reading order")
        let chunks = extraction.flatMap(\.chunks)
        XCTAssertGreaterThan(chunks.count, 20)
        // Every chunk is within 600 words; chunks under 300 words are resource tails or precede an oversized block.
        for (r, resource) in extraction.enumerated() {
            for (i, c) in resource.chunks.enumerated() {
                XCTAssertLessThanOrEqual(c.wordCount, 600, c.id)
                XCTAssertEqual(c.extractionVersion, EPUBExtraction.extractionVersion)
                if c.wordCount < 300, i < resource.chunks.count - 1 {
                    let next = resource.chunks[i + 1]
                    let nextBlockWords = next.parts.first.map { Chunker.wordCount(resource.blocks[$0.blockIndex].text) } ?? 0
                    XCTAssertTrue(next.splitsBlock || c.wordCount + nextBlockWords > 600, "short chunk \(c.id) in resource \(r)")
                }
                for p in c.parts where !c.splitsBlock {
                    XCTAssertEqual(TextOffsets.substring(c.text, scalarRange: p.scalarStart ..< p.scalarEnd), resource.blocks[p.blockIndex].text,
                                   "a chunk part is a whole paragraph")
                }
            }
        }

        let index = try LexicalIndex()
        for c in chunks { try index.add(c) }
        let query = "the perception of this will be more apparent to thee"
        let results = try index.search(query)
        let top = try XCTUnwrap(results.first)
        let hit = try XCTUnwrap(top.hit, "phrase not mapped into a single block")
        let resource = try XCTUnwrap(extraction.first { $0.href == hit.chunk.resourceHref })
        XCTAssertEqual(resource.href, "epub/text/book-7.xhtml")
        let locator = try EPUBExtraction.locator(for: hit, blocks: resource.blocks)
        XCTAssertNotNil(locator.locations.otherLocations["cssSelector"], "content-iterator locators carry a CSS selector")
        let reader = ReadiumReaderSession.readerLocator(locator)
        let went = await s.navigate(to: reader)
        XCTAssertTrue(went)
        var landed = try await ReaderProbe.inspect(s, exact: hit.matchedText, prefix: "", highlightID: nil)
        let visible = await ReaderProbe.wait(timeout: .seconds(5)) {
            landed = (try? await ReaderProbe.inspect(s, exact: hit.matchedText, prefix: "", highlightID: nil)) ?? landed
            return landed.visible
        }
        XCTAssertTrue(visible, "search hit not on screen: \(landed.raw)")
        // The navigator reports the new location once it is idle again.
        let located = await ReaderProbe.wait(timeout: .seconds(5)) { s.currentLocator?.href == "epub/text/book-7.xhtml" }
        XCTAssertTrue(located, "current locator is \(s.currentLocator?.href ?? "nil")")

        // The ReaderSession contract's search (Sylvia's extraction and FTS5 index) returns a locator that reopens the
        // passage; go back to the start first so the jump is real.
        let toStart = await s.followLink(href: "epub/text/book-1.xhtml")
        XCTAssertTrue(toStart)
        let sessionHits = try await s.search(query)
        let first = try XCTUnwrap(sessionHits.first, "ReaderSession.search found nothing")
        XCTAssertEqual(first.href, "epub/text/book-7.xhtml")
        XCTAssertEqual(first.textHighlight?.lowercased(), query.lowercased())
        let went2 = await s.navigate(to: first)
        XCTAssertTrue(went2)
        var landed2 = landed
        let visible2 = await ReaderProbe.wait(timeout: .seconds(5)) {
            landed2 = (try? await ReaderProbe.inspect(s, exact: first.textHighlight ?? query, prefix: "", highlightID: nil)) ?? landed2
            return landed2.visible
        }
        XCTAssertTrue(visible2, "ReaderSession.search hit not on screen: \(landed2.raw)")
        XCTAssertEqual(s.extraction?.filter { $0.status == "indexed" }.count, extraction.count)

        // Readium's own search service on the same phrase, for comparison only (the adapter does not use it).
        let readiumHits = try await s.readiumSearch(query)
        XCTAssertFalse(readiumHits.isEmpty)

        let words = chunks.map(\.wordCount)
        ReaderProbe.writeEvidence("extraction-search.json", json: [
            "environment": CompatibilityMatrixTests.environment,
            "fixture": "se-meditations.epub",
            "extraction_version": EPUBExtraction.extractionVersion,
            "extraction_seconds": (seconds * 1000).rounded() / 1000,
            "resources": extraction.count, "blocks": extraction.reduce(0) { $0 + $1.blocks.count }, "chunks": chunks.count,
            "chunk_words_min": words.min() ?? 0, "chunk_words_max": words.max() ?? 0,
            "chunks_under_300_words": words.filter { $0 < 300 }.count, "chunks_splitting_a_block": chunks.filter(\.splitsBlock).count,
            "query": query, "fts_results": results.count, "sqlite": index.sqliteVersion,
            "hit_chunk": hit.chunk.id, "hit_block_index": hit.blockIndex,
            "hit_chunk_scalar_range": [hit.chunkScalarRange.lowerBound, hit.chunkScalarRange.upperBound],
            "hit_block_scalar_range": [hit.blockScalarRange.lowerBound, hit.blockScalarRange.upperBound],
            "reopen_locator": reader.json, "visible_after_navigate": landed.visible,
            "session_search_results": sessionHits.count, "session_search_first_locator": first.json,
            "session_search_visible_after_navigate": landed2.visible,
            "readium_search_results": readiumHits.count, "readium_search_first_locator": readiumHits.first?.json ?? "",
        ])
    }

    /// Search mapping across non-BMP text: Sylvia's scalar offsets convert to the DOM's UTF-16 index exactly.
    func testNonBMPHitOffsetsConvertAtTheAdapterBoundary() async throws {
        let screen = try await TestHost.open("g01-unicode.epub")
        let s = screen.session
        let extraction = await EPUBExtraction.extract(s.publication)
        let index = try LexicalIndex()
        for r in extraction { for c in r.chunks { try index.add(c) } }
        let query = "letters beside the river"
        let hit = try XCTUnwrap(try index.search(query).first?.hit)
        let resource = try XCTUnwrap(extraction.first { $0.href == hit.chunk.resourceHref })
        let block = resource.blocks[hit.blockIndex]
        let utf16 = try XCTUnwrap(TextOffsets.utf16Range(fromScalarRange: hit.blockScalarRange, in: block.text))
        XCTAssertEqual(utf16.lowerBound - hit.blockScalarRange.lowerBound, 7, "seven non-BMP scalars precede the hit")
        let went = await s.navigate(to: ReadiumReaderSession.readerLocator(try EPUBExtraction.locator(for: hit, blocks: resource.blocks)))
        XCTAssertTrue(went)
        let dom = try await ReaderProbe.evaluate(s, "document.getElementById('p-nonbmp').textContent.indexOf(\(ReaderProbe.jsString(query)))")
        XCTAssertEqual(Int(dom), utf16.lowerBound, "DOM UTF-16 index equals the converted Sylvia offset")
        let i = try await ReaderProbe.inspect(s, exact: query, prefix: "", highlightID: nil)
        XCTAssertTrue(i.visible)
        ReaderProbe.writeEvidence("extraction-nonbmp.json", json: [
            "block_text": block.text, "query": query,
            "sylvia_scalar_range": [hit.blockScalarRange.lowerBound, hit.blockScalarRange.upperBound],
            "converted_utf16_range": [utf16.lowerBound, utf16.upperBound], "dom_indexOf_utf16": Int(dom) ?? -1,
        ])
    }
}
