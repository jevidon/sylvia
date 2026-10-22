import Darwin
import Foundation
import os
import SylviaRecovery

/// Where the harness keeps its own files: `Application Support/G05LockHarness/` in its app container, beside the
/// library under test at `Application Support/Sylvia` (the product's location, `LibraryLayout.applicationSupport()`).
public struct HarnessPaths: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory.standardizedFileURL
    }

    /// The app container's `Application Support/G05LockHarness`, and the library layout beside it. Neither directory
    /// is created here: each file operation creates what it needs, so a launch before the first unlock records why a
    /// write failed instead of failing before it starts.
    public static func applicationSupport() -> (paths: HarnessPaths, layout: LibraryLayout) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return (HarnessPaths(directory: base.appending(path: "G05LockHarness", directoryHint: .isDirectory)),
                LibraryLayout(root: base.appending(path: "Sylvia", directoryHint: .isDirectory)))
    }

    public var log: URL { directory.appending(path: "harness.log", directoryHint: .notDirectory) }
    public var session: URL { directory.appending(path: "session.json", directoryHint: .notDirectory) }
    public var probe: URL { directory.appending(path: "probe.bin", directoryHint: .notDirectory) }
    public var canary: URL { directory.appending(path: "class-a-canary.bin", directoryHint: .notDirectory) }
}

/// The log file: class C, created with the class and read back, each append flushed with `F_FULLFSYNC` before it
/// returns, so a line in the file was on stable storage when the next attempt began.
@MainActor
public final class FileLogSink: LogSink {
    public let paths: HarnessPaths
    public let protector: FileProtector

    public init(paths: HarnessPaths, configuration: HarnessConfiguration) {
        self.paths = paths
        self.protector = FileProtector(protection: configuration.protection)
    }

    public var fileURL: URL { paths.log }

    public func append(_ lines: [String]) throws {
        guard !lines.isEmpty else { return }
        try protector.ensureDirectory(paths.directory)
        if !FileManager.default.fileExists(atPath: paths.log.path) {
            try protector.write(Data(), to: paths.log, atomic: false)
        }
        let handle = try FileHandle(forWritingTo: paths.log)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(lines.map { $0 + "\n" }.joined().utf8))
        if fcntl(handle.fileDescriptor, F_FULLFSYNC) != 0 {
            try handle.synchronize()
        }
        try protector.verify(paths.log)
    }

    public func readTail(maxLines: Int) throws -> [String] {
        guard FileManager.default.fileExists(atPath: paths.log.path) else { return [] }
        let text = String(decoding: try Data(contentsOf: paths.log), as: UTF8.self)
        return Array(text.split(separator: "\n", omittingEmptySubsequences: true).suffix(maxLines).map(String.init))
    }
}

/// The run's record, written whole (atomic rename) with class C and flushed after every attempt.
@MainActor
public final class SessionFileStore: SessionStore {
    public let paths: HarnessPaths
    public let protector: FileProtector

    public init(paths: HarnessPaths, configuration: HarnessConfiguration) {
        self.paths = paths
        self.protector = FileProtector(protection: configuration.protection)
    }

    public func load() throws -> SessionRecord? {
        guard FileManager.default.fileExists(atPath: paths.session.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(SessionRecord.self, from: Data(contentsOf: paths.session))
    }

    public func save(_ record: SessionRecord) throws {
        try protector.ensureDirectory(paths.directory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try protector.write(try encoder.encode(record), to: paths.session, atomic: true)
        try DurableFile.sync(paths.session)
        try DurableFile.syncDirectory(paths.directory)
    }
}

/// The lock detector of the old XCTest probe, kept: a class-A (`complete`) file, unreadable about 10 s after the phone
/// locks. It is the only file the harness writes with a class other than C, and that class is stronger.
@MainActor
public final class ClassACanary: CanaryProbe {
    public let paths: HarnessPaths
    public let protector = FileProtector(protection: .complete)

    public init(paths: HarnessPaths) {
        self.paths = paths
    }

    public func ensureCreated() throws -> Bool {
        if FileManager.default.fileExists(atPath: paths.canary.path) { return false }
        try FileProtector(protection: HarnessConfiguration.requiredProtection).ensureDirectory(paths.directory)
        try Data(repeating: 0x5A, count: 64).write(to: paths.canary, options: [.completeFileProtection, .withoutOverwriting])
        // The simulator reports class C for every file whatever was requested (finding F3), so the class is checked
        // on a device only; there a canary that is not class A could not detect the lock.
        #if !targetEnvironment(simulator)
        do {
            try protector.verify(paths.canary)
        } catch {
            try? FileManager.default.removeItem(at: paths.canary)
            throw error
        }
        #endif
        return true
    }

    public func isReadable() -> Bool {
        (try? Data(contentsOf: paths.canary)) != nil
    }
}

/// A class-C file rewritten and read back on every attempt (the old probe's `tick.bin`), so the harness shows plain
/// file writes as well as the database's while locked.
@MainActor
public final class ClassCFileProbe: FileProbe {
    public let paths: HarnessPaths
    public let protector: FileProtector

    public init(paths: HarnessPaths, configuration: HarnessConfiguration) {
        self.paths = paths
        self.protector = FileProtector(protection: configuration.protection)
    }

    public func writeAndRead(_ text: String) throws -> Bool {
        try protector.ensureDirectory(paths.directory)
        let bytes = Data(text.utf8)
        try protector.write(bytes, to: paths.probe, atomic: true)
        return try Data(contentsOf: paths.probe) == bytes
    }
}

/// Reads back the protection class of every file the harness and the library keep. On a device each must be class C
/// (the canary class A); in the simulator the readback is recorded but not evaluated (finding F3).
@MainActor
public final class FileProtectionInspector: ProtectionInspector {
    public let paths: HarnessPaths
    public let layout: LibraryLayout
    public let protection: FileProtectionType
    private let evaluated: Bool

    public init(paths: HarnessPaths, layout: LibraryLayout, configuration: HarnessConfiguration,
                evaluated: Bool = FileProtector.platformReportsProtection) {
        self.paths = paths
        self.layout = layout
        self.protection = configuration.protection
        self.evaluated = evaluated
    }

    public func inspect(full: Bool) -> ProtectionReport {
        var items: [(String, URL, FileProtectionType)] = [
            ("library.sqlite", layout.databaseURL, protection), ("library.sqlite-wal", layout.walURL, protection),
            ("library.sqlite-shm", layout.shmURL, protection), ("harness.log", paths.log, protection),
            ("session.json", paths.session, protection), ("probe.bin", paths.probe, protection),
        ]
        if full {
            items = [("Sylvia", layout.root, protection), ("Library", layout.libraryDirectory, protection),
                     ("installation.json", layout.installationURL, protection),
                     ("G05LockHarness", paths.directory, protection)]
                + items + [("class-a-canary.bin", paths.canary, .complete)]
        }
        let reader = FileProtector(protection: protection)
        var report: [ProtectionItem] = []
        for (name, url, expected) in items where FileManager.default.fileExists(atPath: url.path) {
            let actual: String
            do {
                actual = try reader.protectionClass(of: url)?.rawValue ?? "none reported"
            } catch {
                actual = "unreadable(\(HarnessLog.code(error)))"
            }
            report.append(ProtectionItem(name: name, expected: expected.rawValue, actual: actual, matches: actual == expected.rawValue))
        }
        return ProtectionReport(items: report, evaluated: evaluated)
    }
}

/// Every line also goes to the unified system log (subsystem `com.jevidon.sylvia.spike.g05lockharness`), at the
/// default level, which iOS keeps on disk: the record of anything that happened before the first unlock, when the
/// class-C log file cannot be written, survives even if the process ends before the first unlock. The lines hold only
/// the harness's synthetic values, so they are logged as public.
@MainActor
public final class UnifiedLogMirror: LogMirror {
    public static let subsystem = "com.jevidon.sylvia.spike.g05lockharness"
    private let logger = Logger(subsystem: UnifiedLogMirror.subsystem, category: "harness")

    public init() {}

    public func mirror(_ line: String) {
        logger.notice("\(line, privacy: .public)")
    }
}

@MainActor
public final class SystemHarnessClock: HarnessClock {
    public init() {}
    public func now() -> Date { Date() }
}

/// `kern.boottime`: the wall-clock time the device booted.
@MainActor
public final class SysctlBootTime: BootTimeSource {
    public init() {}

    public func bootTime() -> Date? {
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        var value = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctl(&mib, 2, &value, &size, nil, 0) == 0, value.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(value.tv_sec) + TimeInterval(value.tv_usec) / 1_000_000)
    }
}

public enum HarnessPlatform {
    public static var name: String {
        #if targetEnvironment(simulator)
        return "simulator"
        #else
        return "device"
        #endif
    }
}
