import Foundation
import GRDB
import Testing
@testable import SylviaRecovery

/// T50 reboot probe, run by a person on a physical iPhone (device checklist
/// Docs/Stage0/device-checklists/G05-Recovery.md, step 4). Every other test builds its library in a
/// temporary directory that is deleted when the test ends; this one writes a library that stays.
///
/// Disabled unless `SYLVIA_DEVICE_PERSIST_PROBE` reaches the test runner (pass
/// `TEST_RUNNER_SYLVIA_DEVICE_PERSIST_PROBE=<mode>` to xcodebuild):
/// * `write`: replaces `Application Support/Sylvia` in the test runner's container
///   (`LibraryLayout.applicationSupport()`) with a class-C library holding 20 captures, a class-C
///   canary file and a class-C record of what was written, and leaves them there;
/// * `verify`: after the reboot and the first unlock, checks that the library, its journal, the device
///   identity and the canary are intact and still carry class C;
/// * `clean`: removes them.
/// Never enabled on macOS, where Application Support is the user's own. On the simulator it can be run
/// to check the probe itself, which is not evidence of protection (the readback is not faithful).
@Suite("Device persistence probe (T50 reboot, physical device only)")
struct DevicePersistenceProbeTests {
    static var mode: String? {
        #if os(macOS)
        return nil
        #else
        return ProcessInfo.processInfo.environment["SYLVIA_DEVICE_PERSIST_PROBE"]
        #endif
    }

    struct Expected: Codable {
        var device_id: String
        var knowledge_sha256: String
        var captures: Int
        var journal_entries: Int
        var canary_sha256: String
        var written_at_ms: Int64
    }

    static let captureCount = 20

    func files(_ layout: LibraryLayout) -> (canary: URL, expected: URL) {
        (layout.root.appending(path: "t50-canary.bin", directoryHint: .notDirectory),
         layout.root.appending(path: "t50-expected.json", directoryHint: .notDirectory))
    }

    /// Reads back the class of every item the probe checks; on a device each must be class C.
    func protection(_ layout: LibraryLayout, extra: [URL]) throws -> [String] {
        var out: [String] = []
        let fm = FileManager.default
        for url in [layout.root, layout.libraryDirectory, layout.databaseURL, layout.walURL, layout.shmURL, layout.installationURL] + extra
        where fm.fileExists(atPath: url.path) {
            let value = (try FileProtector.library.protectionClass(of: url))?.rawValue ?? "none reported"
            out.append("\(url.lastPathComponent)=\(value)")
            if FileProtector.platformReportsProtection {
                #expect(value == FileProtectionType.completeUntilFirstUserAuthentication.rawValue, "\(url.lastPathComponent): \(value)")
            }
        }
        return out
    }

    @Test("write, verify or clean the persistent class-C library used by device checklist step 4",
          .enabled(if: DevicePersistenceProbeTests.mode != nil,
                   "needs a physical device and SYLVIA_DEVICE_PERSIST_PROBE=write|verify|clean (device checklist step 4)"))
    func persistentLibrary() throws {
        let mode = try #require(Self.mode)
        let layout = try LibraryLayout.applicationSupport()
        let (canary, expectedURL) = files(layout)
        let fm = FileManager.default
        switch mode {
        case "write":
            if fm.fileExists(atPath: layout.root.path) { try fm.removeItem(at: layout.root) }
            try CrashDrill.seed(layout, durability: .acknowledgedSaves)
            let store = try LibraryStore.open(layout)
            for n in 0..<Self.captureCount { try store.saveCapture(CrashDrill.command(n)) }
            let (dump, journal) = try store.pool.read { db in
                (try LibraryChecks.knowledgeDump(db), try Int.fetchOne(db, sql: "SELECT count(*) FROM change_journal") ?? -1)
            }
            let deviceID = store.deviceID
            try store.close()
            let canaryBytes = DeterministicBytes.make(seed: 50, count: 65_536)
            try FileProtector.library.write(canaryBytes, to: canary)
            let record = Expected(device_id: deviceID, knowledge_sha256: Digest.sha256Hex(dump), captures: Self.captureCount,
                                  journal_entries: journal, canary_sha256: Digest.sha256Hex(canaryBytes),
                                  written_at_ms: UTCClock.system.nowMillis())
            try FileProtector.library.write(try JSONEncoder.sortedPretty.encode(record), to: expectedURL)
            let classes = try protection(layout, extra: [canary, expectedURL])
            evidence("T50 persistence probe write: library at \(layout.root.path) with \(Self.captureCount) captures and \(journal) journal entries, knowledge sha256 \(record.knowledge_sha256); canary sha256 \(record.canary_sha256); classes \(classes.joined(separator: " "))")
            evidence("T50 persistence probe write: restart the phone now and do not unlock it (checklist step 4.2)")

        case "verify":
            let record = try JSONDecoder().decode(Expected.self, from: Data(contentsOf: expectedURL))
            let store = try LibraryStore.open(layout)
            defer { try? store.close() }
            let (dump, captures, journal, integrity, fk) = try store.pool.read { db in
                (try LibraryChecks.knowledgeDump(db),
                 try Int.fetchOne(db, sql: "SELECT count(*) FROM capture") ?? -1,
                 try Int.fetchOne(db, sql: "SELECT count(*) FROM change_journal") ?? -1,
                 try LibraryChecks.integrity(db),
                 try LibraryChecks.foreignKeyViolations(db))
            }
            #expect(Digest.sha256Hex(dump) == record.knowledge_sha256, "knowledge rows changed")
            #expect(captures == record.captures && journal == record.journal_entries)
            #expect(integrity == ["ok"] && fk.isEmpty)
            #expect(store.deviceID == record.device_id, "device identity changed")
            try store.pool.read { (db: Database) throws in
                #expect(try CrashDrill.verify(db, acknowledged: Set(0..<record.captures), checkContentOf: Set(0..<record.captures)).isEmpty)
            }
            let canaryDigest = try Digest.sha256Hex(fileAt: canary).digest
            #expect(canaryDigest == record.canary_sha256, "canary changed")
            let classes = try protection(layout, extra: [canary, expectedURL])
            let ageSeconds = (UTCClock.system.nowMillis() - record.written_at_ms) / 1000
            evidence("T50 persistence probe verify: written \(ageSeconds) s ago; knowledge sha256 \(Digest.sha256Hex(dump) == record.knowledge_sha256 ? "equal" : "DIFFERENT"); \(captures) captures, \(journal) journal entries, integrity \(integrity.joined(separator: ";")), \(fk.count) foreign-key violations; canary \(canaryDigest == record.canary_sha256 ? "intact" : "DIFFERENT"); classes \(classes.joined(separator: " "))")

        case "clean":
            if fm.fileExists(atPath: layout.root.path) { try fm.removeItem(at: layout.root) }
            evidence("T50 persistence probe clean: removed \(layout.root.path)")

        default:
            Issue.record("SYLVIA_DEVICE_PERSIST_PROBE must be write, verify or clean, not \(mode)")
        }
    }
}
