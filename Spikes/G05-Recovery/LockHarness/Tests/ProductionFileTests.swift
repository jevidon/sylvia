import Foundation
import GRDB
import SylviaRecovery
import Testing

/// The production components against real files in a temporary directory of the simulator. They show that the
/// library, the log, the record, the probe and the canary work as the harness uses them. They cannot show protection:
/// the simulator's readback is not faithful (G0.5 recovery finding F3), so the inspector records it unevaluated here.
@MainActor
@Suite("Lock harness: production files on the simulator (protection not evaluated)")
struct ProductionFileTests {
    final class Root {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "g05-lock-harness-tests/\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
        var paths: HarnessPaths { HarnessPaths(directory: url.appending(path: "G05LockHarness", directoryHint: .isDirectory)) }
        var layout: LibraryLayout { LibraryLayout(root: url.appending(path: "Sylvia", directoryHint: .isDirectory)) }
        deinit { try? FileManager.default.removeItem(at: url) }
    }

    @Test("the spike's library: saved, read back exactly, already-saved on a retry, verified, D17's durability read back")
    func library() throws {
        let root = Root()
        let configuration = try HarnessConfiguration()
        let store = LibraryHarnessStore(layout: root.layout, configuration: configuration)
        #expect(store.protector.protection == .completeUntilFirstUserAuthentication)
        #expect(try store.open() == "journal_mode=wal synchronous=FULL fullfsync=1 checkpoint_fullfsync=1")
        for item in 0..<5 {
            #expect(try store.save(item: item) == .saved)
            #expect(try store.readBack(item: item) == .equal)
        }
        #expect(try store.save(item: 2) == .alreadySaved)
        #expect(try store.readBack(item: 7) == .missing)
        let report = try store.verify(acknowledged: 5)
        #expect(report.passed)
        #expect(report.libraryCaptures == 5)
        let short = try store.verify(acknowledged: 6)
        #expect(!short.passed)
        #expect(short.failures.contains { $0.contains("acknowledged but missing: [5]") })
        store.close()
        #expect(!store.isOpen)
        #expect(throws: HarnessError.storeNotOpen) { try store.save(item: 5) }
        _ = try store.open()
        #expect(try store.verify(acknowledged: 5).passed, "every acknowledged item is there after a reopen")
        store.close()
    }

    @Test("the read-back is byte for byte: a stored quotation that differs only in Unicode composition is not equal")
    func readBackIsByteExact() throws {
        let root = Root()
        let store = LibraryHarnessStore(layout: root.layout, configuration: try HarnessConfiguration())
        _ = try store.open()
        _ = try store.save(item: 0)
        #expect(try store.readBack(item: 0) == .equal)
        let composed = CrashDrill.quote(0).precomposedStringWithCanonicalMapping
        #expect(composed == CrashDrill.quote(0), "Swift's String equality takes the two as equal")
        #expect(Array(composed.utf8) != Array(CrashDrill.quote(0).utf8), "their bytes differ")
        let other = try DatabaseQueue(path: root.layout.databaseURL.path)
        try other.write { db in
            try db.execute(sql: "UPDATE capture SET quoted_text = ? WHERE idempotency_key = ?", arguments: [composed, CrashDrill.key(0)])
        }
        try other.close()
        #expect(try store.readBack(item: 0) == .differs)
        store.close()
    }

    @Test("a library that exists but cannot be opened is reported, and nothing is created in its place")
    func damagedLibraryIsNotReplaced() throws {
        let root = Root()
        let configuration = try HarnessConfiguration()
        let store = LibraryHarnessStore(layout: root.layout, configuration: configuration)
        _ = try store.open()
        _ = try store.save(item: 0)
        store.close()
        // The database is gone from an installation that had one: the spike refuses to create an empty one.
        for url in [root.layout.databaseURL, root.layout.walURL, root.layout.shmURL] {
            try? FileManager.default.removeItem(at: url)
        }
        #expect(throws: (any Error).self) { try store.open() }
        #expect(!FileManager.default.fileExists(atPath: root.layout.databaseURL.path))
    }

    @Test("the log file: lines appended whole and flushed, the tail read back; the record round-trips; the probe and the canary")
    func files() throws {
        let root = Root()
        let configuration = try HarnessConfiguration()
        let sink = FileLogSink(paths: root.paths, configuration: configuration)
        try sink.append(["first line", "second line"])
        try sink.append(["third line"])
        #expect(try sink.readTail(maxLines: 2) == ["second line", "third line"])
        #expect(try String(contentsOf: sink.fileURL, encoding: .utf8) == "first line\nsecond line\nthird line\n")

        let sessions = SessionFileStore(paths: root.paths, configuration: configuration)
        #expect(try sessions.load() == nil)
        var record = SessionRecord(run: "abcd1234", bootTime: Date(timeIntervalSince1970: 1_792_573_200),
                                   startedAt: Date(timeIntervalSince1970: 1_792_659_600), interval: 2, acknowledged: 7)
        record.attempts = 3
        record.lastRecordAt = Date(timeIntervalSince1970: 1_792_659_606.5)
        try sessions.save(record)
        #expect(try sessions.load() == record)

        let probe = ClassCFileProbe(paths: root.paths, configuration: configuration)
        #expect(try probe.writeAndRead("attempt 1"))
        #expect(try probe.writeAndRead("attempt 2"))

        let canary = ClassACanary(paths: root.paths)
        #expect(canary.state() == .absent, "no canary before the first Start: absent, not unreadable (review H-04)")
        #expect(try canary.ensureCreated())
        #expect(try !canary.ensureCreated(), "made once")
        #expect(canary.state() == .readable, "the simulator never locks")
    }

    @Test("every production component asks for class C, from the configuration; only the canary asks for class A")
    func classes() throws {
        let root = Root()
        let configuration = try HarnessConfiguration()
        let classC = FileProtectionType.completeUntilFirstUserAuthentication
        #expect(LibraryHarnessStore(layout: root.layout, configuration: configuration).protector.protection == classC)
        #expect(FileLogSink(paths: root.paths, configuration: configuration).protector.protection == classC)
        #expect(SessionFileStore(paths: root.paths, configuration: configuration).protector.protection == classC)
        #expect(ClassCFileProbe(paths: root.paths, configuration: configuration).protector.protection == classC)
        #expect(FileProtectionInspector(paths: root.paths, layout: root.layout, configuration: configuration).protection == classC)
        #expect(ClassACanary(paths: root.paths).protector.protection == .complete)
    }

    @Test("the inspector reads every class; in the simulator it records them without evaluating them")
    func inspector() throws {
        let root = Root()
        let configuration = try HarnessConfiguration()
        let store = LibraryHarnessStore(layout: root.layout, configuration: configuration)
        _ = try store.open()
        _ = try store.save(item: 0)
        try FileLogSink(paths: root.paths, configuration: configuration).append(["line"])
        _ = try ClassACanary(paths: root.paths).ensureCreated()
        let inspector = FileProtectionInspector(paths: root.paths, layout: root.layout, configuration: configuration)
        let tick = inspector.inspect(full: false)
        #expect(!tick.evaluated)
        #expect(tick.compact == "simulator-unverified")
        #expect(tick.mismatches.isEmpty)
        #expect(Set(tick.items.map(\.name)).isSuperset(of: ["library.sqlite", "library.sqlite-wal", "harness.log"]))
        let full = inspector.inspect(full: true)
        #expect(Set(full.items.map(\.name)).isSuperset(of: ["Sylvia", "Library", "installation.json", "G05LockHarness",
                                                             "library.sqlite", "class-a-canary.bin"]))
        #expect(full.items.first { $0.name == "class-a-canary.bin" }?.expected == FileProtectionType.complete.rawValue)
        let evaluated = FileProtectionInspector(paths: root.paths, layout: root.layout, configuration: configuration, evaluated: true)
        #expect(evaluated.inspect(full: true).compact.hasPrefix("differs:"),
                "were the simulator's readback evaluated, its directories (none reported) would fail it")
        store.close()
    }

    @Test("a whole run on real files: start, attempts, stop; the next launch reads stopped-cleanly and verifies the library")
    func wholeRunOnRealFiles() throws {
        let root = Root()
        let configuration = try HarnessConfiguration()
        let device = SimulatedDevice()
        let mirror = FakeMirror()
        func environment() -> HarnessEnvironment {
            HarnessEnvironment(
                clock: device, protectedData: device, bootTime: device, appState: device, player: FakePlayer(),
                store: LibraryHarnessStore(layout: root.layout, configuration: configuration),
                sink: FileLogSink(paths: root.paths, configuration: configuration), mirror: mirror,
                sessions: SessionFileStore(paths: root.paths, configuration: configuration),
                canary: ClassACanary(paths: root.paths), probe: ClassCFileProbe(paths: root.paths, configuration: configuration),
                inspector: FileProtectionInspector(paths: root.paths, layout: root.layout, configuration: configuration),
                scheduler: FakeScheduler(), platform: "simulator")
        }
        let first = HarnessController(configuration: configuration, environment: environment(), autoTick: false)
        first.launch()
        first.start()
        for _ in 0..<6 {
            device.advance(2)
            first.tick()
        }
        device.advance(1)
        first.stop()

        device.advance(60)
        let second = HarnessController(configuration: configuration, environment: environment(), autoTick: false)
        second.launch()
        let lines = try String(contentsOf: root.paths.log, encoding: .utf8).split(separator: "\n").map { HarnessLog.fields(of: String($0)) }
        let attempts = lines.filter { $0["event"] == "attempt" }
        #expect(attempts.count == 6)
        #expect(attempts.allSatisfy { $0["save"] == "saved" && $0["readback"] == "equal" && $0["file"] == "ok"
            && $0["classes"] == "simulator-unverified" && $0["session"] == "ok" })
        #expect(lines.last { $0["event"] == "previous-session" }?["result"] == "stopped-cleanly")
        let verify = try #require(lines.last { $0["event"] == "verify" })
        #expect(verify["result"] == "ok")
        #expect(verify["acknowledged"] == "6")
        #expect(verify["libraryCaptures"] == "6")
        #expect(second.recentLines.count == lines.count, "the screen shows the file's lines after a launch")
        #expect(mirror.lines.count == lines.count)
    }

    @Test("the boot time is a moment in the past")
    func bootTime() throws {
        let boot = try #require(SysctlBootTime().bootTime())
        #expect(boot < Date())
        #expect(boot > Date(timeIntervalSince1970: 1_577_836_800))
    }
}
