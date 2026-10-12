import Foundation
import GRDB
import Testing
@testable import SylviaRecovery

@Suite("Durable saves (I-03, T02, plan 19.2)")
struct DurabilityTests {
    @Test("the writer runs WAL + synchronous=FULL + fullfsync, read back after open")
    func policyApplied() throws {
        let scratch = try Scratch()
        let store = try LibraryStore.open(scratch.layout())
        defer { try? store.close() }
        let observed = try store.pool.writeWithoutTransaction { try DurabilityPolicy.observe($0) }
        evidence("writer pragmas: \(observed)")
        let sqlite = try store.pool.read { db in
            (try String.fetchOne(db, sql: "SELECT sqlite_version()") ?? "?",
             try String.fetchAll(db, sql: "PRAGMA compile_options").filter { $0.contains("SYNCHRONOUS") || $0.contains("FULLFSYNC") || $0.hasPrefix("ENABLE_FTS5") })
        }
        evidence("SQLite \(sqlite.0); \(sqlite.1.joined(separator: " "))")
        #expect(sqlite.1.contains("ENABLE_FTS5"), "FTS5 is the plan's search baseline (11.3)")
        #expect(observed.journalMode == "wal")
        #expect(observed.synchronous == .full)
        #expect(observed.fullfsync)
        #expect(observed.checkpointFullfsync)
    }

    @Test("finding: GRDB's DatabasePool resets synchronous to NORMAL after prepareDatabase")
    func grdbOverridesPrepareDatabase() throws {
        let scratch = try Scratch()
        var config = Configuration()
        config.prepareDatabase { db in try db.execute(sql: "PRAGMA synchronous = FULL") }
        let pool = try DatabasePool(path: scratch.url.appending(path: "probe.sqlite").path, configuration: config)
        defer { try? pool.close() }
        let value = try pool.writeWithoutTransaction { try Int.fetchOne($0, sql: "PRAGMA synchronous") }
        evidence("synchronous after prepareDatabase(FULL) on a DatabasePool writer: \(value ?? -1) (1 = NORMAL)")
        // If this ever changes, LibraryStore's explicit post-open apply is still correct; the test
        // documents why the apply is needed with GRDB 7.11.1.
        #expect(value == DurabilityPolicy.Synchronous.normal.rawValue)
    }

    @Test("storage full during a capture save: nothing half-written, earlier saves intact, retry saves once (simulated with max_page_count)")
    func storageFull() throws {
        let scratch = try Scratch()
        let layout = scratch.layout()
        try CrashDrill.seed(layout, durability: .acknowledgedSaves)
        let store = try LibraryStore.open(layout)
        defer { try? store.close() }
        for n in 0..<20 { try store.saveCapture(CrashDrill.command(n)) }
        // Cap the database at its current size: the next page allocation fails with SQLITE_FULL,
        // which is what SQLite reports when the volume itself is full.
        let pages = try store.pool.writeWithoutTransaction { db -> Int in
            let count = try Int.fetchOne(db, sql: "PRAGMA page_count") ?? 0
            _ = try Int.fetchOne(db, sql: "PRAGMA max_page_count = \(count)")
            return count
        }
        var big = CrashDrill.command(100)
        big.comment = String(repeating: "A long note that no longer fits. ", count: 2000)
        var failure: DatabaseError?
        do { try store.saveCapture(big) } catch let error as DatabaseError { failure = error }
        evidence("save with storage full: \(failure.map { "\($0.resultCode)" } ?? "no error") at \(pages) pages")
        #expect(failure?.resultCode == .SQLITE_FULL)
        try store.pool.read { (db: Database) throws in
            #expect(try CrashDrill.verify(db, acknowledged: Set(0..<20), checkContentOf: Set(0..<20)).isEmpty)
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM capture WHERE idempotency_key = 'crash-100'") == 0)
        }
        // Space is freed; the editor still holds the command and retries it.
        _ = try store.pool.writeWithoutTransaction { try Int.fetchOne($0, sql: "PRAGMA max_page_count = 1073741823") }
        guard case .saved = try store.saveCapture(big) else { Issue.record("retry should save"); return }
        #expect(try store.saveCapture(big) == .alreadySaved(captureID: big.captureID))
        try store.pool.read { (db: Database) throws in
            #expect(try CrashDrill.verify(db, acknowledged: Set(0..<20), checkContentOf: Set(0..<20)).isEmpty)
            #expect(try String.fetchOne(db, sql: """
                SELECT r.body FROM capture c JOIN note n ON n.capture_id = c.id JOIN note_revision r ON r.note_id = n.id
                WHERE c.idempotency_key = 'crash-100'
                """) == big.comment)
        }
    }

    #if os(macOS)
    /// The real path a phone with a full disk takes: the OS refuses to grow the WAL (ENOSPC) while
    /// SQLite appends a commit. The library lives on a small APFS disk image that is filled to the
    /// last block. (`storageFull` above only exercises SQLite's own page limit.)
    @Test("storage full on a real volume: the WAL append fails, nothing half-written, earlier saves intact after reopen, retry saves once",
          .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/hdiutil"), "needs hdiutil (macOS host)"))
    func storageFullRealVolume() throws {
        let scratch = try Scratch()
        let image = scratch.url.appending(path: "full.dmg")
        let mountPoint = scratch.dir("mnt")
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        try runTool("/usr/bin/hdiutil", ["create", "-size", "64m", "-fs", "APFS", "-volname", "G05Full", "-type", "UDIF", image.path])
        try runTool("/usr/bin/hdiutil", ["attach", "-nobrowse", "-noautoopen", "-mountpoint", mountPoint.path, image.path])
        defer { _ = try? runTool("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"]) }

        let layout = LibraryLayout(root: mountPoint.appending(path: "Install", directoryHint: .isDirectory))
        try CrashDrill.seed(layout, durability: .acknowledgedSaves)
        var store = try LibraryStore.open(layout)
        for n in 0..<20 { try store.saveCapture(CrashDrill.command(n)) }

        // Fill the volume: 1 MiB writes until the OS refuses, then 64 KiB, 4 KiB and 512 bytes, flushing
        // and repeating until a whole round adds nothing (APFS can release blocks after a flush).
        let filler = mountPoint.appending(path: "filler.bin")
        FileManager.default.createFile(atPath: filler.path, contents: nil)
        let handle = try FileHandle(forWritingTo: filler)
        var filled: Int64 = 0
        var fillError = ""
        for _ in 0..<5 {
            let before = filled
            for chunk in [1 << 20, 64 << 10, 4 << 10, 512] {
                let data = Data(repeating: 0xA5, count: chunk)
                while true {
                    do { try handle.write(contentsOf: data); filled += Int64(chunk) } catch { fillError = "\(error.localizedDescription)"; break }
                }
            }
            _ = fcntl(handle.fileDescriptor, F_FULLFSYNC)
            if filled == before { break }
        }
        try? handle.close()
        let free = try mountPoint.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity ?? -1

        // A note of about 8 MiB: far more than any space APFS still reports free on the filled volume,
        // so the WAL cannot hold the commit.
        var big = CrashDrill.command(100)
        big.comment = String(repeating: "A long note that no longer fits. ", count: 250_000)
        var failure: DatabaseError?
        do { try store.saveCapture(big) } catch let error as DatabaseError { failure = error }
        evidence("real full volume (64 MiB APFS disk image, filler \(filled) bytes, last fill error: \(fillError), \(free) bytes reported free), saving a capture with a \(big.comment!.utf8.count)-byte note: save -> \(failure.map { "\($0.resultCode) (extended \($0.extendedResultCode)): \($0.message ?? "")" } ?? "no error")")
        #expect(failure?.resultCode == .SQLITE_FULL)
        try store.pool.read { (db: Database) throws in
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM capture WHERE idempotency_key = 'crash-100'") == 0)
        }
        try store.close()

        // Space is freed; reopen from disk and check what is there before the retry.
        try FileManager.default.removeItem(at: filler)
        store = try LibraryStore.open(layout)
        defer { try? store.close() }
        try store.pool.read { (db: Database) throws in
            #expect(try LibraryChecks.integrity(db) == ["ok"])
            #expect(try LibraryChecks.foreignKeyViolations(db).isEmpty)
            #expect(try CrashDrill.verify(db, acknowledged: Set(0..<20), checkContentOf: Set(0..<20)).isEmpty)
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM capture WHERE idempotency_key = 'crash-100'") == 0)
        }
        guard case .saved = try store.saveCapture(big) else { Issue.record("retry should save"); return }
        #expect(try store.saveCapture(big) == .alreadySaved(captureID: big.captureID))
        try store.pool.read { (db: Database) throws in
            #expect(try CrashDrill.verify(db, acknowledged: Set(0..<20).union([100]), checkContentOf: Set(0..<20)).isEmpty)
        }
    }

    @discardableResult
    func runTool(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw StoreError.invalid("\(path) \(arguments.joined(separator: " ")) failed (\(process.terminationStatus)): \(output)")
        }
        return output
    }
    #endif

    @Test("capture save latency against the 200 ms p95 budget (indicative)")
    func latency() throws {
        let scratch = try Scratch()
        let result = try LatencyBench.run(root: scratch.dir("latency"), durability: .acknowledgedSaves, iterations: 400, preload: 200)
        evidence("capture save latency \(result)")
        #expect(result.p95Ms <= 200)
    }

    #if os(macOS)
    @Test("SIGKILL crash drill (short run; the CI drill runs many hundreds of kills)")
    func crashDrillShort() throws {
        let scratch = try Scratch()
        let executable = toolExecutable()
        #expect(FileManager.default.isExecutableFile(atPath: executable.path), "tool not built at \(executable.path)")
        let drill = CrashDrillParent(executable: executable, root: scratch.dir("crash"), iterations: 60, seed: 7,
                                     durability: .acknowledgedSaves)
        let report = try drill.run()
        evidence("crash drill (short)\n\(report)")
        #expect(report.failures.isEmpty)
        #expect(report.killsByMode.values.reduce(0, +) >= 50)
        #expect(report.killedInsideTransaction >= 15)
        #expect(report.acknowledged > 0)
    }
    #endif
}
