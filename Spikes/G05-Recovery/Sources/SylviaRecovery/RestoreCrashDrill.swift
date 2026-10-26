import Foundation
import GRDB

/// SIGKILL drill for restore (T47 "restore crash"): a child process opens an active library,
/// prepares a restore from a bundle and commits it with confirmation; the parent kills it at random
/// points of the preparation or of the swap, then reopens through the normal launch path and checks
/// that the library is exactly the old one or exactly the restored one, never a mix, never empty,
/// with nothing left pending. The parent side needs `Process` and is macOS-only.
public enum RestoreCrashDrill {
    /// Child side. Prints `PREPARE` before validation and copying, `COMMIT` before the swap,
    /// `STEP <step>` after each swap step (after `STEP restoredMovedIn` the intent is removed and the
    /// restored library opened), and `DONE` once it is open.
    public static func runChild(root: URL, bundle: URL) throws {
        let layout = LibraryLayout(root: root)
        let store = try LibraryStore.open(layout)
        let restorer = BackupRestorer(layout: layout)
        CrashDrill.emit("PREPARE")
        let plan = try restorer.prepare(bundle: bundle)
        CrashDrill.emit("COMMIT")
        let hooks = RestoreHooks(afterStep: { step in CrashDrill.emit("STEP \(step.rawValue)") })
        let result = try restorer.commit(plan, confirmation: .replaceExistingLibrary, activeStore: store, hooks: hooks)
        try result.store.close()
        CrashDrill.emit("DONE")
    }
}

#if os(macOS)
public struct RestoreCrashDrillParent {
    /// Where a kill is aimed. Half the iterations kill during `prepare` at a random time within its
    /// typical duration (the median of the runs seen so far); the other half kill 0-3 ms after one of
    /// the swap's markers, cycling through them, so every step of the swap is hit whatever the
    /// machine's load.
    static let commitMarkers = ["COMMIT", "STEP intentWritten", "STEP activeMovedAside", "STEP restoredMovedIn"]

    public struct Report: Sendable, CustomStringConvertible {
        public var iterations = 0
        public var prepareMs = 0.0
        public var commitMs = 0.0
        public var killsByWindow: [String: Int] = [:]
        /// The last line a killed child printed: how far it got before the kill.
        public var killsByLastLine: [String: Int] = [:]
        public var childrenFinishedBeforeKill = 0
        public var outcomes: [String: Int] = [:]
        public var reconciliations: [String: Int] = [:]
        public var failures: [String] = []

        public var description: String {
            var lines = [
                "iterations: \(iterations)",
                String(format: "measured unkilled run: prepare %.1f ms, commit (swap) %.1f ms", prepareMs, commitMs),
                "SIGKILLs by window: " + killsByWindow.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "),
                "SIGKILLs by the last step the child reported: " + killsByLastLine.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "),
                "children that finished before the kill: \(childrenFinishedBeforeKill)",
                "library after reopen: " + outcomes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "),
                "launch reconciliation: " + reconciliations.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "),
                "failures: \(failures.count)",
            ]
            lines += failures.prefix(20).map { "  FAIL \($0)" }
            return lines.joined(separator: "\n")
        }
    }

    public var executable: URL
    public var workDirectory: URL
    public var iterations: Int
    public var seed: UInt64
    public var log: (String) -> Void = { _ in }

    public init(executable: URL, workDirectory: URL, iterations: Int, seed: UInt64) {
        self.executable = executable
        self.workDirectory = workDirectory
        self.iterations = iterations
        self.seed = seed
    }

    /// What the parent knows about the two acceptable end states.
    struct Expectation {
        var oldDump: String
        var newDump: String
        var deviceID: String
    }

    public func run() throws -> Report {
        let fm = FileManager.default
        var rng = SeededRandom(seed: seed)
        var report = Report()
        try FileProtector.library.ensureDirectory(workDirectory)

        // A backup made from the golden corpus.
        let sourceLayout = LibraryLayout(root: workDirectory.appending(path: "Source", directoryHint: .isDirectory))
        let source = try LibraryStore.open(sourceLayout)
        _ = try GoldenCorpus.build(in: source, sourceDirectory: workDirectory.appending(path: "SourceMedia", directoryHint: .isDirectory))
        let bundle = workDirectory.appending(path: "Exports/drill.sylviabackup", directoryHint: .isDirectory)
        try FileProtector.library.ensureDirectory(bundle.deletingLastPathComponent())
        _ = try BackupExporter(source).export(to: bundle)
        try source.close()

        // The active library each iteration starts from: one work and one capture of its own.
        let template = workDirectory.appending(path: "Template", directoryHint: .isDirectory)
        let templateLayout = LibraryLayout(root: template)
        try CrashDrill.seed(templateLayout, durability: .acknowledgedSaves)
        let seeded = try LibraryStore.open(templateLayout)
        try seeded.saveCapture(CrashDrill.command(0))
        let oldDump = try seeded.pool.read { try LibraryChecks.knowledgeDump($0) }
        let deviceID = seeded.deviceID
        try seeded.close()

        let root = workDirectory.appending(path: "Install", directoryHint: .isDirectory)
        let stderrURL = workDirectory.appending(path: "child-stderr.log", directoryHint: .notDirectory)
        fm.createFile(atPath: stderrURL.path, contents: nil)

        func reset() throws {
            if fm.fileExists(atPath: root.path) { try fm.removeItem(at: root) }
            // Created with the library's class, never `FileManager.copyItem`, which keeps the template's.
            try FileProtector.library.copyTree(from: template, to: root)
        }

        // Calibration: one unkilled run gives the restored state and the two windows' durations.
        try reset()
        let calibration = try spawn(root: root, bundle: bundle, stderr: stderrURL, kill: nil)
        guard calibration.lines.last == "DONE", let prepared = calibration.times["PREPARE"],
              let committing = calibration.times["COMMIT"], let done = calibration.times["DONE"] else {
            throw StoreError.invalid("calibration restore did not finish: \(calibration.lines)")
        }
        report.prepareMs = (committing - prepared) * 1000
        report.commitMs = (done - committing) * 1000
        var prepareSamples = [report.prepareMs]
        let restored = try LibraryStore.open(LibraryLayout(root: root))
        let newDump = try restored.pool.read { try LibraryChecks.knowledgeDump($0) }
        try restored.close()
        guard newDump != oldDump else { throw StoreError.invalid("restored and old libraries are indistinguishable") }
        let expectation = Expectation(oldDump: oldDump, newDump: newDump, deviceID: deviceID)
        log(String(format: "calibration: prepare %.1f ms, commit %.1f ms", report.prepareMs, report.commitMs))

        for iteration in 0..<iterations {
            try reset()
            let window = iteration % 2 == 0 ? "prepare" : "commit"
            let plan: (after: String, delayMicroseconds: UInt32)
            if window == "prepare" {
                let typical = prepareSamples.sorted()[prepareSamples.count / 2]
                plan = ("PREPARE", UInt32(Double.random(in: 0...max(typical * 0.9, 0.1), using: &rng) * 1000))
            } else {
                plan = (Self.commitMarkers[(iteration / 2) % Self.commitMarkers.count], UInt32.random(in: 0...3000, using: &rng))
            }
            let run = try spawn(root: root, bundle: bundle, stderr: stderrURL, kill: plan)
            if let start = run.times["PREPARE"], let end = run.times["COMMIT"] { prepareSamples.append((end - start) * 1000) }
            if run.killed {
                report.killsByWindow[window, default: 0] += 1
                report.killsByLastLine[run.lines.last ?? "none", default: 0] += 1
            } else if run.exitedCleanly {
                report.childrenFinishedBeforeKill += 1
            } else {
                report.failures.append("iteration \(iteration): child failed: \(run.lines)")
            }
            let (outcome, reconciliation, problems) = verify(root: root, expectation: expectation)
            report.outcomes[outcome, default: 0] += 1
            report.reconciliations[reconciliation, default: 0] += 1
            report.failures += problems.map { "iteration \(iteration) (\(window) after \(plan.after), killed \(run.killed), last line \(run.lines.last ?? "none")): \($0)" }
            report.iterations = iteration + 1
            if iteration % 50 == 49 { log("  \(iteration + 1) iterations, \(report.failures.count) failures") }
        }
        return report
    }

    /// Reopens through the launch path and classifies the library. Returns (outcome, reconciliation, problems).
    func verify(root: URL, expectation: Expectation) -> (String, String, [String]) {
        let layout = LibraryLayout(root: root)
        var problems: [String] = []
        let store: LibraryStore
        do { store = try LibraryStore.open(layout) } catch {
            return ("open failed", "error", ["reopen failed: \(error)"])
        }
        defer { try? store.close() }
        let reconciliation = "\(store.openReport.restoreReconciliation)"
        var outcome = "mixed"
        do {
            try store.pool.read { db in
                let dump = try LibraryChecks.knowledgeDump(db)
                if dump == expectation.oldDump { outcome = "old library kept" }
                else if dump == expectation.newDump { outcome = "restored library" }
                else { problems.append("library is neither the old nor the restored one") }
                if try LibraryChecks.integrity(db) != ["ok"] { problems.append("integrity_check failed") }
                if try !LibraryChecks.foreignKeyViolations(db).isEmpty { problems.append("foreign key violations") }
                if outcome == "restored library",
                   try Int.fetchOne(db, sql: "SELECT count(*) FROM asset_location WHERE availability = 'on_device'") != 0 {
                    problems.append("restored library claims an original on this device")
                }
            }
        } catch { problems.append("read failed: \(error)") }
        if store.deviceID != expectation.deviceID { problems.append("device identity changed") }
        let fm = FileManager.default
        if fm.fileExists(atPath: layout.restoreIntentURL.path) { problems.append("restore intent left behind") }
        if let left = try? fm.contentsOfDirectory(atPath: layout.restoreWorkDirectory.path), !left.isEmpty {
            problems.append("restore work left behind: \(left)")
        }
        if outcome == "restored library" {
            // The replaced library must be kept as the pre-restore recovery copy.
            let copies = ((try? fm.contentsOfDirectory(at: layout.recoveryDirectory, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("pre-restore-") }
                .map { $0.appending(path: "Library/library.sqlite", directoryHint: .notDirectory) }
                .filter { fm.fileExists(atPath: $0.path) }
            let matching = copies.filter { url in
                guard let queue = try? RecoveryAccess.openReadOnly(url) else { return false }
                defer { try? queue.close() }
                return (try? queue.read { try LibraryChecks.knowledgeDump($0) }) == expectation.oldDump
            }
            if matching.count != 1 { problems.append("expected one pre-restore copy equal to the old library, found \(matching.count) of \(copies.count)") }
        }
        return (outcome, reconciliation, problems)
    }

    struct ChildRun {
        var lines: [String] = []
        var times: [String: TimeInterval] = [:]
        var killed = false
        var exitedCleanly = false
    }

    /// Runs one child. With `kill`, sends SIGKILL `delayMicroseconds` after the given marker line.
    func spawn(root: URL, bundle: URL, stderr: URL, kill plan: (after: String, delayMicroseconds: UInt32)?) throws -> ChildRun {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["restore-crash-child", "--root", root.path, "--bundle", bundle.path]
        let out = Pipe()
        process.standardOutput = out
        let errHandle = try FileHandle(forWritingTo: stderr)
        try errHandle.seekToEnd()
        process.standardError = errHandle
        try process.run()
        try out.fileHandleForWriting.close()
        try errHandle.close()
        let pid = process.processIdentifier
        var run = ChildRun()
        var sentKill = false
        var buffer = Data()
        let reader = out.fileHandleForReading
        while true {
            let data = reader.availableData
            if data.isEmpty { break }
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...newline)
                run.lines.append(line)
                run.times[line] = Date().timeIntervalSinceReferenceDate
                if let plan, line == plan.after, !sentKill {
                    usleep(plan.delayMicroseconds)
                    if process.isRunning { Darwin.kill(pid, SIGKILL) }
                    sentKill = true
                }
            }
        }
        process.waitUntilExit()
        run.killed = sentKill && process.terminationReason == .uncaughtSignal && process.terminationStatus == SIGKILL
        run.exitedCleanly = process.terminationReason == .exit && process.terminationStatus == 0
        return run
    }
}
#endif
