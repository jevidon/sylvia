import Foundation
import GRDB
import SylviaAI

/// Builds FTS5 MATCH expressions from untrusted user text (plan 11.3: bound parameters, escaped literal input,
/// no arbitrary FTS syntax). Each term is a quoted string token, joined with OR; operators, column filters,
/// prefixes and NEAR groups typed by the user are therefore literal words, never syntax.
public enum FTSQuery {
    static let stopwords: Set<String> = [
        "a", "about", "after", "all", "also", "an", "and", "any", "are", "as", "at", "be", "been", "but", "by", "can", "could",
        "did", "do", "does", "for", "from", "had", "has", "have", "he", "her", "here", "him", "his", "how", "i", "if", "in", "into",
        "is", "it", "its", "me", "mean", "means", "more", "my", "no", "not", "of", "on", "or", "our", "she", "so", "some", "than",
        "that", "the", "their", "them", "then", "there", "these", "they", "this", "those", "to", "up", "us", "was", "we", "were",
        "what", "when", "where", "which", "who", "whom", "why", "will", "with", "would", "you", "your", "book", "author", "passage",
        "chapter", "say", "says", "said", "tell", "explain",
    ]
    public static let maxTerms = 16

    public static func terms(from text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        let lowered = text.lowercased().folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        for token in lowered.components(separatedBy: CharacterSet.alphanumerics.inverted) where token.count >= 2 {
            guard !stopwords.contains(token), seen.insert(token).inserted else { continue }
            out.append(token)
            if out.count == maxTerms { break }
        }
        return out
    }

    public static func matchExpression(_ terms: [String]) -> String? {
        guard !terms.isEmpty else { return nil }
        return terms.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: " OR ")
    }
}

public struct SearchHit: Sendable, Equatable {
    public let chunk: TextChunk
    public let score: Double
    public let rank: Int
}

public struct SearchResult: Sendable, Equatable {
    public let terms: [String]
    public let hits: [SearchHit]
    /// Chunks that matched but lie beyond the spoiler boundary; filtered in SQL before ranking.
    public let excludedByBoundary: Int
    public let candidatesConsidered: Int
}

/// Lexical retrieval over one or more works' extracted text with SQLite FTS5 through GRDB (plan 11.3, 13.2).
public final class PassageIndex: Sendable {
    let dbQueue: DatabaseQueue

    public init(path: String? = nil) throws {
        dbQueue = try path.map { try DatabaseQueue(path: $0) } ?? DatabaseQueue()
        try dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS resource (
                    work_id TEXT NOT NULL, position INTEGER NOT NULL, href TEXT NOT NULL, label TEXT NOT NULL,
                    PRIMARY KEY (work_id, position));
                CREATE TABLE IF NOT EXISTS paragraph (
                    work_id TEXT NOT NULL, ordinal INTEGER NOT NULL, resource_href TEXT NOT NULL, index_in_resource INTEGER NOT NULL,
                    location_label TEXT NOT NULL, text TEXT NOT NULL, PRIMARY KEY (work_id, ordinal));
                CREATE TABLE IF NOT EXISTS chunk (
                    id INTEGER PRIMARY KEY, work_id TEXT NOT NULL, chunk_index INTEGER NOT NULL, resource_href TEXT NOT NULL,
                    location_label TEXT NOT NULL, first_ordinal INTEGER NOT NULL, last_ordinal INTEGER NOT NULL, piece_index INTEGER,
                    word_count INTEGER NOT NULL, text TEXT NOT NULL, UNIQUE (work_id, chunk_index));
                CREATE VIRTUAL TABLE IF NOT EXISTS chunk_fts USING fts5(
                    text, content='chunk', content_rowid='id', tokenize='unicode61 remove_diacritics 2');
                """)
        }
    }

    /// Indexes a work. Re-indexing the same work replaces its rows (rebuildable, plan 11.3).
    public func index(work: ExtractedWork, workID: UUID, chunks: [TextChunk]) throws {
        let id = workID.uuidString
        try dbQueue.write { db in
            try db.execute(sql: "INSERT INTO chunk_fts(chunk_fts, rowid, text) SELECT 'delete', id, text FROM chunk WHERE work_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM chunk WHERE work_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM paragraph WHERE work_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM resource WHERE work_id = ?", arguments: [id])
            var labels: [String: String] = [:]
            for paragraph in work.paragraphs {
                labels[paragraph.resourceHref] = paragraph.locationLabel
                try db.execute(sql: "INSERT INTO paragraph VALUES (?, ?, ?, ?, ?, ?)",
                               arguments: [id, paragraph.ordinal, paragraph.resourceHref, paragraph.indexInResource, paragraph.locationLabel, paragraph.text])
            }
            for (position, href) in work.resourceHrefs.enumerated() {
                try db.execute(sql: "INSERT INTO resource VALUES (?, ?, ?, ?)", arguments: [id, position, href, labels[href] ?? href])
            }
            for chunk in chunks {
                try db.execute(sql: """
                    INSERT INTO chunk (work_id, chunk_index, resource_href, location_label, first_ordinal, last_ordinal, piece_index, word_count, text)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [id, chunk.chunkIndex, chunk.resourceHref, chunk.locationLabel, chunk.firstOrdinal, chunk.lastOrdinal,
                                     chunk.pieceIndex, chunk.wordCount, chunk.text])
                try db.execute(sql: "INSERT INTO chunk_fts(rowid, text) VALUES (?, ?)", arguments: [db.lastInsertedRowID, chunk.text])
            }
        }
    }

    static func chunk(from row: Row) -> TextChunk {
        TextChunk(chunkIndex: row["chunk_index"], resourceHref: row["resource_href"], locationLabel: row["location_label"],
                  firstOrdinal: row["first_ordinal"], lastOrdinal: row["last_ordinal"], pieceIndex: row["piece_index"],
                  text: row["text"], wordCount: row["word_count"])
    }

    /// Ranked lexical search within one work. `maxOrdinal` filters in SQL, before ranking and before anything
    /// can reach a ContextPack (plan 13.3).
    public func search(workID: UUID, question: String, maxOrdinal: Int?, limit: Int) throws -> SearchResult {
        let terms = FTSQuery.terms(from: question)
        guard let match = FTSQuery.matchExpression(terms) else {
            return SearchResult(terms: [], hits: [], excludedByBoundary: 0, candidatesConsidered: 0)
        }
        let id = workID.uuidString
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT chunk.*, bm25(chunk_fts) AS score
                FROM chunk_fts JOIN chunk ON chunk.id = chunk_fts.rowid
                WHERE chunk_fts MATCH ? AND chunk.work_id = ? AND (? IS NULL OR chunk.last_ordinal <= ?)
                ORDER BY score, chunk.chunk_index
                LIMIT ?
                """, arguments: [match, id, maxOrdinal, maxOrdinal, limit])
            let considered = try Int.fetchOne(db, sql: """
                SELECT count(*) FROM chunk_fts JOIN chunk ON chunk.id = chunk_fts.rowid
                WHERE chunk_fts MATCH ? AND chunk.work_id = ? AND (? IS NULL OR chunk.last_ordinal <= ?)
                """, arguments: [match, id, maxOrdinal, maxOrdinal]) ?? 0
            let excluded = maxOrdinal == nil ? 0 : try Int.fetchOne(db, sql: """
                SELECT count(*) FROM chunk_fts JOIN chunk ON chunk.id = chunk_fts.rowid
                WHERE chunk_fts MATCH ? AND chunk.work_id = ? AND chunk.last_ordinal > ?
                """, arguments: [match, id, maxOrdinal]) ?? 0
            let hits = rows.enumerated().map { index, row in
                SearchHit(chunk: Self.chunk(from: row), score: row["score"], rank: index + 1)
            }
            return SearchResult(terms: terms, hits: hits, excludedByBoundary: excluded, candidatesConsidered: considered)
        }
    }

    public func chunk(workID: UUID, index: Int) throws -> TextChunk? {
        try dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM chunk WHERE work_id = ? AND chunk_index = ?", arguments: [workID.uuidString, index]).map(Self.chunk)
        }
    }

    public func allChunks(workID: UUID, maxOrdinal: Int?) throws -> [TextChunk] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM chunk WHERE work_id = ? AND (? IS NULL OR last_ordinal <= ?) ORDER BY chunk_index",
                             arguments: [workID.uuidString, maxOrdinal, maxOrdinal]).map(Self.chunk)
        }
    }

    public func paragraph(workID: UUID, ordinal: Int) throws -> ExtractedParagraph? {
        try dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM paragraph WHERE work_id = ? AND ordinal = ?", arguments: [workID.uuidString, ordinal]).map {
                ExtractedParagraph(ordinal: $0["ordinal"], spineIndex: 0, resourceHref: $0["resource_href"], indexInResource: $0["index_in_resource"],
                                   locationLabel: $0["location_label"], text: $0["text"])
            }
        }
    }

    public func resourceCount(workID: UUID) throws -> Int {
        try dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM resource WHERE work_id = ?", arguments: [workID.uuidString]) ?? 0 }
    }

    /// Row counts, for integrity checks in tests.
    public func counts(workID: UUID) throws -> (paragraphs: Int, chunks: Int, ftsRows: Int) {
        try dbQueue.read { db in
            let id = workID.uuidString
            return (try Int.fetchOne(db, sql: "SELECT count(*) FROM paragraph WHERE work_id = ?", arguments: [id]) ?? 0,
                    try Int.fetchOne(db, sql: "SELECT count(*) FROM chunk WHERE work_id = ?", arguments: [id]) ?? 0,
                    try Int.fetchOne(db, sql: "SELECT count(*) FROM chunk_fts") ?? 0)
        }
    }
}
