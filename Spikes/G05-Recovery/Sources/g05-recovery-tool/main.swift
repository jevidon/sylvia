// g05-recovery-tool: scripted runs for the G0.5 recovery spike (host only).
//
//   g05-recovery-tool env-report
//   g05-recovery-tool crash-drill --root DIR --iterations N [--seed S] [--sync full|normal|off] [--fullfsync 0|1]
//   g05-recovery-tool latency --root DIR [--iterations N]
//   g05-recovery-tool restore-drill --root DIR
//   g05-recovery-tool restore-crash-drill --root DIR --iterations N [--seed S]
//   g05-recovery-tool migration-crash-drill --root DIR --iterations N [--seed S]
//   g05-recovery-tool make-v1-fixture --out FILE
//   g05-recovery-tool crash-child ...            (internal: spawned by crash-drill)
//   g05-recovery-tool restore-crash-child ...    (internal: spawned by restore-crash-drill)
//   g05-recovery-tool migration-crash-child ...  (internal: spawned by migration-crash-drill)
#if os(macOS)
import Foundation
import GRDB
import SylviaRecovery

func argument(_ name: String, default value: String? = nil) -> String? {
    let args = CommandLine.arguments
    if let index = args.firstIndex(of: name), index + 1 < args.count { return args[index + 1] }
    return value
}

func require(_ name: String) -> String {
    guard let value = argument(name) else { fail("missing \(name)") }
    return value
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func policy() -> DurabilityPolicy {
    let sync: DurabilityPolicy.Synchronous
    switch argument("--sync", default: "full") {
    case "off": sync = .off
    case "normal": sync = .normal
    case "full": sync = .full
    default: fail("--sync must be off, normal or full")
    }
    return DurabilityPolicy(synchronous: sync, fullfsync: argument("--fullfsync", default: "1") == "1")
}

/// Recreates `path` with the library protection class, so that everything created inside it
/// inherits the class from the start.
func freshDirectory(_ path: String) -> URL {
    let url = URL(fileURLWithPath: path, isDirectory: true)
    try? FileManager.default.removeItem(at: url)
    do { try FileProtector.library.ensureDirectory(url) } catch { fail("cannot create \(path): \(error)") }
    return url
}

let command = CommandLine.arguments.dropFirst().first ?? "help"
do {
    switch command {
    case "crash-child":
        guard let mode = CrashDrill.Mode(rawValue: require("--mode")),
              let start = Int(require("--start")), let count = Int(require("--count")) else { fail("bad crash-child arguments") }
        try CrashDrill.runChild(root: URL(fileURLWithPath: require("--root")), start: start, count: count, mode: mode,
                                durability: policy())

    case "crash-drill":
        let root = freshDirectory(require("--root"))
        guard let iterations = Int(require("--iterations")),
              let seed = UInt64(argument("--seed", default: "20261006")!) else { fail("bad crash-drill arguments") }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        var drill = CrashDrillParent(executable: executable, root: root, iterations: iterations, seed: seed, durability: policy())
        drill.log = { print($0); fflush(stdout) }
        print("crash drill: environment host (macOS), seed \(seed), \(iterations) iterations, \(drill.itemsPerChild) items per child")
        let start = Date()
        let report = try drill.run()
        print(report)
        print(String(format: "elapsed: %.1f s", Date().timeIntervalSince(start)))
        print(report.failures.isEmpty ? "RESULT: PASS" : "RESULT: FAIL")
        exit(report.failures.isEmpty ? 0 : 1)

    case "restore-crash-child":
        try RestoreCrashDrill.runChild(root: URL(fileURLWithPath: require("--root")), bundle: URL(fileURLWithPath: require("--bundle")))

    case "restore-crash-drill":
        let root = freshDirectory(require("--root"))
        guard let iterations = Int(require("--iterations")),
              let seed = UInt64(argument("--seed", default: "20261007")!) else { fail("bad restore-crash-drill arguments") }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        var drill = RestoreCrashDrillParent(executable: executable, workDirectory: root, iterations: iterations, seed: seed)
        drill.log = { print($0); fflush(stdout) }
        print("restore crash drill (T47): environment host (macOS), seed \(seed), \(iterations) iterations, SIGKILL during prepare and during the swap")
        let start = Date()
        let report = try drill.run()
        print(report)
        print(String(format: "elapsed: %.1f s", Date().timeIntervalSince(start)))
        print(report.failures.isEmpty ? "RESULT: PASS" : "RESULT: FAIL")
        exit(report.failures.isEmpty ? 0 : 1)

    case "migration-crash-child":
        guard let fault = MigrationCrashDrill.Fault(rawValue: require("--fault")),
              let pauseMs = UInt32(argument("--pause-ms", default: "300")!) else { fail("bad migration-crash-child arguments") }
        let pause = require("--pause-after")
        let pauseAfter = pause == "none" ? nil : PutBackStep(rawValue: pause)
        if pause != "none" && pauseAfter == nil { fail("unknown step \(pause)") }
        try MigrationCrashDrill.runChild(root: URL(fileURLWithPath: require("--root")), fault: fault,
                                         pauseAfter: pauseAfter, pauseMs: pauseMs)

    case "migration-crash-drill":
        let root = freshDirectory(require("--root"))
        guard let iterations = Int(require("--iterations")),
              let seed = UInt64(argument("--seed", default: "20261008")!) else { fail("bad migration-crash-drill arguments") }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        var drill = MigrationCrashDrillParent(executable: executable, workDirectory: root, iterations: iterations, seed: seed)
        drill.log = { print($0); fflush(stdout) }
        print("migration put-back crash drill (T45): environment host (macOS), seed \(seed), \(iterations) iterations, "
              + "SIGKILL at each put-back step (paused there, or 0-3 ms after it) and at random times, faults: throw and drop rows")
        let start = Date()
        let report = try drill.run()
        print(report)
        print(String(format: "elapsed: %.1f s", Date().timeIntervalSince(start)))
        print(report.failures.isEmpty ? "RESULT: PASS" : "RESULT: FAIL")
        exit(report.failures.isEmpty ? 0 : 1)

    case "latency":
        let root = freshDirectory(require("--root"))
        let iterations = Int(argument("--iterations", default: "2000")!) ?? 2000
        print("capture save latency: environment host (macOS); budget p95 <= 200 ms (plan 19.2); indicative only")
        var chosen: LatencyBench.Result?
        for (name, durability) in [("chosen", DurabilityPolicy.acknowledgedSaves),
                                   ("full-no-fullfsync", DurabilityPolicy(synchronous: .full, fullfsync: false)),
                                   ("grdb-default", DurabilityPolicy.grdbDefault)] {
            let result = try LatencyBench.run(root: root.appending(path: name, directoryHint: .isDirectory),
                                              durability: durability, iterations: iterations)
            print("\(name): \(result)")
            if name == "chosen" { chosen = result }
        }
        guard let chosen else { fail("no result") }
        let pass = chosen.p95Ms <= 200
        print(pass ? "RESULT: PASS (chosen p95 \(chosen.p95Ms) ms <= 200 ms)" : "RESULT: FAIL (chosen p95 \(chosen.p95Ms) ms > 200 ms)")
        exit(pass ? 0 : 1)

    case "restore-drill":
        let root = freshDirectory(require("--root"))
        print("restore drill (T35, J-06): environment host (macOS)")
        let report = try RestoreDrill.run(workDirectory: root, log: { print($0) })
        print(report)
        print(report.failures.isEmpty ? "RESULT: PASS (\(report.checks.count) checks)" : "RESULT: FAIL (\(report.failures.count) of \(report.checks.count))")
        exit(report.failures.isEmpty ? 0 : 1)

    case "make-v1-fixture":
        let out = URL(fileURLWithPath: require("--out"))
        let work = FileManager.default.temporaryDirectory.appending(path: "g05-v1-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: work) }
        var options = StoreOptions()
        options.migrateUpTo = "v1-initial"
        options.clock = .stepping(from: 1_790_000_000_000)
        let store = try LibraryStore.open(LibraryLayout(root: work.appending(path: "Install", directoryHint: .isDirectory)), options: options)
        _ = try GoldenCorpus.build(in: store, sourceDirectory: work.appending(path: "Source", directoryHint: .isDirectory))
        try? FileManager.default.removeItem(at: out)
        try Snapshot.take(from: store.pool, to: out, staging: out.deletingLastPathComponent(), protector: store.protector)
        try store.close()
        let counts = try RecoveryAccess.openReadOnly(out).read { try LibraryChecks.counts($0) }
        print("wrote v1 fixture \(out.lastPathComponent): \(counts.values.reduce(0, +)) rows")

    case "protection-probe":
        // Reports what the platform says about protection classes under a directory.
        let base = URL(fileURLWithPath: require("--dir"), isDirectory: true)
        let probe = base.appending(path: "protection-probe-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: probe) }
        let reader = FileProtector.library
        func describe(_ url: URL) -> String { ((try? reader.protectionClass(of: url)) ?? nil)?.rawValue ?? "none reported" }
        try FileManager.default.createDirectory(at: probe, withIntermediateDirectories: true)
        print("base \(base.path): \(describe(base))")
        print("plain directory: \(describe(probe))")
        let classC = probe.appending(path: "classC", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: classC, withIntermediateDirectories: false,
                                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        print("directory created with class C: \(describe(classC))")
        let file = classC.appending(path: "file.bin")
        try Data("x".utf8).write(to: file)
        print("file created inside it: \(describe(file))")
        let plainFile = probe.appending(path: "plain.bin")
        try Data("x".utf8).write(to: plainFile, options: .completeFileProtectionUntilFirstUserAuthentication)
        print("file written with the class C option in the plain directory: \(describe(plainFile))")

    case "env-report":
        let queue = try DatabaseQueue()
        try queue.read { db in
            print("sqlite_version: \(try String.fetchOne(db, sql: "SELECT sqlite_version()") ?? "?")")
            print("sqlite_source_id: \(try String.fetchOne(db, sql: "SELECT sqlite_source_id()") ?? "?")")
            let options = try String.fetchAll(db, sql: "PRAGMA compile_options")
            print("compile_options (durability-relevant): " + options.filter {
                $0.hasPrefix("DEFAULT_SYNCHRONOUS") || $0.hasPrefix("DEFAULT_WAL_SYNCHRONOUS") || $0.hasPrefix("DEFAULT_CKPTFULLFSYNC")
                    || $0.hasPrefix("ENABLE_FTS5") || $0.hasPrefix("THREADSAFE") || $0.hasPrefix("HAS_CODEC")
            }.joined(separator: " "))
            print("connection defaults: fullfsync=\(try Int.fetchOne(db, sql: "PRAGMA fullfsync") ?? -1) "
                  + "checkpoint_fullfsync=\(try Int.fetchOne(db, sql: "PRAGMA checkpoint_fullfsync") ?? -1) "
                  + "synchronous=\(try Int.fetchOne(db, sql: "PRAGMA synchronous") ?? -1)")
        }
        let root = FileManager.default.temporaryDirectory.appending(path: "g05-env-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore.open(LibraryLayout(root: root))
        print("library open: \(store.openReport.durability)")
        print("migrations: \(store.openReport.appliedNow.joined(separator: ", "))")
        print("protection before explicit set: \(store.openReport.protectionBeforeExplicitSet.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
        try store.close()

    default:
        print("usage: g05-recovery-tool env-report | crash-drill | latency | restore-drill | restore-crash-drill | migration-crash-drill | make-v1-fixture")
        exit(command == "help" ? 0 : 2)
    }
} catch {
    fail(String(describing: error))
}
#else
print("g05-recovery-tool runs on macOS only")
#endif
