// Does the system libsqlite3 delete -wal and -shm when the last connection to a WAL database closes?
import Foundation
import SQLite3

let dir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.removeItem(at: dir)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let path = dir.appendingPathComponent("probe.sqlite").path

func exec(_ db: OpaquePointer?, _ sql: String) {
    var error: UnsafeMutablePointer<CChar>?
    if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK { print("error: \(String(cString: error!))") }
}

func files() -> String {
    ["probe.sqlite-wal", "probe.sqlite-shm"].map { "\($0)=\(FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path))" }.joined(separator: " ")
}

var db: OpaquePointer?
sqlite3_open(path, &db)
exec(db, "PRAGMA journal_mode=WAL; CREATE TABLE t(x INTEGER); INSERT INTO t VALUES (1);")
var persist: Int32 = -1
sqlite3_file_control(db, nil, SQLITE_FCNTL_PERSIST_WAL, &persist)
print("sqlite \(String(cString: sqlite3_libversion())); SQLITE_FCNTL_PERSIST_WAL default=\(persist)")
print("open, after a write: \(files())")
sqlite3_close(db)
print("after closing the only connection: \(files())")
