import Foundation
import SQLite3

/// Creates a real SQLite database in WAL mode so the layout audit sees the database, -wal and -shm files where
/// the product's GRDB store will put them. Stage 0 evidence helper; the product uses GRDB (ADR-0002).
public enum SQLiteFixture {
    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    /// Opens (creating) the database, switches to WAL and writes one row. The connection stays open so the
    /// -wal and -shm files exist; close it with `sqlite3_close`.
    public static func makeWALDatabase(at url: URL) throws -> OpaquePointer {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK, let db else {
            throw Failure(description: "sqlite3_open_v2 failed")
        }
        for sql in ["PRAGMA journal_mode=WAL", "CREATE TABLE IF NOT EXISTS layout_probe(x)", "INSERT INTO layout_probe VALUES (1)"] {
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                let message = String(cString: sqlite3_errmsg(db))
                sqlite3_close(db)
                throw Failure(description: "sqlite3_exec failed: \(message)")
            }
        }
        return db
    }
}
