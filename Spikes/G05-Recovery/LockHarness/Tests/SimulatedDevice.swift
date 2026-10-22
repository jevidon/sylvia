import Darwin
import Foundation

/// A phone as the harness sees it, for the simulator, which cannot lock: its lock state decides which data-protection
/// classes are available, and its clock and boot time are set by the test.
///
/// * unlocked: classes A and C available, `isProtectedDataAvailable` true;
/// * locked after the first unlock: class A unavailable (the canary unreadable), class C available,
///   `isProtectedDataAvailable` false;
/// * before the first unlock after a restart: classes A and C unavailable, `isProtectedDataAvailable` false.
///
/// A class-C operation in the third state throws what iOS reports for a file whose class key is not available
/// (`NSFileWriteNoPermissionError` over `EPERM`, as the host showed for a closed class-B file while locked, errno 1).
@MainActor
final class SimulatedDevice: HarnessClock, ProtectedDataSource, BootTimeSource, AppStateSource {
    enum Lock {
        case unlocked, lockedAfterFirstUnlock, beforeFirstUnlock
    }

    var lock: Lock = .unlocked
    /// 2026-10-22T09:00:00Z, booted a day earlier.
    var current = Date(timeIntervalSince1970: 1_792_659_600)
    var boot: Date? = Date(timeIntervalSince1970: 1_792_659_600 - 86_400)
    var stateName = "active"

    var isProtectedDataAvailable: Bool { lock == .unlocked }
    var classCAvailable: Bool { lock != .beforeFirstUnlock }
    var classAAvailable: Bool { lock == .unlocked }

    func now() -> Date { current }
    func bootTime() -> Date? { boot }
    func advance(_ seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }

    /// Powers off now and boots `offFor` seconds later; the phone then stays before its first unlock.
    func restart(offFor seconds: TimeInterval = 40) {
        advance(seconds)
        boot = current
        advance(20)
        lock = .beforeFirstUnlock
        stateName = "background"
    }

    static var classKeyUnavailable: NSError {
        NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError,
                userInfo: [NSLocalizedDescriptionKey: "You don't have permission to save the file 'harness.log' in the folder 'G05LockHarness'.",
                           NSFilePathErrorKey: "/private/var/mobile/Containers/Data/Application/0000/Library/Application Support/G05LockHarness/harness.log",
                           NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])
    }

    func requireClassC() throws {
        if !classCAvailable { throw Self.classKeyUnavailable }
    }
}

/// The library: what was committed survives a restart; the open connection does not.
@MainActor
final class FakeStore: HarnessStore {
    let device: SimulatedDevice
    /// Committed items and whether each holds its exact content.
    var committed: [Int: Bool] = [:]
    var isOpen = false
    var opens = 0
    var openAttempts = 0
    /// Items whose stored content does not read back as written.
    var corrupt: Set<Int> = []
    /// The next read-backs throw (after their save committed).
    var readBackFailuresLeft = 0
    /// The library itself is damaged: verify reports it.
    var integrity = ["ok"]

    init(device: SimulatedDevice) { self.device = device }

    func open() throws -> String {
        openAttempts += 1
        try device.requireClassC()
        opens += 1
        isOpen = true
        return "journal_mode=wal synchronous=FULL fullfsync=1 checkpoint_fullfsync=1"
    }

    func close() { isOpen = false }

    func save(item: Int) throws -> SaveResult {
        guard isOpen else { throw HarnessError.storeNotOpen }
        try device.requireClassC()
        if committed[item] != nil { return .alreadySaved }
        committed[item] = !corrupt.contains(item)
        return .saved
    }

    func readBack(item: Int) throws -> ReadBack {
        guard isOpen else { throw HarnessError.storeNotOpen }
        try device.requireClassC()
        if readBackFailuresLeft > 0 {
            readBackFailuresLeft -= 1
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EIO))
        }
        guard let exact = committed[item] else { return .missing }
        return exact ? .equal : .differs
    }

    func verify(acknowledged: Int) throws -> VerifyReport {
        guard isOpen else { throw HarnessError.storeNotOpen }
        try device.requireClassC()
        let failures = (0..<acknowledged).filter { committed[$0] != true }.map { "item \($0) missing or not exact" }
        return VerifyReport(acknowledged: acknowledged, libraryCaptures: committed.count, integrity: integrity,
                            foreignKeyViolations: 0, failures: failures)
    }
}

@MainActor
final class FakeSink: LogSink {
    let device: SimulatedDevice
    var lines: [String] = []
    var appendCalls = 0
    let fileURL = URL(filePath: "/simulated/G05LockHarness/harness.log")

    init(device: SimulatedDevice) { self.device = device }

    func append(_ new: [String]) throws {
        appendCalls += 1
        try device.requireClassC()
        lines += new
    }

    func readTail(maxLines: Int) throws -> [String] {
        try device.requireClassC()
        return Array(lines.suffix(maxLines))
    }
}

@MainActor
final class FakeMirror: LogMirror {
    var lines: [String] = []
    func mirror(_ line: String) { lines.append(line) }
}

@MainActor
final class FakeSessions: SessionStore {
    let device: SimulatedDevice
    var stored: SessionRecord?
    var saves = 0

    init(device: SimulatedDevice) { self.device = device }

    func load() throws -> SessionRecord? {
        try device.requireClassC()
        return stored
    }

    func save(_ record: SessionRecord) throws {
        try device.requireClassC()
        saves += 1
        stored = record
    }
}

@MainActor
final class FakeCanary: CanaryProbe {
    let device: SimulatedDevice
    var exists = false

    init(device: SimulatedDevice) { self.device = device }

    func ensureCreated() throws -> Bool {
        if exists { return false }
        if !device.classAAvailable { throw SimulatedDevice.classKeyUnavailable }
        exists = true
        return true
    }

    func isReadable() -> Bool { exists && device.classAAvailable }
}

@MainActor
final class FakeProbe: FileProbe {
    let device: SimulatedDevice
    var writes = 0

    init(device: SimulatedDevice) { self.device = device }

    func writeAndRead(_ text: String) throws -> Bool {
        try device.requireClassC()
        writes += 1
        return true
    }
}

@MainActor
final class FakeInspector: ProtectionInspector {
    /// A file that reads back another class (a device would show it; the controller must only record it).
    var mismatch: ProtectionItem?
    var inspections: [Bool] = []

    func inspect(full: Bool) -> ProtectionReport {
        inspections.append(full)
        var items = [ProtectionItem(name: "library.sqlite", expected: HarnessConfiguration.requiredProtection.rawValue,
                                    actual: HarnessConfiguration.requiredProtection.rawValue, matches: true)]
        if let mismatch { items.append(mismatch) }
        return ProtectionReport(items: items, evaluated: true)
    }
}

@MainActor
final class FakePlayer: KeepAlivePlayer {
    var onEvent: (@MainActor (String) -> Void)?
    var isPlaying = false
    var startedVolumes: [Float] = []
    var stops = 0
    var startError: (any Error)?

    func start(volume: Float) throws {
        if let startError { throw startError }
        startedVolumes.append(volume)
        isPlaying = true
    }

    func stop() {
        stops += 1
        isPlaying = false
    }
}

@MainActor
final class FakeScheduler: RefreshScheduler {
    var calls = 0
    func schedule() -> String {
        calls += 1
        return "scheduled-earliest-in-60s"
    }
}

/// One installation: the files persist across processes; a restart or a kill ends the process.
@MainActor
final class Rig {
    let device = SimulatedDevice()
    lazy var store = FakeStore(device: device)
    lazy var sink = FakeSink(device: device)
    let mirror = FakeMirror()
    lazy var sessions = FakeSessions(device: device)
    lazy var canary = FakeCanary(device: device)
    lazy var probe = FakeProbe(device: device)
    let inspector = FakeInspector()
    let player = FakePlayer()
    let scheduler = FakeScheduler()

    var environment: HarnessEnvironment {
        HarnessEnvironment(clock: device, protectedData: device, bootTime: device, appState: device, player: player,
                           store: store, sink: sink, mirror: mirror, sessions: sessions, canary: canary, probe: probe,
                           inspector: inspector, scheduler: scheduler, platform: "simulated-device")
    }

    /// A new process: what was in memory is gone, the files are not.
    func newProcess(environment variables: [String: String] = [:]) throws -> HarnessController {
        store.isOpen = false
        player.isPlaying = false
        return HarnessController(configuration: try HarnessConfiguration(environment: variables), environment: environment,
                                 autoTick: false)
    }

    /// Lines of the log file with this event, parsed.
    func fileLines(_ event: String) -> [[String: String]] {
        sink.lines.map(HarnessLog.fields(of:)).filter { $0["event"] == event }
    }

    func mirrorLines(_ event: String) -> [[String: String]] {
        mirror.lines.map(HarnessLog.fields(of:)).filter { $0["event"] == event }
    }

    /// `count` attempts, `interval` seconds apart.
    func ticks(_ controller: HarnessController, _ count: Int, interval: TimeInterval = 2) {
        for _ in 0..<count {
            device.advance(interval)
            controller.tick()
        }
    }
}
