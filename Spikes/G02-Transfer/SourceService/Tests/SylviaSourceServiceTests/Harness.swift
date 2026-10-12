import CryptoKit
import Foundation
import Synchronization
import Testing
@_spi(Testing) import SylviaSourceService
@_spi(Testing) import SylviaTransferClient
import SylviaTransferCore

/// Approver whose answer each test scripts. Records every request it is asked about.
final class ScriptedApprover: PairingApprover {
    enum Answer: Sendable {
        case approve
        case deny
        case never
        case wait(Duration, Bool)
        /// Answers after the delay and ignores cancellation, like a prompt nobody is looking at.
        case uncancellable(seconds: Double, Bool)
    }

    let answer: Mutex<Answer>
    let asked = Mutex<[PairingApprovalRequest]>([])

    init(_ answer: Answer = .approve) { self.answer = Mutex(answer) }

    func approve(_ request: PairingApprovalRequest) async -> Bool {
        asked.withLock { $0.append(request) }
        switch answer.withLock({ $0 }) {
        case .approve: return true
        case .deny: return false
        case .never:
            try? await Task.sleep(for: .seconds(3600))
            return false
        case .wait(let duration, let result):
            try? await Task.sleep(for: duration)
            return result
        case .uncancellable(let seconds, let result):
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { continuation.resume() }
            }
            return result
        }
    }

    var askedCount: Int { asked.withLock { $0.count } }
}

/// A clock tests can move.
final class TestClock: Sendable {
    private let current = Mutex(Date())
    var now: @Sendable () -> Date { { [self] in current.withLock { $0 } } }
    func advance(_ seconds: TimeInterval) { current.withLock { $0 = $0.addingTimeInterval(seconds) } }
}

/// A running source over temporary folders, with a source root and a state directory.
struct Harness {
    let root: URL
    let state: URL
    let identityStore: EphemeralIdentityStore
    let approver: ScriptedApprover
    let faults: FaultPlan
    let clock: TestClock
    var service: SourceService

    static let mib = 1_048_576

    static func make(
        files: [String: [UInt8]] = [:], approver: ScriptedApprover = ScriptedApprover(), partSize: Int64 = TransferProtocol.mebibyte,
        limits: PairingAuthority.Limits = PairingAuthority.Limits(), identityStore: EphemeralIdentityStore = EphemeralIdentityStore(),
        port: Int = 0, root existingRoot: URL? = nil, state existingState: URL? = nil, clock: TestClock = TestClock(),
        sourceName: String = "Test Mac", advertiseBonjour: Bool = false, idleTimeout: Duration = .seconds(60),
        preparationResponseLimit: Duration = .seconds(10)
    ) async throws -> Harness {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("g02-\(UUID().uuidString)")
        let root = existingRoot ?? base.appendingPathComponent("library")
        let state = existingState ?? base.appendingPathComponent("state")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (path, bytes) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(bytes).write(to: url)
        }
        var configuration = SourceServiceConfiguration(roots: [root], stateDirectory: state)
        configuration.port = port
        configuration.sourceName = sourceName
        configuration.advertiseBonjour = advertiseBonjour
        configuration.idleTimeout = idleTimeout
        configuration.preparationResponseLimit = preparationResponseLimit
        configuration.partSizes = .init(defaultBytes: partSize, minimumBytes: TransferProtocol.minimumPartSize, maximumBytes: TransferProtocol.maximumPartSize)
        configuration.pairingLimits = limits
        configuration.now = clock.now
        let faults = FaultPlan()
        let service = try await SourceService.start(
            configuration: configuration, identityStore: identityStore, approver: approver, faults: faults)
        return Harness(root: root, state: state, identityStore: identityStore, approver: approver, faults: faults, clock: clock, service: service)
    }

    /// Restarts the service on the same port, state and identity store (a Mac app relaunch).
    func restarted(identityStore: EphemeralIdentityStore? = nil) async throws -> Harness {
        await service.stop()
        return try await Harness.make(
            approver: approver, partSize: service.configuration.partSizes.defaultBytes, limits: service.configuration.pairingLimits,
            identityStore: identityStore ?? self.identityStore, port: service.port, root: root, state: state, clock: clock)
    }

    var baseURL: URL { URL(string: "https://127.0.0.1:\(service.port)")! }

    func unauthenticatedClient(pin: SPKIPin? = nil) -> SourceClient {
        SourceClient(baseURL: baseURL, pin: pin ?? service.pin, sourceID: service.sourceID, token: nil)
    }

    func client(token: String) -> SourceClient {
        SourceClient(baseURL: baseURL, pin: service.pin, sourceID: service.sourceID, token: token)
    }

    /// Pairs a new device and returns its client and identity.
    func pairDevice(name: String = "Test iPhone") async throws -> (client: SourceClient, paired: PairedSource, token: String) {
        let payload = await service.issueInvitation()
        let (paired, token) = try await SourceClient.pair(payload: payload, deviceID: CanonicalID.make(), deviceName: name, now: clock.now())
        return (client(token: token), paired, token)
    }

    func itemID(titled title: String) async throws -> String {
        let page = try await service.library.catalog(after: nil, limit: 200)
        return try #require(page.items.first { $0.title == title }?.itemID)
    }

    func cleanUp() async {
        await service.stop()
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    static func bytes(seed: UInt8, count: Int) -> [UInt8] {
        // Deterministic, non-repeating within a part: SHA-256 counter stream.
        var out = [UInt8]()
        out.reserveCapacity(count + 32)
        var counter: UInt64 = 0
        while out.count < count {
            var input = [seed]
            withUnsafeBytes(of: counter.littleEndian) { input.append(contentsOf: $0) }
            out.append(contentsOf: SHA256.hash(data: input))
            counter += 1
        }
        return Array(out.prefix(count))
    }
}

/// A small APFS volume (an `hdiutil` disk image attached without Finder), for tests that need a disk that
/// really fills up (ENOSPC from the file system, not a simulated error).
struct DiskImage {
    let base: URL
    let mountPoint: URL

    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    init(megabytes: Int) throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("g02-volume-\(UUID().uuidString)", isDirectory: true)
        mountPoint = base.appendingPathComponent("mnt", isDirectory: true)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        let image = base.appendingPathComponent("volume.dmg").path
        try Self.hdiutil(["create", "-size", "\(megabytes)m", "-fs", "APFS", "-volname", "G02Full", "-type", "UDIF", image])
        try Self.hdiutil(["attach", "-nobrowse", "-mountpoint", mountPoint.path, image])
    }

    func detach() {
        _ = try? Self.hdiutil(["detach", "-force", mountPoint.path])
        try? FileManager.default.removeItem(at: base)
    }

    /// Bytes the file system reports free to this user.
    var availableBytes: Int64 {
        var stats = statfs()
        guard statfs(mountPoint.path, &stats) == 0 else { return -1 }
        return Int64(stats.f_bavail) * Int64(stats.f_bsize)
    }

    /// Writes zeros until at most `leaving` bytes are free (each chunk synced, so the count is current).
    func fill(leaving: Int64) throws -> URL {
        let url = mountPoint.appendingPathComponent("filler.bin")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        while availableBytes > leaving {
            let excess = availableBytes - leaving
            let chunk = Int(min(excess, excess > 2 * 1_048_576 ? 1_048_576 : 65_536))
            try handle.write(contentsOf: Data(count: max(4_096, chunk)))
            try handle.synchronize()
        }
        return url
    }

    @discardableResult
    static func hdiutil(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw Failure(description: "hdiutil \(arguments.first ?? "") failed (\(process.terminationStatus)): \(text)")
        }
        return text
    }
}

/// Collects transfer events for assertions.
final class EventLog: Sendable {
    let events = Mutex<[TransferEngine.Event]>([])
    func record(_ event: TransferEngine.Event) { events.withLock { $0.append(event) } }
    var all: [TransferEngine.Event] { events.withLock { $0 } }
    func count(where predicate: (TransferEngine.Event) -> Bool) -> Int { all.filter(predicate).count }
}

/// Evidence output for the CI drop-in: Docs/Stage0/evidence/G02-Transfer/<name>.
enum Evidence {
    static let directory: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("Docs/Stage0/evidence/G02-Transfer")
    }()

    static func write(_ name: String, _ text: String) {
        let url = directory.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: url)
    }

    static func appendLine(_ name: String, _ line: String) {
        let url = directory.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data((line + "\n").utf8))
            try? handle.close()
        } else {
            try? Data((line + "\n").utf8).write(to: url)
        }
    }
}
