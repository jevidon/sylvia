import Foundation
import GRDB
import Testing
@testable import SylviaRecovery

/// T50 device probe, run by a person on a physical iPhone (device checklist
/// Docs/Stage0/device-checklists/G05-Recovery.md, steps 3-4). Disabled unless
/// `SYLVIA_DEVICE_LOCK_PROBE=1` reaches the test runner (pass `TEST_RUNNER_SYLVIA_DEVICE_LOCK_PROBE=1`
/// to xcodebuild), because it waits for the tester to lock the phone.
///
/// Lock detection: a class-A (`complete`) canary file becomes unreadable about 10 s after the
/// device locks. While that is so, the probe keeps saving captures to a class-C library and writing
/// class-C files, which must keep succeeding (authorized background work after first unlock).
@Suite("Device lock probe (T50, physical device only)")
struct DeviceLockProbeTests {
    static var enabled: Bool {
        #if targetEnvironment(simulator) || os(macOS)
        return false
        #else
        return ProcessInfo.processInfo.environment["SYLVIA_DEVICE_LOCK_PROBE"] == "1"
        #endif
    }

    @Test("class-C library stays writable while locked; class-A canary does not",
          .enabled(if: DeviceLockProbeTests.enabled, "needs a physical device, a person to lock it, and SYLVIA_DEVICE_LOCK_PROBE=1"),
          .timeLimit(.minutes(5)))
    func lockedWrites() throws {
        let scratch = try Scratch()
        let layout = scratch.layout()
        try CrashDrill.seed(layout, durability: .acknowledgedSaves)
        let store = try LibraryStore.open(layout)
        defer { try? store.close() }
        let canary = scratch.url.appending(path: "class-a-canary.bin")
        try Data("canary".utf8).write(to: canary, options: .completeFileProtection)
        let seconds = Int(ProcessInfo.processInfo.environment["SYLVIA_DEVICE_LOCK_PROBE_SECONDS"] ?? "120") ?? 120
        evidence("lock probe: lock the device now and keep it locked for at least 60 s; probing for \(seconds) s")
        var lockedSamples = 0
        var lockedFailures: [String] = []
        for second in 0..<seconds {
            let canaryReadable = (try? Data(contentsOf: canary)) != nil
            var saveResult = "ok"
            do {
                try store.saveCapture(CrashDrill.command(second))
                try FileProtector.library.write(Data("tick \(second)".utf8), to: layout.stagingDirectory.appending(path: "tick.bin"))
            } catch {
                saveResult = "FAILED \(error)"
            }
            if !canaryReadable {
                lockedSamples += 1
                if saveResult != "ok" { lockedFailures.append("t=\(second)s \(saveResult)") }
            }
            evidence("t=\(second)s classA_readable=\(canaryReadable) classC_save=\(saveResult)")
            Thread.sleep(forTimeInterval: 1)
        }
        evidence("lock probe summary: \(lockedSamples) locked samples, \(lockedFailures.count) failed class-C saves while locked")
        #expect(lockedSamples >= 30, "the device was not observed locked long enough; lock it and rerun")
        #expect(lockedFailures.isEmpty, "\(lockedFailures.prefix(5))")
        try store.pool.read { (db: Database) throws in
            #expect(try CrashDrill.verify(db, acknowledged: Set(0..<seconds), checkContentOf: Set(0..<seconds)).isEmpty)
        }
    }
}
