import Foundation
import GRDB

/// Shared definitions for the SIGKILL crash drill (I-03, T02, plan 19.2 "zero missing items").
/// The parent side needs `Process` and is macOS-only; see `CrashDrillParent`.
public enum CrashDrill {
    public enum Mode: String, Sendable, CaseIterable {
        /// Kill as soon as the parent reads the k-th acknowledgement (the child is already inside
        /// its next save).
        case afterAck = "after-ack"
        /// The child announces it is inside an open write transaction and pauses; the parent kills it
        /// there, so an uncommitted, half-written capture is guaranteed to exist at the kill.
        case inTransaction = "in-tx"
        /// Kill after a random 0-40 ms delay from spawn: lands during open, migration check, mid-save,
        /// between commit and acknowledgement, and so on.
        case randomTime = "random"
    }

    public static let seedWorkID = "00000000-0000-4000-8000-00000000c0de"

    public static func key(_ n: Int) -> String { "crash-\(n)" }
    public static func quote(_ n: Int) -> String { "Crash item \(n): \(GoldenCorpus.unicodeQuote)" }
    public static func comment(_ n: Int) -> String { "Comment \(n) ✓ — kept exactly" }

    public static func command(_ n: Int) -> CaptureCommand {
        CaptureCommand(
            workID: seedWorkID, editionID: nil, kind: .quote, quotedText: quote(n),
            snapshot: SourceSnapshot(title: "Crash drill", authorDisplay: "Fixture", locationLabel: "Item \(n)", sourceKind: "local_epub"),
            anchors: [
                AnchorInput(kind: .text, textOffsetUnit: "unicode_scalar", locatorJSON: #"{"item":\#(n),"part":0}"#),
                AnchorInput(kind: .text, textOffsetUnit: "unicode_scalar", locatorJSON: #"{"item":\#(n),"part":1}"#),
            ],
            comment: comment(n), idempotencyKey: key(n))
    }

    /// Creates the drill library and its one work.
    public static func seed(_ layout: LibraryLayout, durability: DurabilityPolicy) throws {
        var options = StoreOptions()
        options.durability = durability
        let store = try LibraryStore.open(layout, options: options)
        try store.pool.write { db in
            if try Bool.fetchOne(db, sql: "SELECT 1 FROM work WHERE id = ?", arguments: [seedWorkID]) == nil {
                try store.insertJournaled(db, "work", id: seedWorkID, [
                    "id": seedWorkID, "title": "Crash drill", "sort_title": "crash drill", "description": nil,
                    "language_tag": "en", "metadata_revision": 1, "created_at_ms": 0, "updated_at_ms": 0, "deleted_at_ms": nil,
                ])
            }
        }
        try store.close()
    }

    /// Child side: saves items `start..<start+count`, writing "ACK n" to stdout (an unbuffered
    /// `write(2)`) only after `saveCapture` has returned, i.e. after the commit.
    public static func runChild(root: URL, start: Int, count: Int, mode: Mode, durability: DurabilityPolicy) throws {
        var options = StoreOptions()
        options.durability = durability
        let store = try LibraryStore.open(LibraryLayout(root: root), options: options)
        for n in start..<(start + count) {
            let outcome = try store.saveCapture(command(n), beforeCommit: mode == .inTransaction ? {
                emit("INTX \(n)")
                usleep(150_000)
            } : nil)
            switch outcome {
            case .saved: emit("ACK \(n) saved")
            case .alreadySaved: emit("ACK \(n) already")
            }
        }
        try store.close()
    }

    static func emit(_ line: String) {
        let bytes = Array((line + "\n").utf8)
        bytes.withUnsafeBufferPointer { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(STDOUT_FILENO, buffer.baseAddress! + offset, buffer.count - offset)
                if written <= 0 { return }
                offset += written
            }
        }
    }

    /// Structural checks after a kill: every capture is complete (two anchors, one note with one
    /// revision, one ledger event, journal entries), nothing exists without its capture, every
    /// acknowledged item is present exactly once with exact text. Returns failure descriptions.
    public static func verify(_ db: Database, acknowledged: Set<Int>, checkContentOf: Set<Int>) throws -> [String] {
        var failures: [String] = []
        let quick = try String.fetchAll(db, sql: "PRAGMA quick_check")
        if quick != ["ok"] { failures.append("quick_check: \(quick.prefix(3))") }
        let incomplete = try Int.fetchOne(db, sql: """
            SELECT count(*) FROM capture c WHERE c.idempotency_key LIKE 'crash-%' AND (
              (SELECT count(*) FROM capture_anchor a WHERE a.capture_id = c.id) <> 2 OR
              (SELECT count(*) FROM note n WHERE n.capture_id = c.id) <> 1 OR
              (SELECT count(*) FROM note_revision r JOIN note n ON n.id = r.note_id WHERE n.capture_id = c.id) <> 1 OR
              (SELECT count(*) FROM ledger_event l WHERE l.capture_id = c.id) <> 1 OR
              (SELECT count(*) FROM change_journal j WHERE j.entity = 'capture' AND j.entity_id = c.id) <> 1)
            """) ?? -1
        if incomplete != 0 { failures.append("\(incomplete) capture(s) not complete") }
        let orphanLedger = try Int.fetchOne(db, sql: "SELECT count(*) FROM ledger_event WHERE event_type = 'capture_saved' AND capture_id IS NULL") ?? -1
        if orphanLedger != 0 { failures.append("\(orphanLedger) ledger event(s) without capture") }
        let orphanNotes = try Int.fetchOne(db, sql: "SELECT count(*) FROM note WHERE capture_id IS NULL AND work_id = ?", arguments: [seedWorkID]) ?? -1
        if orphanNotes != 0 { failures.append("\(orphanNotes) note(s) without capture") }
        let orphanRevisions = try Int.fetchOne(db, sql: "SELECT count(*) FROM note_revision r WHERE NOT EXISTS (SELECT 1 FROM note n WHERE n.id = r.note_id)") ?? -1
        if orphanRevisions != 0 { failures.append("\(orphanRevisions) orphan note revision(s)") }
        let orphanJournal = try Int.fetchOne(db, sql: """
            SELECT count(*) FROM change_journal j WHERE j.entity = 'capture' AND NOT EXISTS (SELECT 1 FROM capture c WHERE c.id = j.entity_id)
            """) ?? -1
        if orphanJournal != 0 { failures.append("\(orphanJournal) journal entr(ies) for missing captures") }

        let present = Set(try String.fetchAll(db, sql: "SELECT idempotency_key FROM capture WHERE idempotency_key LIKE 'crash-%'")
            .compactMap { Int($0.dropFirst("crash-".count)) })
        let missing = acknowledged.subtracting(present)
        if !missing.isEmpty { failures.append("acknowledged but missing: \(missing.sorted().prefix(10))") }
        for n in checkContentOf.sorted() {
            let row = try Row.fetchOne(db, sql: """
                SELECT c.quoted_text, r.body, (SELECT count(*) FROM capture WHERE idempotency_key = ?) AS copies
                FROM capture c JOIN note nt ON nt.capture_id = c.id JOIN note_revision r ON r.note_id = nt.id
                WHERE c.idempotency_key = ?
                """, arguments: [key(n), key(n)])
            guard let row else { failures.append("item \(n) missing"); continue }
            if (row["copies"] as Int) != 1 { failures.append("item \(n) has \(row["copies"] as Int) copies") }
            if (row["quoted_text"] as String) != quote(n) { failures.append("item \(n) quote differs") }
            if (row["body"] as String) != comment(n) { failures.append("item \(n) note differs") }
        }
        return failures
    }
}

/// SplitMix64, for reproducible drills.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

#if os(macOS)
/// Parent side of the crash drill: spawns the tool as a child, SIGKILLs it, reopens and verifies.
public struct CrashDrillParent {
    public struct Report: Sendable, CustomStringConvertible {
        public var durability = ""
        public var iterations = 0
        public var killsByMode: [String: Int] = [:]
        public var killedInsideTransaction = 0
        /// In-tx kills that arrived after the child's 150 ms pause ended and the item committed
        /// (informational; such an item is committed-but-unacknowledged and is retried).
        public var inTransactionKillsAfterCommit = 0
        public var childrenFinishedWithoutKill = 0
        public var acknowledged = 0
        public var committedButUnacknowledged = 0
        public var retriesDeduplicated = 0
        public var totalCaptures = 0
        public var failures: [String] = []

        public var description: String {
            var lines = [
                "durability: \(durability)",
                "iterations: \(iterations)",
                "SIGKILLs by mode: " + killsByMode.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "),
                "kills while a write transaction was open, in-flight item absent after reopen (in-tx mode): \(killedInsideTransaction)",
                "in-tx kills that landed after the commit instead: \(inTransactionKillsAfterCommit)",
                "children that finished before the kill: \(childrenFinishedWithoutKill)",
                "acknowledged items: \(acknowledged)",
                "committed but unacknowledged items (allowed; UI never said Saved; retry deduplicated): \(committedButUnacknowledged)",
                "retries answered 'already saved' instead of duplicating: \(retriesDeduplicated)",
                "captures in library: \(totalCaptures)",
                "failures: \(failures.count)",
            ]
            lines += failures.prefix(20).map { "  FAIL \($0)" }
            return lines.joined(separator: "\n")
        }
    }

    public var executable: URL
    public var root: URL
    public var iterations: Int
    public var seed: UInt64
    public var durability: DurabilityPolicy
    public var itemsPerChild = 12
    public var log: (String) -> Void = { _ in }

    public init(executable: URL, root: URL, iterations: Int, seed: UInt64, durability: DurabilityPolicy) {
        self.executable = executable
        self.root = root
        self.iterations = iterations
        self.seed = seed
        self.durability = durability
    }

    public func run() throws -> Report {
        var rng = SeededRandom(seed: seed)
        let layout = LibraryLayout(root: root)
        try CrashDrill.seed(layout, durability: durability)
        var report = Report()
        report.durability = durability.description
        var acknowledged = Set<Int>()
        let stderrURL = root.appending(path: "child-stderr.log", directoryHint: .notDirectory)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)

        for iteration in 0..<iterations {
            let mode = CrashDrill.Mode.allCases[iteration % CrashDrill.Mode.allCases.count]
            let start = (acknowledged.max() ?? -1) + 1   // retries the item that may be committed but unacknowledged
            // Random-time children get far more work than 40 ms allows, so they are always still
            // running (and not yet reaped) when the kill is sent.
            let count = mode == .randomTime ? 2000 : itemsPerChild
            let process = Process()
            process.executableURL = executable
            process.arguments = ["crash-child", "--root", root.path, "--start", String(start), "--count", String(count),
                                 "--mode", mode.rawValue, "--sync", durability.synchronous.name.lowercased(),
                                 "--fullfsync", durability.fullfsync ? "1" : "0"]
            let out = Pipe()
            process.standardOutput = out
            let errHandle = try FileHandle(forWritingTo: stderrURL)
            try errHandle.seekToEnd()
            process.standardError = errHandle
            try process.run()
            try out.fileHandleForWriting.close()
            try errHandle.close()
            let pid = process.processIdentifier

            var killed = false
            var inTransactionItem: Int?
            func killChild() {
                guard !killed, process.isRunning else { return }
                kill(pid, SIGKILL)
                killed = true
            }
            var lines: [String] = []
            var buffer = Data()
            let reader = out.fileHandleForReading
            func consume(_ data: Data, onLine: (String) -> Void) {
                buffer.append(data)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                    buffer.removeSubrange(buffer.startIndex...newline)
                    lines.append(line)
                    onLine(line)
                }
            }
            switch mode {
            case .afterAck:
                let target = Int.random(in: 1...(itemsPerChild - 1), using: &rng)
                var acks = 0
                while true {
                    let data = reader.availableData
                    if data.isEmpty { break }
                    consume(data) { line in
                        if line.hasPrefix("ACK ") { acks += 1; if acks == target { killChild() } }
                    }
                }
            case .inTransaction:
                let target = Int.random(in: 1...3, using: &rng)
                var seen = 0
                while true {
                    let data = reader.availableData
                    if data.isEmpty { break }
                    consume(data) { line in
                        if line.hasPrefix("INTX ") {
                            seen += 1
                            if seen == target, !killed {
                                inTransactionItem = Int(line.dropFirst("INTX ".count))
                                killChild()
                            }
                        }
                    }
                }
            case .randomTime:
                usleep(UInt32.random(in: 0...40_000, using: &rng))
                killChild()
                while true {
                    let data = reader.availableData
                    if data.isEmpty { break }
                    consume(data) { _ in }
                }
            }
            process.waitUntilExit()
            // A kill counts only if the child really died of SIGKILL: a child that had already
            // exited (a zombie not yet reaped) when the signal was sent is counted as finished.
            let diedOfSIGKILL = process.terminationReason == .uncaughtSignal && process.terminationStatus == SIGKILL
            if killed && diedOfSIGKILL {
                report.killsByMode[mode.rawValue, default: 0] += 1
            } else if process.terminationReason == .exit && process.terminationStatus == 0 {
                report.childrenFinishedWithoutKill += 1
            } else {
                report.failures.append("iteration \(iteration): child failed (reason \(process.terminationReason.rawValue), status \(process.terminationStatus))")
            }
            var newlyAcked = Set<Int>()
            for line in lines where line.hasPrefix("ACK ") {
                let parts = line.split(separator: " ")
                guard parts.count == 3, let n = Int(parts[1]) else { report.failures.append("bad line \(line)"); continue }
                newlyAcked.insert(n)
                if parts[2] == "already" { report.retriesDeduplicated += 1 }
            }
            acknowledged.formUnion(newlyAcked)

            var options = StoreOptions()
            options.durability = durability
            let store = try LibraryStore.open(layout, options: options)
            let (failures, inFlightCommitted) = try store.pool.read { db in
                (try CrashDrill.verify(db, acknowledged: acknowledged, checkContentOf: newlyAcked),
                 try inTransactionItem.map {
                     try Int.fetchOne(db, sql: "SELECT count(*) FROM capture WHERE idempotency_key = ?", arguments: [CrashDrill.key($0)]) ?? 0
                 })
            }
            try store.close()
            // In-transaction kills: the item whose transaction was open at the kill must be wholly
            // absent after reopening (rolled back), which also proves the kill landed before COMMIT.
            if killed && diedOfSIGKILL, mode == .inTransaction, let item = inTransactionItem {
                if inFlightCommitted == 0 {
                    report.killedInsideTransaction += 1
                } else {
                    report.inTransactionKillsAfterCommit += 1
                    if newlyAcked.contains(item) { report.failures.append("iteration \(iteration): in-transaction item \(item) was acknowledged before the kill") }
                }
            }
            report.failures += failures.map { "iteration \(iteration) (\(mode.rawValue)): \($0)" }
            report.iterations = iteration + 1
            if iteration % 100 == 99 { log("  \(iteration + 1) iterations, \(acknowledged.count) acknowledged, \(report.failures.count) failures") }
        }

        var options = StoreOptions()
        options.durability = durability
        let store = try LibraryStore.open(layout, options: options)
        try store.pool.read { db in
            let integrity = try LibraryChecks.integrity(db)
            if integrity != ["ok"] { report.failures.append("final integrity_check: \(integrity.prefix(3))") }
            let fk = try LibraryChecks.foreignKeyViolations(db)
            if !fk.isEmpty { report.failures.append("final foreign_key_check: \(fk.count)") }
            report.failures += try CrashDrill.verify(db, acknowledged: acknowledged, checkContentOf: acknowledged).map { "final: \($0)" }
            let present = try Int.fetchOne(db, sql: "SELECT count(*) FROM capture WHERE idempotency_key LIKE 'crash-%'") ?? 0
            report.totalCaptures = present
            report.committedButUnacknowledged = present - acknowledged.count
            let ledger = try Int.fetchOne(db, sql: "SELECT count(*) FROM ledger_event WHERE event_type = 'capture_saved'") ?? 0
            if ledger != present { report.failures.append("ledger events \(ledger) != captures \(present) (duplicate or missing ledger activity)") }
        }
        try store.close()
        report.acknowledged = acknowledged.count
        return report
    }
}
#endif
