import Foundation
@testable import G01EPUBCore
import Testing

@Suite("Offsets, chunking and lexical search (plan 7.5, 9.1, 11.3)")
struct TextAndSearchTests {
    // U+1D509 (Fraktur F) is outside the BMP: one scalar, two UTF-16 code units.
    let text = "The scribe wrote \u{1D509}\u{1D52F}\u{1D51E}\u{1D528}\u{1D531}\u{1D532}\u{1D52F} letters beside the river, then drew a small \u{1F33F}."

    @Test("Scalar and UTF-16 offsets convert both ways around non-BMP characters")
    func offsets() throws {
        let r = try #require(text.range(of: "letters"))
        let scalar = TextOffsets.scalarRange(of: r, in: text)
        let utf16 = try #require(TextOffsets.utf16Range(fromScalarRange: scalar, in: text))
        // Seven non-BMP letters precede "letters": UTF-16 offsets are seven units larger.
        #expect(utf16.lowerBound == scalar.lowerBound + 7)
        #expect(utf16.count == scalar.count)
        #expect(TextOffsets.scalarRange(fromUTF16Range: utf16, in: text) == scalar)
        #expect(TextOffsets.substring(text, scalarRange: scalar) == "letters")
        // Same answer as NSString (UTF-16) indexing.
        #expect((text as NSString).range(of: "letters").location == utf16.lowerBound)
        // An offset between the two surrogates of U+1D509 is not a valid boundary.
        let f = (text as NSString).range(of: "\u{1D509}").location
        #expect(TextOffsets.scalarOffset(fromUTF16Offset: f + 1, in: text) == nil)
        #expect(TextOffsets.scalarOffset(fromUTF16Offset: f + 2, in: text) == TextOffsets.scalarOffset(fromUTF16Offset: f, in: text)! + 1)
        // Out of range.
        #expect(TextOffsets.utf16Offset(fromScalarOffset: text.unicodeScalars.count + 1, in: text) == nil)
    }

    func blocks(_ counts: [Int]) -> [ExtractedBlock] {
        counts.enumerated().map { i, words in
            let body = (0 ..< words).map { "w\(i)x\($0)" }.joined(separator: " ")
            return ExtractedBlock(resourceHref: "r.xhtml", index: i, text: body, role: "body", locatorJSON: "{}")
        }
    }

    @Test("Chunks are 300-600 words, keep whole blocks, and split only blocks longer than 600 words")
    func chunking() throws {
        let input = blocks([120, 90, 150, 40, 700, 200, 200, 260, 30])
        let chunks = Chunker(extractionVersion: "test-1").chunk(resourceHref: "r.xhtml", blocks: input)
        print("CHUNKS words=\(chunks.map(\.wordCount)) splits=\(chunks.map(\.splitsBlock))")
        // 120+90+150 reaches 300; 40 is flushed short because the next block is oversized; the 700-word block has no
        // sentence ends, so it is cut at a word boundary into 600 + 100; 200+200; then the resource tail 260+30.
        #expect(chunks.map(\.wordCount) == [360, 40, 600, 100, 400, 290])
        for c in chunks {
            #expect(c.wordCount <= 600)
            for part in c.parts {
                let piece = try #require(TextOffsets.substring(c.text, scalarRange: part.scalarStart ..< part.scalarEnd))
                let block = input[part.blockIndex].text
                if c.splitsBlock {
                    #expect(TextOffsets.substring(block, scalarRange: part.blockScalarStart ..< part.blockScalarStart + piece.unicodeScalars.count) == piece)
                } else {
                    #expect(piece == block, "a chunk part must be a whole block")
                }
            }
        }
        // Every block appears, in order, and only the 700-word block is split.
        let order = chunks.flatMap { $0.parts.map(\.blockIndex) }
        #expect(order == order.sorted())
        #expect(Set(order) == Set(0 ..< input.count))
        #expect(chunks.filter(\.splitsBlock).allSatisfy { $0.parts.allSatisfy { $0.blockIndex == 4 } })
    }

    @Test("FTS5 phrase search over chunks maps a hit back to its block, with user input escaped")
    func lexical() throws {
        let paragraphs = [
            "First paragraph about the orchard keeper and his small book.",
            "Second paragraph: " + text,
            "Third paragraph with Amélie and a \"quoted\" word.",
        ]
        let input = paragraphs.enumerated().map { ExtractedBlock(resourceHref: "c1.xhtml", index: $0, text: $1, role: "body", locatorJSON: "{}") }
        var chunker = Chunker(extractionVersion: "test-1")
        chunker.minWords = 5
        chunker.maxWords = 600
        let chunks = chunker.chunk(resourceHref: "c1.xhtml", blocks: input)
        let index = try LexicalIndex()
        print("SQLITE version=\(index.sqliteVersion)")
        for c in chunks { try index.add(c) }

        let results = try index.search("beside the river")
        let hit = try #require(results.first?.hit)
        #expect(hit.blockIndex == 1)
        let block = paragraphs[1]
        #expect(TextOffsets.substring(block, scalarRange: hit.blockScalarRange) == "beside the river")
        let utf16 = try #require(TextOffsets.utf16Range(fromScalarRange: hit.blockScalarRange, in: block))
        #expect((block as NSString).range(of: "beside the river").location == utf16.lowerBound)

        // Diacritic-insensitive lookup; the stored text keeps its accent.
        let accent = try #require(try index.search("Amelie").first?.hit)
        #expect(accent.matchedText == "Amélie")

        // FTS syntax in user input is treated as literal text, never as an operator.
        #expect(try index.search("orchard\" OR body:*").isEmpty)
        #expect(try index.search("NEAR(orchard book)").isEmpty)
        #expect(try index.search("\"quoted\"").count == 1)
    }

    @Test("Portable anchor round-trips with snake_case keys and an opaque reader locator")
    func anchorCoding() throws {
        let locator = try JSONValue(jsonString: #"{"href":"text/book-1.xhtml","type":"application/xhtml+xml","locations":{"progression":0.25},"text":{"highlight":"x"}}"#)
        let anchor = PortableEPUBAnchor(
            assetID: "ba28d451-0e31-4dca-9822-bdc10fdf1dfd", assetDigest: String(repeating: "a", count: 64),
            resourceHref: "text/book-1.xhtml", resourceMediaType: "application/xhtml+xml", exactText: "x", prefix: "a ", suffix: " b",
            textOffsets: .init(unit: "unicode_scalar", basis: "sylvia-extraction", extractionVersion: "v1", blockIndex: 3, start: 10, end: 11),
            progression: 0.25, totalProgression: 0.1, position: 4, segment: nil,
            reader: .init(adapter: "readium-swift", adapterVersion: "3.11.0", locator: locator)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(anchor)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"exact_text\"") && json.contains("\"text_offsets\"") && json.contains("\"adapter_version\""))
        #expect(try JSONDecoder().decode(PortableEPUBAnchor.self, from: data) == anchor)
    }
}
