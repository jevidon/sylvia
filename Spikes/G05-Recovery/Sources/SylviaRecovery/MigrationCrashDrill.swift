import Foundation
import GRDB

/// SIGKILL drill for the failed-migration put-back (plan 7.4, T45): a child process opens a v1
/// library whose destructive migration fails (it throws, or silently drops rows and fails the
/// post-migration check), so the pre-migration snapshot is put back. The parent kills the child at
/// every step of that sequence and at random times, then reopens through the normal launch path and
/// checks that the library is never empty or partial: the first reopen either migrates the intact
/// library or finishes the put-back (and reports it), and the next open migrates. The parent side
/// needs `Process` and is macOS-only.
public enum MigrationCrashDrill {
    public enum Fault: String, Sendable, CaseIterable {
        case throwing = "throw"
        case dropRows = "drop"
    }

    /// Steps the failure path reports, in order (`migrationChecked` is the success path only).
    public static let failurePathSteps: [PutBackStep] = PutBackStep.allCases.filter { $0 != .migrationChecked }

    /// Child side. Prints `OPEN`, then `STEP <step>` after each step (sleeping `pauseMs` after
    /// `pauseAfter`, so a kill sent on that line lands exactly there), `FAILED` when the open reports
    /// the migration failure with the snapshot put back, and `DONE`.
    public static func runChild(root: URL, fault: Fault, pauseAfter: PutBackStep?, pauseMs: UInt32) throws {
        var options = StoreOptions()
        switch fault {
        case .throwing: options.faults.throwDuringRecommendationRebuild = true
        case .dropRows: options.faults.dropRowsDuringRecommendationRebuild = true
        }
        options.putBackHooks = PutBackHooks(afterStep: { step in
            CrashDrill.emit("STEP \(step.rawValue)")
            if step == pauseAfter { usleep(pauseMs * 1000) }
        })
        CrashDrill.emit("OPEN")
        do {
            let store = try LibraryStore.open(LibraryLayout(root: root), options: options)
            try store.close()
            throw StoreError.invalid("the faulty migration unexpectedly succeeded")
        } catch StoreError.migrationFailed(_, _, true), StoreError.postMigrationCheckFailed(_, true) {
            CrashDrill.emit("FAILED")
        }
        CrashDrill.emit("DONE")
    }
}

#if os(macOS)
public struct MigrationCrashDrillParent {
    public struct Report: Sendable, CustomStringConvertible {
        public var iterations = 0
        public var calibrationMs = 0.0
        /// Kills by plan: `<mode> <step>`.
        public var killsByPlan: [String: Int] = [:]
        /// The last line a killed child printed: how far it got before the kill.
        public var killsByLastLine: [String: Int] = [:]
        public var childrenFinishedBeforeKill = 0
        /// What the first reopen after each run did.
        public var firstReopen: [String: Int] = [:]
        public var failures: [String] = []

        public var description: String {
            var lines = [
                "iterations: \(iterations)",
                String(format: "measured unkilled run (open, snapshot, failed migration, put-back): %.1f ms", calibrationMs),
                "SIGKILLs by plan: " + killsByPlan.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "),
                "SIGKILLs by the last line the child printed: " + killsByLastLine.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "),
                "children that finished before the kill: \(childrenFinishedBeforeKill)",
                "first reopen: " + firstReopen.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "),
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

    struct Expectation {
        /// Knowledge rows of the v1 library: what the put-back must restore.
        var v1Dump: String
        /// Knowledge rows after a clean v1 -> v2 migration of the same library.
        var v2Dump: String
        var deviceID: String
    }

    public func run() throws -> Report {
        let fm = FileManager.default
        var rng = SeededRandom(seed: seed)
        var report = Report()
        try FileProtector.library.ensureDirectory(workDirectory)

        // A v1 library holding the golden corpus.
        let template = workDirectory.appending(path: "Template", directoryHint: .isDirectory)
        var v1 = StoreOptions()
        v1.migrateUpTo = "v1-initial"
        let seeded = try LibraryStore.open(LibraryLayout(root: template), options: v1)
        _ = try GoldenCorpus.build(in: seeded, sourceDirectory: workDirectory.appending(path: "TemplateMedia", directoryHint: .isDirectory))
        let v1Dump = try seeded.pool.read { try LibraryChecks.knowledgeDump($0) }
        let deviceID = seeded.deviceID
        try seeded.close()

        let root = workDirectory.appending(path: "Install", directoryHint: .isDirectory)
        func reset() throws {
            if fm.fileExists(atPath: root.path) { try fm.removeItem(at: root) }
            // Created with the library's class, never `FileManager.copyItem`, which keeps the template's.
            try FileProtector.library.copyTree(from: template, to: root)
        }
        // The clean migration of the same library gives the expected final state.
        try reset()
        let reference = try LibraryStore.open(LibraryLayout(root: root))
        let v2Dump = try reference.pool.read { try LibraryChecks.knowledgeDump($0) }
        try reference.close()
        guard v2Dump != v1Dump else { throw StoreError.invalid("v1 and v2 dumps are indistinguishable") }
        let expectation = Expectation(v1Dump: v1Dump, v2Dump: v2Dump, deviceID: deviceID)

        let stderrURL = workDirectory.appending(path: "child-stderr.log", directoryHint: .notDirectory)
        fm.createFile(atPath: stderrURL.path, contents: nil)

        // Calibration: one unkilled run gives the duration for random kills, and must itself verify.
        try reset()
        let calibration = try spawn(root: root, fault: .throwing, pauseAfter: nil, stderr: stderrURL, kill: nil)
        guard calibration.lines.last == "DONE", calibration.lines.contains("FAILED"),
              let opened = calibration.times["OPEN"], let done = calibration.times["DONE"] else {
            throw StoreError.invalid("calibration run did not fail and put back as expected: \(calibration.lines)")
        }
        report.calibrationMs = (done - opened) * 1000
        let (calibrationOutcome, calibrationProblems) = verify(root: root, expectation: expectation)
        guard calibrationProblems.isEmpty, calibrationOutcome == "migrated" else {
            throw StoreError.invalid("calibration run did not verify: \(calibrationOutcome) \(calibrationProblems)")
        }
        log(String(format: "calibration: %.1f ms from OPEN to DONE", report.calibrationMs))

        let steps = MigrationCrashDrill.failurePathSteps
        for iteration in 0..<iterations {
            try reset()
            // Modes: "pause" stops the child right after the step and kills it there; "delay" kills
            // 0-3 ms after the step's marker while the child runs on; "random" kills at a random time
            // within an unkilled run's duration after OPEN (the migration itself included).
            let mode = ["pause", "delay", "random"][iteration % 3]
            let step = steps[(iteration / 3) % steps.count]
            let fault = MigrationCrashDrill.Fault.allCases[(iteration / (3 * steps.count)) % 2]
            let plan: (after: String, delayMicroseconds: UInt32)
            let pauseAfter: PutBackStep?
            switch mode {
            case "pause":
                plan = ("STEP \(step.rawValue)", 0)
                pauseAfter = step
            case "delay":
                plan = ("STEP \(step.rawValue)", UInt32.random(in: 0...3000, using: &rng))
                pauseAfter = nil
            default:
                plan = ("OPEN", UInt32(Double.random(in: 0...max(report.calibrationMs, 1), using: &rng) * 1000))
                pauseAfter = nil
            }
            let label = mode == "random" ? "random" : "\(mode) \(step.rawValue)"
            let run = try spawn(root: root, fault: fault, pauseAfter: pauseAfter, stderr: stderrURL, kill: plan)
            if run.killed {
                report.killsByPlan[label, default: 0] += 1
                report.killsByLastLine[run.lines.last ?? "none", default: 0] += 1
            } else if run.exitedCleanly {
                report.childrenFinishedBeforeKill += 1
            } else {
                report.failures.append("iteration \(iteration): child failed: \(run.lines)")
            }
            let (outcome, problems) = verify(root: root, expectation: expectation)
            report.firstReopen[outcome, default: 0] += 1
            report.failures += problems.map { "iteration \(iteration) (\(label), fault \(fault.rawValue), killed \(run.killed), last line \(run.lines.last ?? "none")): \($0)" }
            report.iterations = iteration + 1
            if iteration % 40 == 39 { log("  \(iteration + 1) iterations, \(report.failures.count) failures") }
        }
        return report
    }

    /// Reopens through the launch path (as a fixed build would: no fault) and checks the result.
    /// Returns the first reopen's outcome and any problems.
    func verify(root: URL, expectation: Expectation) -> (String, [String]) {
        let layout = LibraryLayout(root: root)
        var problems: [String] = []
        var outcome: String
        var store: LibraryStore?
        do {
            store = try LibraryStore.open(layout)
            outcome = "migrated"
        } catch StoreError.migrationInterrupted {
            outcome = "put back, then migrated at the next open"
            // What the recovery screen shows: the complete v1 library.
            do {
                let queue = try RecoveryAccess.openReadOnly(layout.databaseURL)
                let (applied, dump) = try queue.read { (try LibrarySchema.applied($0), try LibraryChecks.knowledgeDump($0)) }
                try queue.close()
                if applied != ["v1-initial"] { problems.append("put-back library has migrations \(applied)") }
                if dump != expectation.v1Dump { problems.append("put-back library differs from the v1 library") }
            } catch { problems.append("put-back library unreadable: \(error)") }
            do { store = try LibraryStore.open(layout) } catch { problems.append("open after the put-back failed: \(error)") }
        } catch {
            return ("open failed", ["reopen failed: \(error)"])
        }
        guard let store else { return (outcome, problems) }
        defer { try? store.close() }
        do {
            try store.pool.read { db in
                if try LibraryChecks.knowledgeDump(db) != expectation.v2Dump { problems.append("library is not the complete migrated library") }
                if try LibraryChecks.integrity(db) != ["ok"] { problems.append("integrity_check failed") }
                if try !LibraryChecks.foreignKeyViolations(db).isEmpty { problems.append("foreign key violations") }
            }
            if try store.schemaVersion != LibrarySchema.currentVersion { problems.append("schema version \(try store.schemaVersion)") }
        } catch { problems.append("read failed: \(error)") }
        if store.openReport.appliedNow != LibrarySchema.migrations.map(\.identifier) {
            problems.append("applied migrations \(store.openReport.appliedNow)")
        }
        if store.deviceID != expectation.deviceID { problems.append("device identity changed") }
        let fm = FileManager.default
        if fm.fileExists(atPath: layout.migrationPutBackIntentURL.path) { problems.append("put-back intent left behind") }
        let staged = ((try? fm.contentsOfDirectory(atPath: layout.stagingDirectory.path)) ?? []).filter { $0.hasPrefix("putback-") }
        if !staged.isEmpty { problems.append("staged put-back copies left behind: \(staged)") }
        return (outcome, problems)
    }

    struct ChildRun {
        var lines: [String] = []
        var times: [String: TimeInterval] = [:]
        var killed = false
        var exitedCleanly = false
    }

    /// Runs one child. With `kill`, sends SIGKILL `delayMicroseconds` after the given marker line.
    func spawn(root: URL, fault: MigrationCrashDrill.Fault, pauseAfter: PutBackStep?, stderr: URL,
               kill plan: (after: String, delayMicroseconds: UInt32)?) throws -> ChildRun {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["migration-crash-child", "--root", root.path, "--fault", fault.rawValue,
                             "--pause-after", pauseAfter?.rawValue ?? "none", "--pause-ms", "300"]
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
                    if plan.delayMicroseconds > 0 { usleep(plan.delayMicroseconds) }
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
