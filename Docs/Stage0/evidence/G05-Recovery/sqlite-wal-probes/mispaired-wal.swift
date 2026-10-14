// Host probe: is a -wal written for database A applied when it is placed beside database B?
// A and B start as identical files (as a pre-migration snapshot and its live library do). A then
// commits a change that stays in its -wal; that -wal is copied beside B.
import Foundation
import SQLite3

let dir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.removeItem(at: dir)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let fm = FileManager.default
func p(_ name: String) -> String { dir.appendingPathComponent(name).path }

func exec(_ db: OpaquePointer?, _ sql: String) {
    var error: UnsafeMutablePointer<CChar>?
    if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK { print("error: \(String(cString: error!))") }
}

/// Opens `path`, runs `sql`, closes, and returns the rows joined by commas.
func query(_ path: String, _ sql: String) -> String {
    var db: OpaquePointer?
    guard sqlite3_open(path, &db) == SQLITE_OK else { return "open failed" }
    defer { sqlite3_close(db) }
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return "prepare failed: \(String(cString: sqlite3_errmsg(db)))" }
    defer { sqlite3_finalize(stmt) }
    var rows: [String] = []
    while sqlite3_step(stmt) == SQLITE_ROW { rows.append(String(cString: sqlite3_column_text(stmt, 0))) }
    return rows.joined(separator: ",")
}

func removeSidecars(_ name: String) {
    for suffix in ["-wal", "-shm"] { try? fm.removeItem(atPath: p(name + suffix)) }
}

var a: OpaquePointer?
sqlite3_open(p("a.sqlite"), &a)
exec(a, "PRAGMA journal_mode=WAL; CREATE TABLE t(x TEXT); INSERT INTO t VALUES ('original');")
sqlite3_close(a)
try fm.copyItem(atPath: p("a.sqlite"), toPath: p("b.sqlite"))
print("b.sqlite read alone: \(query(p("b.sqlite"), "SELECT x FROM t"))")
removeSidecars("b.sqlite")

// A commits a change that stays in its -wal (copied while A is open, before the checkpoint on close).
sqlite3_open(p("a.sqlite"), &a)
exec(a, "PRAGMA wal_autocheckpoint=0; UPDATE t SET x = 'only in a.sqlite-wal';")
try fm.copyItem(atPath: p("a.sqlite-wal"), toPath: p("b.sqlite-wal"))
sqlite3_close(a)
print("b.sqlite read with a.sqlite's -wal beside it: \(query(p("b.sqlite"), "SELECT x FROM t"))")
