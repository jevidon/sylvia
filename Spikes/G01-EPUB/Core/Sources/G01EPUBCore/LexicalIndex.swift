import Foundation
import SQLite3

/// Minimal FTS5 index over chunks (plan 11.3 baseline: FTS5 lexical ranking, bound parameters, user input escaped
/// as a phrase so no FTS syntax reaches the engine). In-memory; the spike only needs the mapping, not durability.
public final class LexicalIndex {
    public enum IndexError: Error, Equatable { case sqlite(String) }

    private var db: OpaquePointer?
    private var chunks: [String: TextChunk] = [:]
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init() throws {
        guard sqlite3_open_v2(":memory:", &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            throw IndexError.sqlite("open")
        }
        // unicode61 with diacritics removed so "Amelie" finds "Amélie"; the stored quote is never normalized.
        try exec("CREATE VIRTUAL TABLE chunk_fts USING fts5(chunk_id UNINDEXED, body, tokenize = 'unicode61 remove_diacritics 2')")
    }

    deinit { sqlite3_close(db) }

    public var sqliteVersion: String { String(cString: sqlite3_libversion()) }

    public func add(_ chunk: TextChunk) throws {
        chunks[chunk.id] = chunk
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO chunk_fts (chunk_id, body) VALUES (?1, ?2)", -1, &stmt, nil) == SQLITE_OK else {
            throw IndexError.sqlite(lastError)
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, chunk.id, -1, Self.transient)
        sqlite3_bind_text(stmt, 2, chunk.text, -1, Self.transient)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw IndexError.sqlite(lastError) }
    }

    /// Escapes arbitrary user text as a single FTS5 phrase.
    public static func phrase(_ userText: String) -> String {
        "\"" + userText.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Returns chunks ranked by bm25, each with the located hit (nil when the phrase spans a block separator).
    public func search(_ userText: String, limit: Int = 20) throws -> [(chunk: TextChunk, hit: ChunkHit?)] {
        var stmt: OpaquePointer?
        let sql = "SELECT chunk_id FROM chunk_fts WHERE chunk_fts MATCH ?1 ORDER BY bm25(chunk_fts) LIMIT ?2"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw IndexError.sqlite(lastError) }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, Self.phrase(userText), -1, Self.transient)
        sqlite3_bind_int(stmt, 2, Int32(limit))
        var results: [(TextChunk, ChunkHit?)] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) else { throw IndexError.sqlite(lastError) }
            if let chunk = chunks[String(cString: c)] {
                results.append((chunk, chunk.locate(userText)))
            }
        }
        return results
    }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw IndexError.sqlite(lastError) }
    }

    private var lastError: String { db.map { String(cString: sqlite3_errmsg($0)) } ?? "no database" }
}
