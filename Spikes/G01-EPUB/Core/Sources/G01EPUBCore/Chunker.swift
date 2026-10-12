import Foundation

/// One block of text extracted from a publication resource, in reading order (for Readium: one
/// `TextContentElement`). `locatorJSON` is the reader's own locator for the block, kept adapter-opaque.
public struct ExtractedBlock: Sendable, Codable, Equatable {
    public var resourceHref: String
    public var index: Int
    public var text: String
    public var role: String
    public var locatorJSON: String

    public init(resourceHref: String, index: Int, text: String, role: String, locatorJSON: String) {
        self.resourceHref = resourceHref
        self.index = index
        self.text = text
        self.role = role
        self.locatorJSON = locatorJSON
    }
}

/// A search chunk: 300-600 words of one resource, built from whole blocks (paragraph boundaries preserved).
public struct TextChunk: Sendable, Codable, Equatable {
    public struct Part: Sendable, Codable, Equatable {
        /// Index of the block in the resource's extraction.
        public var blockIndex: Int
        /// Unicode scalar range of the block's text inside `TextChunk.text`.
        public var scalarStart: Int
        public var scalarEnd: Int
        /// Scalar offset of this part inside the block's own text (non-zero only for a split oversized block).
        public var blockScalarStart: Int
    }

    public var id: String
    public var resourceHref: String
    public var ordinal: Int
    public var extractionVersion: String
    public var text: String
    public var wordCount: Int
    public var parts: [Part]
    /// True when the chunk holds part of a single block longer than `maxWords` (split at a sentence end).
    public var splitsBlock: Bool
}

public struct Chunker: Sendable {
    public var minWords = 300
    public var maxWords = 600
    public var extractionVersion: String
    public static let separator = "\n\n"

    public init(extractionVersion: String) { self.extractionVersion = extractionVersion }

    public static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// Chunks one resource. Chunks never cross a resource boundary; a block is never split unless it alone exceeds
    /// `maxWords`, in which case it is cut at sentence ends.
    public func chunk(resourceHref: String, blocks: [ExtractedBlock]) -> [TextChunk] {
        var chunks: [TextChunk] = []
        var pending: [(block: ExtractedBlock, text: String, offset: Int)] = []
        var pendingWords = 0

        func flush(splits: Bool = false) {
            guard !pending.isEmpty else { return }
            var text = ""
            var parts: [TextChunk.Part] = []
            for (i, item) in pending.enumerated() {
                if i > 0 { text += Chunker.separator }
                let start = text.unicodeScalars.count
                text += item.text
                parts.append(.init(blockIndex: item.block.index, scalarStart: start, scalarEnd: text.unicodeScalars.count, blockScalarStart: item.offset))
            }
            chunks.append(TextChunk(
                id: "\(resourceHref)#chunk-\(chunks.count)", resourceHref: resourceHref, ordinal: chunks.count,
                extractionVersion: extractionVersion, text: text, wordCount: pendingWords, parts: parts, splitsBlock: splits
            ))
            pending = []
            pendingWords = 0
        }

        for block in blocks where !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let words = Chunker.wordCount(block.text)
            if words > maxWords {
                flush()
                for piece in splitAtSentences(block.text, maxWords: maxWords) {
                    pending = [(block, piece.text, piece.scalarOffset)]
                    pendingWords = Chunker.wordCount(piece.text)
                    flush(splits: true)
                }
                continue
            }
            if pendingWords + words > maxWords, pendingWords > 0 {
                flush()
            }
            pending.append((block, block.text, 0))
            pendingWords += words
            if pendingWords >= minWords { flush() }
        }
        flush()
        return chunks
    }

    private func splitAtSentences(_ text: String, maxWords: Int) -> [(text: String, scalarOffset: Int)] {
        var pieces: [(String, Int)] = []
        var sentences: [Range<String.Index>] = []
        text.enumerateSubstrings(in: text.startIndex ..< text.endIndex, options: .bySentences) { _, range, _, _ in
            sentences.append(range)
        }
        if sentences.isEmpty { sentences = [text.startIndex ..< text.endIndex] }
        // A single sentence longer than maxWords falls back to word boundaries.
        sentences = sentences.flatMap { r -> [Range<String.Index>] in
            guard Chunker.wordCount(String(text[r])) > maxWords else { return [r] }
            var out: [Range<String.Index>] = []
            var lower = r.lowerBound
            var count = 0
            var i = r.lowerBound
            var inWord = false
            while i < r.upperBound {
                let isSpace = text[i].isWhitespace
                if !isSpace, !inWord {
                    if count == maxWords { out.append(lower ..< i); lower = i; count = 0 }
                    count += 1
                }
                inWord = !isSpace
                i = text.index(after: i)
            }
            out.append(lower ..< r.upperBound)
            return out
        }
        var start = sentences[0].lowerBound
        var end = start
        var words = 0
        for r in sentences {
            let w = Chunker.wordCount(String(text[r]))
            if words + w > maxWords, words > 0 {
                pieces.append((String(text[start ..< end]), text.unicodeScalars.distance(from: text.unicodeScalars.startIndex, to: start)))
                start = r.lowerBound
                words = 0
            }
            end = r.upperBound
            words += w
        }
        pieces.append((String(text[start ..< end]), text.unicodeScalars.distance(from: text.unicodeScalars.startIndex, to: start)))
        return pieces
    }
}

/// Where a lexical hit falls: the chunk, the block, and scalar ranges in both.
public struct ChunkHit: Sendable, Equatable {
    public var chunk: TextChunk
    public var chunkScalarRange: Range<Int>
    public var blockIndex: Int
    public var blockScalarRange: Range<Int>
    public var matchedText: String
}

public extension TextChunk {
    /// Finds the first case- and diacritic-insensitive occurrence of `query` in the chunk and maps it to its block.
    /// Matches that cross a block separator are not mapped (they are not a single passage).
    func locate(_ query: String) -> ChunkHit? {
        guard let r = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        let scalars = TextOffsets.scalarRange(of: r, in: text)
        guard let part = parts.first(where: { $0.scalarStart <= scalars.lowerBound && scalars.upperBound <= $0.scalarEnd }) else {
            return nil
        }
        let inBlock = (scalars.lowerBound - part.scalarStart + part.blockScalarStart) ..< (scalars.upperBound - part.scalarStart + part.blockScalarStart)
        return ChunkHit(chunk: self, chunkScalarRange: scalars, blockIndex: part.blockIndex, blockScalarRange: inBlock, matchedText: String(text[r]))
    }
}
