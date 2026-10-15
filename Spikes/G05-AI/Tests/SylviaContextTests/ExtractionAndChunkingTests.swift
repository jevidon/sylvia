import Foundation
import G05TestSupport
import Testing
@testable import SylviaContext

/// Brief item 6: own XHTML extraction from Standard Ebooks fixtures and 300-600 word chunks on paragraph boundaries.
@Suite("EPUB extraction and chunking")
struct ExtractionAndChunkingTests {
    static let middlemarch = Result { try EPUBTextExtractor.extract(epubAt: RepoFixtures.url("epub/se-middlemarch.epub")) }
    static let walden = Result { try EPUBTextExtractor.extract(epubAt: RepoFixtures.url("epub/se-walden.epub")) }

    @Test func extractsBodyMatterInSpineOrder() throws {
        let work = try Self.middlemarch.get()
        #expect(work.title == "Middlemarch")
        #expect(work.author == "George Eliot")
        #expect(work.resourceHrefs.first == "text/book-1.xhtml")
        #expect(work.resourceHrefs.contains("text/chapter-1.xhtml"))
        #expect(!work.resourceHrefs.contains("text/colophon.xhtml"))
        #expect(!work.resourceHrefs.contains("text/uncopyright.xhtml"))
        // Ordinals strictly increase through the book.
        #expect(work.paragraphs.map(\.ordinal) == Array(0..<work.paragraphs.count))
        let first = try #require(work.paragraphs.first { $0.resourceHref == "text/chapter-1.xhtml" })
        // The epigraph comes first, with <br/> as a line break; the heading "I" is a label, not passage text.
        #expect(first.text == "Since I can do no good because a woman,\nReach constantly at something that is near it.")
        #expect(work.paragraphs.contains { $0.text.hasPrefix("Miss Brooke had that kind of beauty which seems to be thrown into relief by poor dress.") })
        #expect(!work.paragraphs.contains { $0.text == "I" })
    }

    @Test func waldenExtractsTheKnownPassage() throws {
        let work = try Self.walden.get()
        let passage = work.paragraphs.first { $0.text.contains("I went to the woods because I wished to live deliberately") }
        #expect(passage?.resourceHref == "text/where-i-lived-and-what-i-lived-for.xhtml")
    }

    @Test func chunksRespectTheParagraphAndSizeRules() throws {
        for work in [try Self.middlemarch.get(), try Self.walden.get()] {
            let policy = ChunkingPolicy()
            let chunks = Chunker.chunk(work.paragraphs, policy: policy)
            #expect(!chunks.isEmpty)
            let byOrdinal = Dictionary(uniqueKeysWithValues: work.paragraphs.map { ($0.ordinal, $0) })
            for chunk in chunks {
                // Rule 1: never more than 600 words.
                #expect(chunk.wordCount <= policy.maxWords)
                // Rule 2: one resource per chunk.
                #expect(byOrdinal[chunk.firstOrdinal]?.resourceHref == chunk.resourceHref)
                #expect(byOrdinal[chunk.lastOrdinal]?.resourceHref == chunk.resourceHref)
            }
            // Rule 3 and 5: whole paragraphs, each exactly once and in order; split pieces rejoin exactly.
            var rebuilt: [Int: [String]] = [:]
            for chunk in chunks {
                if chunk.pieceIndex != nil {
                    rebuilt[chunk.firstOrdinal, default: []].append(chunk.text)
                } else {
                    let texts = chunk.text.components(separatedBy: "\n\n")
                    #expect(texts.count == chunk.lastOrdinal - chunk.firstOrdinal + 1)
                    for (offset, text) in texts.enumerated() { rebuilt[chunk.firstOrdinal + offset, default: []].append(text) }
                }
            }
            #expect(rebuilt.count == work.paragraphs.count)
            for paragraph in work.paragraphs {
                let pieces = try #require(rebuilt[paragraph.ordinal])
                if pieces.count == 1 {
                    #expect(pieces[0] == paragraph.text)
                } else {
                    #expect(paragraph.wordCount > policy.maxWords)
                    // Each piece is an exact substring, in order, and together they cover every non-space character.
                    var cursor = paragraph.text.startIndex
                    for piece in pieces {
                        let range = try #require(paragraph.text.range(of: piece, range: cursor..<paragraph.text.endIndex))
                        #expect(paragraph.text[cursor..<range.lowerBound].allSatisfy { $0.isWhitespace })
                        cursor = range.upperBound
                    }
                    #expect(paragraph.text[cursor...].allSatisfy { $0.isWhitespace })
                }
            }
            // Rule 4: a short chunk is the last of its resource, or the next paragraph would not have fit.
            for (index, chunk) in chunks.enumerated() where chunk.wordCount < policy.minWords && chunk.pieceIndex == nil {
                guard index + 1 < chunks.count else { continue }
                let next = chunks[index + 1]
                let nextParagraph = try #require(byOrdinal[chunk.lastOrdinal + 1])
                let endsResource = next.resourceHref != chunk.resourceHref
                let nextWouldOverflow = chunk.wordCount + nextParagraph.wordCount > policy.maxWords
                #expect(endsResource || nextWouldOverflow || next.pieceIndex != nil,
                        "chunk \(chunk.chunkIndex) has \(chunk.wordCount) words without a reason")
            }
        }
    }

    @Test func zipReaderRejectsUnsafeArchives() throws {
        #expect(ZipReader.isSafe("epub/text/chapter-1.xhtml"))
        #expect(!ZipReader.isSafe("../etc/passwd"))
        #expect(!ZipReader.isSafe("epub/../../x"))
        #expect(!ZipReader.isSafe("/abs"))
        #expect(!ZipReader.isSafe("a\\b"))
        #expect(throws: ZipError.notAZip) { _ = try ZipReader(data: Data("not a zip at all, definitely not".utf8)) }
    }

    @Test func zipReaderDetectsCorruptedEntryBytes() throws {
        var data = try RepoFixtures.data("epub/se-walden.epub")
        let zip = try ZipReader(data: data)
        let entry = try #require(zip.entries["epub/text/solitude.xhtml"])
        // Flip one byte inside the compressed data of that entry.
        let local = entry.localHeaderOffset
        let start = local + 30 + Int(ZipReader.u16(data, local + 26)) + Int(ZipReader.u16(data, local + 28))
        data[start + entry.compressedSize / 2] ^= 0xFF
        let corrupted = try ZipReader(data: data)
        #expect(throws: (any Error).self) { _ = try corrupted.read("epub/text/solitude.xhtml") }
    }
}
