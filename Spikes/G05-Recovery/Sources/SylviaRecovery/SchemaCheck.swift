import Foundation
import GRDB
import SylviaSQLiteShim

/// Schema verification for database files Sylvia did not create itself (a backup snapshot), and
/// the defensive way to open them (plan 17.4 "validate ... schema", plan 18.1 "archives are
/// untrusted").
///
/// A backup's database is attacker-controlled bytes with matching digests. Its migration list
/// says which schema it claims to have; its `sqlite_schema` says what SQLite will actually run:
/// tables with or without `STRICT` and `CHECK`, foreign-key actions, indexes, and any trigger or
/// view. Restore therefore rebuilds the schema this build's migrations produce for the claimed
/// migration list and requires the snapshot's schema to be identical, entry for entry, before it
/// reads counts, runs migrations or writes anything.
public enum SchemaCheck {
    /// One row of `sqlite_schema`.
    public struct Entry: Hashable, Sendable, CustomStringConvertible {
        public var type: String
        public var name: String
        public var tableName: String
        /// The `CREATE` statement exactly as SQLite stores it; nil for automatic indexes.
        public var sql: String?

        public var description: String { "\(type) \(name)" }
    }

    public static func entries(_ db: Database) throws -> [Entry] {
        try Row.fetchAll(db, sql: "SELECT type, name, tbl_name, sql FROM sqlite_schema ORDER BY type, name").map {
            Entry(type: $0["type"], name: $0["name"], tableName: $0["tbl_name"], sql: $0["sql"])
        }
    }

    /// The schema this build's own migrator produces after applying `applied`, built in memory.
    /// `applied` must be a prefix of the registered migrations (GRDB applies them in order); any
    /// other list is not a schema this build can produce.
    public static func reference(applied: [String]) throws -> [Entry]? {
        let registered = LibrarySchema.migrations.map(\.identifier)
        guard let last = applied.last, applied == Array(registered.prefix(applied.count)) else { return nil }
        let queue = try DatabaseQueue()
        try LibrarySchema.migrator().migrate(queue, upTo: last)
        return try queue.read { try entries($0) }
    }

    /// Differences between `actual` and `expected`, one line each; empty when identical. SQL text
    /// is compared exactly: the reference is built by the same SQLite library that will use the
    /// restored file, from the same migration code.
    public static func differences(actual: [Entry], expected: [Entry]) -> [String] {
        let expectedByKey = Dictionary(uniqueKeysWithValues: expected.map { ("\($0.type) \($0.name)", $0) })
        let actualByKey = Dictionary(uniqueKeysWithValues: actual.map { ("\($0.type) \($0.name)", $0) })
        var out: [String] = []
        for key in actualByKey.keys.sorted() where expectedByKey[key] == nil {
            out.append("unexpected \(key)")
        }
        for key in expectedByKey.keys.sorted() {
            guard let found = actualByKey[key] else { out.append("missing \(key)"); continue }
            let wanted = expectedByKey[key]!
            if found.tableName != wanted.tableName || found.sql != wanted.sql { out.append("altered \(key)") }
        }
        return out
    }

    /// Checks `db` against the reference for its applied migrations. Throws `schemaMismatch`.
    public static func requireReference(_ db: Database, applied: [String]) throws {
        guard let expected = try reference(applied: applied) else {
            throw BackupError.schemaMismatch("migrations \(applied) are not an ordered prefix of this build's migrations")
        }
        let problems = differences(actual: try entries(db), expected: expected)
        guard problems.isEmpty else {
            throw BackupError.schemaMismatch(problems.prefix(5).joined(separator: "; ") + (problems.count > 5 ? "; …" : ""))
        }
    }

    /// Configuration for opening a database file that came from outside the library: SQLite's
    /// defensive mode (no `writable_schema`, no shadow-table or `sqlite_dbpage` writes, no
    /// `journal_mode=OFF`) and `trusted_schema=OFF` (functions with side effects and virtual tables
    /// cannot be used from the schema). Both are read back; a connection without them fails to open.
    public static func untrustedConfiguration() -> Configuration {
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            guard sylvia_sqlite_set_defensive(db.sqliteConnection, 1) == 1 else {
                throw BackupError.corruptDatabase("SQLite defensive mode could not be enabled")
            }
            try db.execute(sql: "PRAGMA trusted_schema = OFF")
            guard try Int.fetchOne(db, sql: "PRAGMA trusted_schema") == 0 else {
                throw BackupError.corruptDatabase("trusted_schema could not be turned off")
            }
        }
        return config
    }
}

/// Row values in a database Sylvia did not create that its schema does not constrain but the app
/// relies on (plan 17.4 "fail safely on ... malicious archives"): effective dates against their
/// precision, each note's revisions against its `current_revision`, every INTEGER within
/// ±(2^53 - 1), `sqlite_sequence` against the ChangeJournal, and every TEXT value valid UTF-8
/// without a NUL character. Everything else in a row is validated only by the schema's `STRICT`
/// types and `CHECK` constraints, `foreign_key_check` and `integrity_check`; any further invariant
/// the app relies on must be added here.
public enum RowCheck {
    /// Every user-effective date column with its precision column (plan 7.3). The schema checks the
    /// precision value and that both are null together; the date text itself is checked here (and
    /// by `EffectiveDate` in code that builds dates). `SchemaTests.everyEffectiveDateColumnIsChecked`
    /// keeps this list equal to the schema's `*_date` columns.
    public static let effectiveDateColumns: [(table: String, date: String, precision: String)] = [
        ("edition", "published_date", "published_date_precision"),
        ("consumption_run", "started_date", "started_date_precision"),
        ("consumption_run", "finished_date", "finished_date_precision"),
        ("recommendation_event", "event_date", "event_date_precision"),
        ("ledger_event", "effective_date", "effective_date_precision"),
    ]

    /// Problems found, one line each (at most `limit`); empty when every checked value is valid.
    /// Pairs whose precision column does not exist yet (v1 `recommendation_event`, whose free-form
    /// date the v2 migration converts under a `CHECK`) are skipped; restore runs this again after
    /// migrating.
    public static func problems(_ db: Database, limit: Int = 5) throws -> [String] {
        var out: [String] = []
        for (table, date, precision) in effectiveDateColumns {
            let columns = Set(try db.columns(in: table).map(\.name))
            guard columns.contains(date), columns.contains(precision) else { continue }
            let sql = "SELECT rowid, \(date) AS d, \(precision) AS p FROM \(table) WHERE \(date) IS NOT NULL OR \(precision) IS NOT NULL"
            for row in try Row.fetchAll(db, sql: sql) {
                let value: String? = row["d"]
                let rawPrecision: String? = row["p"]
                if let value, let rawPrecision, let kind = EffectiveDate.Precision(rawValue: rawPrecision),
                   EffectiveDate.isValid(value, precision: kind) {
                    continue
                }
                let shown = value.map { "'\($0.prefix(40))'" } ?? "null"
                out.append("\(table).\(date) rowid \(row["rowid"] as Int64): \(shown) is not a date of precision \(rawPrecision ?? "null")")
                if out.count >= limit { return out }
            }
        }
        out += try noteRevisionProblems(db, limit: limit)
        out += try integerRangeProblems(db, limit: limit)
        out += try sequenceProblems(db)
        out += try textProblems(db, limit: limit)
        return Array(out.prefix(limit))
    }

    /// GRDB 7.11.1 binds a Swift `String` as a C string (`sqlite3_bind_text` with length -1, so a
    /// value is cut off at its first NUL) and decodes TEXT with `String(cString:)` (everything after
    /// a NUL is dropped and invalid UTF-8 is replaced). The app therefore never stores text with a
    /// NUL (`LibraryStore.insert` refuses it) or invalid UTF-8 (Swift strings are always valid), and
    /// a stored value holding either would be shown, edited, exported and compared as different
    /// text from what is stored (finding F12; review round 4 found the content digest blind to it).
    /// Every TEXT value of every library table must be valid UTF-8 with no NUL; one problem is
    /// reported per column.
    static func textProblems(_ db: Database, limit: Int) throws -> [String] {
        var out: [String] = []
        let present = try LibraryChecks.existingTables(db)
        for table in LibrarySchema.tables.map(\.name) where present.contains(table) {
            for column in try db.columns(in: table) where column.type.uppercased() == "TEXT" {
                let sql = """
                    SELECT rowid AS r, CAST(\(column.name) AS BLOB) AS b FROM \(table)
                    WHERE typeof(\(column.name)) = 'text' ORDER BY rowid
                    """
                let rows = try Row.fetchCursor(db, sql: sql)
                while let row = try rows.next() {
                    let bytes: Data = row["b"]
                    let problem: String? = bytes.contains(0) ? "contains a NUL character"
                        : String(validating: bytes, as: UTF8.self) == nil ? "is not valid UTF-8" : nil
                    if let problem {
                        out.append("\(table).\(column.name) rowid \(row["r"] as Int64): text \(problem)")
                        break
                    }
                }
                if out.count >= limit { return out }
            }
        }
        return out
    }

    /// Largest magnitude an INTEGER value may have: below 2^53, so the portable JSON export (which
    /// refuses anything larger, because JSON readers lose precision there) can always export the
    /// library, and every counter the app increments (`note.current_revision`, `capture.revision`,
    /// `work.metadata_revision`, `edition_asset.timeline_revision`, the ChangeJournal sequence) stays
    /// far from `Int64.max`, so `current + 1` cannot overflow. Real values are far smaller:
    /// millisecond timestamps reach 2^53 in the year 287,396, and byte counts at 8 PiB.
    public static let integerMagnitudeLimit: Int64 = (1 << 53) - 1

    /// A note's text is its revision `current_revision` (plan 7.3), and `reviseNote` inserts
    /// `current_revision + 1`. Every note must therefore have revisions numbered exactly
    /// 1...current_revision. A stale pointer would make every later edit of the note fail on the
    /// revision key, and a dangling one would leave the note without current text (review round 3).
    static func noteRevisionProblems(_ db: Database, limit: Int) throws -> [String] {
        let sql = """
            SELECT n.rowid AS note_rowid, n.current_revision AS current, count(r.revision) AS revisions,
                   min(r.revision) AS lowest, max(r.revision) AS highest
            FROM note n LEFT JOIN note_revision r ON r.note_id = n.id
            GROUP BY n.id
            HAVING revisions = 0 OR lowest <> 1 OR highest <> n.current_revision OR revisions <> n.current_revision
            ORDER BY n.rowid
            LIMIT \(limit)
            """
        return try Row.fetchAll(db, sql: sql).map { row in
            let revisions: Int64 = row["revisions"]
            let shown = revisions == 0 ? "no revisions"
                : "\(revisions) revisions numbered \(row["lowest"] as Int64)...\(row["highest"] as Int64)"
            return "note rowid \(row["note_rowid"] as Int64): current_revision \(row["current"] as Int64) but \(shown); revisions must be exactly 1...current_revision"
        }
    }

    /// Every INTEGER column of every library table holds values within `integerMagnitudeLimit`.
    static func integerRangeProblems(_ db: Database, limit: Int) throws -> [String] {
        var out: [String] = []
        let present = try LibraryChecks.existingTables(db)
        for table in LibrarySchema.tables.map(\.name) where present.contains(table) {
            for column in try db.columns(in: table) where column.type.uppercased() == "INTEGER" {
                let sql = """
                    SELECT rowid AS r, \(column.name) AS v FROM \(table)
                    WHERE \(column.name) > \(integerMagnitudeLimit) OR \(column.name) < -\(integerMagnitudeLimit)
                    ORDER BY rowid LIMIT 1
                    """
                if let row = try Row.fetchOne(db, sql: sql) {
                    out.append("\(table).\(column.name) rowid \(row["r"] as Int64): \(row["v"] as Int64) is outside ±(2^53 - 1)")
                    if out.count >= limit { return out }
                }
            }
        }
        return out
    }

    /// `sqlite_sequence` may hold only the ChangeJournal's entry: an integer equal to its highest
    /// sequence, or no entry while the journal is empty. Nothing deletes journal rows, so a real
    /// library always satisfies this. A crafted value near 2^63 would make every later save fail with
    /// `SQLITE_FULL`, which looks like a full disk. A product that prunes the journal must relax this
    /// to "at least the highest sequence, within a bound".
    static func sequenceProblems(_ db: Database) throws -> [String] {
        var out: [String] = []
        let rows = try Row.fetchAll(db, sql: "SELECT name, seq FROM sqlite_sequence")
        let highest = try Int64.fetchOne(db, sql: "SELECT max(seq) FROM change_journal")
        var journal: [DatabaseValue] = []
        for row in rows {
            let name: String? = row["name"]
            if name == "change_journal" {
                journal.append(row["seq"])
            } else {
                out.append("sqlite_sequence has an entry for \(name.map { "'\($0.prefix(40))'" } ?? "null")")
            }
        }
        switch (journal.count, highest) {
        case (0, nil):
            break
        case (1, let highest?):
            if case .int64(let seq) = journal[0].storage, seq == highest { break }
            out.append("sqlite_sequence for change_journal is \(journal[0]), the highest journal entry is \(highest)")
        default:
            out.append("sqlite_sequence has \(journal.count) change_journal entries; the highest journal entry is \(highest.map(String.init) ?? "none")")
        }
        return out
    }

    /// Throws `BackupError.invalidRows` when `problems` finds anything.
    public static func require(_ db: Database) throws {
        let found = try problems(db)
        guard found.isEmpty else { throw BackupError.invalidRows(found.joined(separator: "; ")) }
    }
}
