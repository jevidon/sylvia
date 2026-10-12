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
    /// including types (an integer never compares equal to the same digits stored as text).
    public static func canonicalDump(_ db: Database, tables: [String]) throws -> String {
        let orderBy = Dictionary(uniqueKeysWithValues: LibrarySchema.tables.map { ($0.name, $0.orderBy) })
        var out = ""
        for table in tables {
            guard let order = orderBy[table] else { throw StoreError.unknownTable(table) }
            let columns = try db.columns(in: table).map(\.name).sorted()
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM \(table) ORDER BY \(order)")
            out += "## \(table) (\(rows.count))\n"
            for row in rows {
                out += columns.map { "\($0)=\(CanonicalValue.render(row[$0] as DatabaseValue))" }
                    .joined(separator: "|") + "\n"
            }
        }
        return out
    }

    public static func knowledgeDump(_ db: Database) throws -> String {
        try canonicalDump(db, tables: LibrarySchema.knowledgeTables)
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
