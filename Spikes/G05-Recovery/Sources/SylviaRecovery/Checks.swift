import CryptoKit
import Foundation
import GRDB

/// Integrity, foreign-key and content checks shared by migrations, export, restore and the drills.
public enum LibraryChecks {
    /// `PRAGMA integrity_check` messages; `["ok"]` means healthy.
    public static func integrity(_ db: Database) throws -> [String] {
        try String.fetchAll(db, sql: "PRAGMA integrity_check")
    }

    public static func isIntact(_ db: Database) throws -> Bool {
        try integrity(db) == ["ok"]
    }

    /// Rows reported by `PRAGMA foreign_key_check`, rendered as "table rowid -> parent".
    public static func foreignKeyViolations(_ db: Database) throws -> [String] {
        try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").map { row in
            "\(row[0] as String? ?? "?") rowid \(row[1] as Int64? ?? -1) -> \(row[2] as String? ?? "?")"
        }
    }

    public static func existingTables(_ db: Database) throws -> Set<String> {
        Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'"))
    }

    /// Row counts for every library table present in the database.
    public static func counts(_ db: Database) throws -> [String: Int64] {
        let present = try existingTables(db)
        var result: [String: Int64] = [:]
        for table in LibrarySchema.tables.map(\.name) where present.contains(table) {
            result[table] = try Int64.fetchOne(db, sql: "SELECT count(*) FROM \(table)") ?? 0
        }
        return result
    }

    /// A canonical, typed text rendering of every row of `tables` (columns in name order, rows in
    /// primary-key order). Two libraries with equal dumps hold the same values, byte for byte,
    /// including types (an integer never compares equal to the same digits stored as text): values
    /// are read with `ExactRows`, so TEXT is rendered from its stored bytes, not from GRDB's
    /// decoding (review round 4).
    public static func canonicalDump(_ db: Database, tables: [String]) throws -> String {
        let orderBy = Dictionary(uniqueKeysWithValues: LibrarySchema.tables.map { ($0.name, $0.orderBy) })
        var out = ""
        for table in tables {
            guard let order = orderBy[table] else { throw StoreError.unknownTable(table) }
            let columns = try db.columns(in: table).map(\.name).sorted()
            let rows = try Row.fetchAll(db, sql: ExactRows.select(columns, from: ExactRows.quoted(table), orderBy: order))
            out += "## \(table) (\(rows.count))\n"
            for row in rows {
                out += zip(columns, ExactRows.render(row, columnCount: columns.count)).map { "\($0)=\($1)" }
                    .joined(separator: "|") + "\n"
            }
        }
        return out
    }

    public static func knowledgeDump(_ db: Database) throws -> String {
        try canonicalDump(db, tables: LibrarySchema.knowledgeTables)
    }

    /// SHA-256 over the whole logical content of a database: every `sqlite_schema` entry with its
    /// SQL, `user_version` and `application_id`, and every row of every table (including
    /// `grdb_migrations` and `sqlite_sequence`), typed, in a total order. Values are read with
    /// `ExactRows`: TEXT as its stored bytes, INTEGER and BLOB exactly, REAL in Swift's shortest
    /// round-trip form, each with its type. The rendering is injective, so two databases with
    /// equal digests hold the same schema and the same values byte for byte (barring a SHA-256
    /// collision) whatever their journal mode or page layout, and a pre-migration snapshot can be
    /// recognised as a copy of the live library (review round 3). Review round 4 found the first
    /// version, which rendered GRDB's decoded strings, blind to TEXT after an embedded NUL.
    public static func contentDigest(_ db: Database) throws -> String {
        var hasher = SHA256()
        func add(_ line: String) { hasher.update(data: Data((line + "\n").utf8)) }
        add("user_version=\(try Int64.fetchOne(db, sql: "PRAGMA user_version") ?? 0)")
        add("application_id=\(try Int64.fetchOne(db, sql: "PRAGMA application_id") ?? 0)")
        let schemaColumns = ["type", "name", "tbl_name", "sql"]
        for row in try Row.fetchAll(db, sql: ExactRows.select(schemaColumns, from: "sqlite_schema", orderBy: "type, name")) {
            add("S|" + ExactRows.render(row, columnCount: schemaColumns.count).joined(separator: "|"))
        }
        for table in try String.fetchAll(db, sql: "SELECT name FROM sqlite_schema WHERE type = 'table' ORDER BY name") {
            let columns = try db.columns(in: table).map(\.name)
            add("T|" + CanonicalValue.render(table.databaseValue))
            guard !columns.isEmpty else { continue }
            // Every column in declared order, with its own collation: the same total order as before.
            let order = columns.map(ExactRows.quoted).joined(separator: ", ")
            let rows = try Row.fetchCursor(db, sql: ExactRows.select(columns, from: ExactRows.quoted(table), orderBy: order))
            while let row = try rows.next() {
                add("R|" + ExactRows.render(row, columnCount: columns.count).joined(separator: "|"))
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Reads rows with every value as stored, for comparisons that must not depend on how GRDB decodes
/// text (`LibraryChecks.canonicalDump`, `LibraryChecks.contentDigest`).
///
/// GRDB 7.11.1 decodes a TEXT value with `String(cString:)`, which drops everything after an
/// embedded NUL and replaces invalid UTF-8, so different stored texts can decode to the same
/// `String`: review round 4 showed two databases holding `CAST(X'61006D696E65' AS TEXT)` and
/// `CAST(X'61007468656972' AS TEXT)` with equal content digests. Here every column is selected
/// twice, as `typeof(c)` and as its value with TEXT cast to BLOB, which SQLite returns as the stored
/// bytes at their full length; GRDB reads blobs exactly.
enum ExactRows {
    /// A double-quoted SQL identifier.
    static func quoted(_ identifier: String) -> String {
        "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// `SELECT typeof(c1), <c1 as stored>, typeof(c2), ... FROM <from> ORDER BY <orderBy>`.
    /// `from` is used as given (quote a table name with `quoted`).
    static func select(_ columns: [String], from: String, orderBy: String) -> String {
        let list = columns.map { column -> String in
            let c = quoted(column)
            return "typeof(\(c)), CASE typeof(\(c)) WHEN 'text' THEN CAST(\(c) AS BLOB) ELSE \(c) END"
        }.joined(separator: ", ")
        return "SELECT \(list) FROM \(from) ORDER BY \(orderBy)"
    }

    /// One rendering per column of a row fetched with `select`.
    static func render(_ row: Row, columnCount: Int) -> [String] {
        (0..<columnCount).map { index in
            CanonicalValue.renderExact(type: row[2 * index], value: row[2 * index + 1] as DatabaseValue)
        }
    }
}

/// Typed rendering used by canonical dumps and by the portable-JSON round-trip check.
public enum CanonicalValue {
    public static func render(_ value: DatabaseValue) -> String {
        switch value.storage {
        case .null: return "n"
        case .int64(let v): return "i:\(v)"
        case .double(let v): return "r:\(v)"
        case .string(let s): return "t:" + escape(s)
        case .blob(let d): return "b:" + d.map { String(format: "%02x", $0) }.joined()
        }
    }

    /// Renders a value read by `ExactRows`: `type` is SQLite's `typeof`, and a TEXT value arrives
    /// as its stored bytes. Valid UTF-8 renders exactly as `render` renders the decoded string, so
    /// dumps of ordinary text compare equal to the portable JSON's rendering; an embedded NUL is
    /// kept (escaped as `\u{0}`), and bytes that are not valid UTF-8 render as `x:` and their hex,
    /// which no other value can render as.
    public static func renderExact(type: String, value: DatabaseValue) -> String {
        guard type == "text" else { return render(value) }
        guard case .blob(let bytes) = value.storage else { return "?:" + render(value) }
        if let text = String(validating: bytes, as: UTF8.self) { return "t:" + escape(text) }
        return "x:" + bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Renders a value decoded from the portable JSON export the same way.
    public static func render(json value: Any) -> String {
        if value is NSNull { return "n" }
        if let s = value as? String { return "t:" + escape(s) }
        if let n = value as? NSNumber {
            if CFNumberIsFloatType(n) { return "r:\(n.doubleValue)" }
            return "i:\(n.int64Value)"
        }
        if let dict = value as? [String: Any], let b64 = dict["base64"] as? String,
           let data = Data(base64Encoded: b64) {
            return "b:" + data.map { String(format: "%02x", $0) }.joined()
        }
        return "?:\(value)"
    }

    static func escape(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "|": out += "\\u{7c}"
            default:
                if scalar.value < 0x20 { out += "\\u{\(String(scalar.value, radix: 16))}" } else { out.unicodeScalars.append(scalar) }
            }
        }
        return out + "\""
    }
}
