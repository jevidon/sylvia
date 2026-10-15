import CryptoKit
import Foundation
import NaturalLanguage

/// A retrieval chunk: whole paragraphs from one resource, 300-600 words (plan 13.2).
public struct TextChunk: Codable, Sendable, Equatable {
    public let chunkIndex: Int
    public let resourceHref: String
    public let locationLabel: String
    /// Ordinals of the first and last paragraph in the chunk. A paragraph longer than the maximum is split at
    /// sentence boundaries; its pieces share one ordinal and record `pieceIndex`.
    public let firstOrdinal: Int
    public let lastOrdinal: Int
    public let pieceIndex: Int?
    public let text: String
    public let wordCount: Int

    public var sha256: String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
}

public struct ChunkingPolicy: Sendable, Equatable {
    public var minWords: Int
    public var maxWords: Int

    public init(minWords: Int = 300, maxWords: Int = 600) {
        self.minWords = minWords
        self.maxWords = maxWords
    }
}

/// Builds chunks on paragraph boundaries without crossing resources (chapters).
///
/// Rules, checked by tests:
/// 1. A chunk never exceeds `maxWords`.
/// 2. A chunk never spans two resources.
/// 3. Paragraphs are never split unless a single paragraph exceeds `maxWords`; such a paragraph is split at
///    sentence boundaries into pieces of at most `maxWords` and those pieces are chunks of their own.
/// 4. A chunk has fewer than `minWords` only when it ends a resource, precedes an oversized paragraph, or would
///    otherwise exceed `maxWords` by taking the next paragraph.
/// 5. Concatenating chunk texts in order reproduces every paragraph exactly once and in order.
public enum Chunker {
    public static func chunk(_ paragraphs: [ExtractedParagraph], policy: ChunkingPolicy = ChunkingPolicy()) -> [TextChunk] {
        var chunks: [TextChunk] = []
        var current: [ExtractedParagraph] = []
        var currentWords = 0

        func close() {
            guard let first = current.first, let last = current.last else { return }
            chunks.append(TextChunk(chunkIndex: chunks.count, resourceHref: first.resourceHref, locationLabel: first.locationLabel,
                                    firstOrdinal: first.ordinal, lastOrdinal: last.ordinal, pieceIndex: nil,
                                    text: current.map(\.text).joined(separator: "\n\n"), wordCount: currentWords))
            current.removeAll()
            currentWords = 0
        }

        for paragraph in paragraphs {
            if let first = current.first, first.resourceHref != paragraph.resourceHref { close() }
            let words = paragraph.wordCount
            if words > policy.maxWords {
                close()
                for (pieceIndex, piece) in splitLongParagraph(paragraph.text, maxWords: policy.maxWords).enumerated() {
                    chunks.append(TextChunk(chunkIndex: chunks.count, resourceHref: paragraph.resourceHref,
                                            locationLabel: paragraph.locationLabel, firstOrdinal: paragraph.ordinal,
                                            lastOrdinal: paragraph.ordinal, pieceIndex: pieceIndex, text: piece,
                                            wordCount: piece.split(whereSeparator: \.isWhitespace).count))
                }
                continue
            }
            if currentWords + words > policy.maxWords { close() }
            current.append(paragraph)
            currentWords += words
            if currentWords >= policy.minWords { close() }
        }
        close()
        return chunks
    }

    /// Splits text into pieces of at most `maxWords`, at sentence boundaries where possible; a single sentence
    /// longer than the limit is split at word boundaries. Each piece is an exact substring of `text` with
    /// surrounding whitespace removed, so the pieces plus the whitespace between them reproduce `text`.
    static func splitLongParagraph(_ text: String, maxWords: Int) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            sentences.append(range)
            return true
        }
        if sentences.isEmpty { sentences = [text.startIndex..<text.endIndex] }
        // Word ranges of the whole text, so cuts always fall on whitespace.
        var cutPoints: [String.Index] = []  // indices where a piece starts
        var pieceWords = 0
        for sentence in sentences {
            let words = wordStarts(in: text, range: sentence)
            if pieceWords + words.count > maxWords && pieceWords > 0 {
                cutPoints.append(sentence.lowerBound)
                pieceWords = 0
            }
            if words.count > maxWords {
                // Oversized sentence: cut every maxWords words.
                var index = 0
                while index < words.count {
                    if pieceWords == maxWords {
                        cutPoints.append(words[index])
                        pieceWords = 0
                    }
                    pieceWords += 1
                    index += 1
                }
            } else {
                pieceWords += words.count
            }
        }
        var pieces: [String] = []
        var lower = text.startIndex
        for cut in cutPoints + [text.endIndex] where cut > lower {
            let piece = text[lower..<cut].trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { pieces.append(piece) }
            lower = cut
        }
        return pieces
    }

    /// Start indices of whitespace-separated words inside `range`.
    static func wordStarts(in text: String, range: Range<String.Index>) -> [String.Index] {
        var starts: [String.Index] = []
        var previousWasSpace = true
        var index = range.lowerBound
        while index < range.upperBound {
            let isSpace = text[index].isWhitespace
            if !isSpace && previousWasSpace { starts.append(index) }
            previousWasSpace = isSpace
            index = text.index(after: index)
        }
        return starts
    }
}
