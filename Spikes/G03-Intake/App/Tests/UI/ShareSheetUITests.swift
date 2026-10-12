// End-to-end share into the real share extension on the simulator, driven through the system share sheet
// presented by the harness app. Evidence lines start with "G03-EVIDENCE".
import Darwin
import XCTest

@MainActor
final class ShareSheetUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launch(bytes: Int, ext: String = "epub") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-G03ShareBytes", String(bytes), "-G03ShareExtension", ext]
        app.launch()
        XCTAssertTrue(app.staticTexts["harness.summary"].waitForExistence(timeout: 20))
        return app
    }

    /// "jobs=N staged=N review=N share=N" -> the share count.
    private func shareJobs(_ app: XCUIApplication) -> Int {
        let label = app.staticTexts["harness.summary"].label
        guard let range = label.range(of: "share=") else { return -1 }
        return Int(label[range.upperBound...].prefix { $0.isNumber }) ?? -1
    }

    /// Opens the share sheet and taps the Sylvia Intake extension, scrolling or using More if needed.
    /// On the iOS 26.5 simulator the share sheet labels a third-party share extension with its containing app's
    /// display name ("Sylvia Intake Spike"), in a cell with identifier "shareCell".
    private func openExtension(_ app: XCUIApplication) {
        app.buttons["harness.share"].tap()
        let target = app.cells.matching(NSPredicate(format: "identifier == %@ AND label == %@", "shareCell", "Sylvia Intake Spike")).firstMatch
        if target.waitForExistence(timeout: 15), target.isHittable {
            target.tap()
            return
        }
        // Third-party extensions can sit past the visible app row or behind "More".
        let row = app.collectionViews.firstMatch
        for _ in 0..<4 where !(target.exists && target.isHittable) { row.swipeLeft() }
        if target.exists && target.isHittable { target.tap(); return }
        XCTFail("Sylvia Intake not found in the share sheet:\n\(app.debugDescription)")
    }

    func testShareIntoExtensionIsReceivedAndImported() throws {
        let app = launch(bytes: 3 << 20)
        let before = shareJobs(app)
        openExtension(app)
        let received = app.staticTexts["share.received"]
        XCTAssertTrue(received.waitForExistence(timeout: 60), "extension did not report receipt:\n\(app.debugDescription)")
        let peak = app.staticTexts["share.peakFootprint"]
        if peak.exists { print("G03-EVIDENCE share 3 MiB: extension says \(peak.label)") }
        let detail = app.staticTexts["share.receivedDetail"].label
        print("G03-EVIDENCE share 3 MiB: extension reports '\(detail)'")
        print("G03-EVIDENCE share 3 MiB: \(app.staticTexts["share.representations"].label)")
        print("G03-EVIDENCE share 3 MiB: \(app.staticTexts["share.protection"].label)")
        XCTAssertTrue(detail.contains("\(3 << 20) bytes"), detail)
        app.buttons["share.done"].tap()
        let predicate = NSPredicate(format: "label CONTAINS %@", "share=\(before + 1)")
        let imported = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: app.staticTexts["harness.summary"])], timeout: 30)
        XCTAssertEqual(imported, .completed, "app did not import the handoff: \(app.staticTexts["harness.summary"].label)")
        print("G03-EVIDENCE share 3 MiB: app summary after scan: \(app.staticTexts["harness.summary"].label)")
    }

    /// Extension memory must not grow with the file size: 64 MiB, 1 GiB, just over 4 GiB and just over 8 GiB through
    /// the real share sheet and extension (each in a fresh extension process). Every size must be received in full. The simulator does not enforce extension memory limits; this measures, it does
    /// not prove the device limit is respected (device checklist).
    func testExtensionMemoryDoesNotGrowWithFileSize() throws {
        var peaks: [(Int, UInt64, UInt64)] = []
        for size in [64 << 20, 1 << 30, (4 << 30) + 1, (8 << 30) + 1] {
            let app = launch(bytes: size)
            let before = shareJobs(app)
            openExtension(app)
            XCTAssertTrue(app.staticTexts["share.received"].waitForExistence(timeout: 600), "no receipt for \(size) bytes:\n\(app.debugDescription)")
            let label = app.staticTexts["share.peakFootprint"].label
            let numbers = label.split(whereSeparator: { !$0.isNumber }).compactMap { UInt64($0) }
            XCTAssertEqual(numbers.count, 2, label)
            peaks.append((size, numbers.first ?? 0, numbers.last ?? 0))
            print("G03-EVIDENCE share \(size) bytes: extension \(label)")
            print("G03-EVIDENCE share \(size) bytes: \(app.staticTexts["share.availableMemory"].label)")
            print("G03-EVIDENCE share \(size) bytes: \(app.staticTexts["share.footprintSeries"].label)")
            let detail = app.staticTexts["share.receivedDetail"].label
            print("G03-EVIDENCE share \(size) bytes: extension reports '\(detail)'")
            XCTAssertTrue(detail.contains("\(size) bytes"), "the whole file must be received: \(detail)")
            print("G03-EVIDENCE share \(size) bytes: Done tapped at \(ISO8601DateFormatter.string(from: Date(), timeZone: .gmt, formatOptions: [.withFullTime, .withFractionalSeconds]))")
            app.buttons["share.done"].tap()
            let predicate = NSPredicate(format: "label CONTAINS %@", "share=\(before + 1)")
            let imported = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: app.staticTexts["harness.summary"])], timeout: 120)
            print("G03-EVIDENCE share \(size) bytes: app scans: \(app.staticTexts["harness.scanLog"].label)")
            XCTAssertEqual(imported, .completed, "not imported: \(app.staticTexts["harness.summary"].label)")
            app.terminate()
        }
        let growth = Int64(peaks.last!.2) - Int64(peaks.first!.2)
        let plateau = Int64(peaks[3].2) - Int64(peaks[2].2)
        print("G03-EVIDENCE extension peak growth from 64 MiB to 8 GiB + 1 byte: \(growth) bytes; from 4 GiB + 1 to 8 GiB + 1: \(plateau) bytes")
        XCTAssertLessThan(plateau, 4 << 20, "doubling the file from 4 GiB to 8 GiB must not raise the peak: \(peaks)")
        // On the simulator the footprint rises by about 15 MiB over the first ~2 GiB and then stays flat (G0.3 report);
        // the plateau check above is the bounded-memory claim, this is a sanity bound.
        XCTAssertLessThan(growth, 32 << 20, "extension memory grew with file size: \(peaks)")
    }

    func testCancelMidCopyShowsFallbackAndClaimsNothing() throws {
        let app = launch(bytes: 3 << 30)   // 3 GiB so the copy is still running when Cancel is tapped
        let before = shareJobs(app)
        openExtension(app)
        XCTAssertTrue(app.staticTexts["share.copying"].waitForExistence(timeout: 60))
        app.buttons["share.cancel"].tap()
        let notReceived = app.staticTexts["share.notReceived"]
        XCTAssertTrue(notReceived.waitForExistence(timeout: 60), "\(app.debugDescription)")
        XCTAssertFalse(app.staticTexts["share.received"].exists)
        print("G03-EVIDENCE cancel mid-copy: extension shows '\(notReceived.label)' / '\(app.staticTexts["share.reason"].label)'")
        app.buttons["share.done"].tap()
        returnToHarness(app)
        app.buttons["harness.scan"].tap()
        sleep(3)
        XCTAssertEqual(shareJobs(app), before, "a cancelled share must not import")
    }

    /// Real process death of the share extension mid-copy (T07 on the simulator). The simulator's processes are
    /// host processes, so the test finds the extension by name and sends SIGKILL, but only to an IntakeShare whose
    /// executable lies inside this simulator's own device directory: an extension running in another simulator (a
    /// parallel run from another worktree) is never touched.
    func testKillExtensionMidCopyClaimsNothing() throws {
        let app = launch(bytes: 3 << 30)
        let before = shareJobs(app)
        openExtension(app)
        let copied = app.staticTexts["share.copiedBytes"]
        XCTAssertTrue(copied.waitForExistence(timeout: 60))
        // Wait until some bytes are on disk, then kill.
        let started = Date()
        while !copied.label.contains("MB") && !copied.label.contains("GB") && Date().timeIntervalSince(started) < 30 { usleep(100_000) }
        let label = copied.label
        let device = try XCTUnwrap(simulatorDeviceID(), "cannot tell which simulator this test runs in; refusing to kill by name alone")
        let candidates = processIDs(named: "IntakeShare")
        let pids = candidates.filter { executablePath(of: $0)?.contains("/Devices/\(device)/") == true }
        XCTAssertEqual(pids.count, 1, "expected exactly one IntakeShare in simulator \(device); found \(pids) of \(candidates)")
        for pid in pids { kill(pid, SIGKILL) }
        print("G03-EVIDENCE kill mid-copy: SIGKILL sent to IntakeShare pid(s) \(pids) in simulator \(device) (host-wide IntakeShare processes: \(candidates.count)) after '\(label)'")
        sleep(2)
        XCTAssertFalse(app.staticTexts["share.received"].exists, "a killed extension must never show Received")
        // Dismiss whatever the system left, then rescan.
        if app.buttons["share.done"].exists { app.buttons["share.done"].tap() }
        returnToHarness(app)
        app.buttons["harness.scan"].firstMatch.tap()
        let predicate = NSPredicate(format: "label CONTAINS %@", "manual:")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: app.staticTexts["harness.lastScan"])], timeout: 30), .completed)
        let scan = app.staticTexts["harness.lastScan"].label
        print("G03-EVIDENCE kill mid-copy: app scan after kill: \(scan); summary \(app.staticTexts["harness.summary"].label)")
        XCTAssertEqual(shareJobs(app), before, "the partial copy must not be imported")
        // The killed extension's directory is fresh, so the scan must see exactly one incomplete handoff and must
        // neither accept nor remove it (the cleanup policy only removes it once it is an hour old).
        XCTAssertTrue(scan.contains("accepted=0") && scan.contains("inProgress=1") && scan.contains("removed=0"), scan)
    }

    /// After an extension cancels or dies the share sheet goes back to its activity list; close it.
    private func returnToHarness(_ app: XCUIApplication) {
        let close = app.buttons["header.closeButton"]
        if close.waitForExistence(timeout: 5) && close.isHittable { close.tap() }
        let scan = app.buttons["harness.scan"]
        let hittable = NSPredicate(format: "hittable == true")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: hittable, object: scan)], timeout: 15), .completed,
                       "harness not reachable after the share sheet:\n\(app.debugDescription)")
    }

    /// This simulator's UDID: the runner's own bundle lives under .../CoreSimulator/Devices/<UDID>/data/...
    private func simulatorDeviceID() -> String? {
        if let udid = ProcessInfo.processInfo.environment["SIMULATOR_UDID"], udid.count == 36 { return udid }
        let parts = Bundle.main.bundlePath.components(separatedBy: "/")
        guard let index = parts.firstIndex(of: "Devices"), index + 1 < parts.count, parts[index + 1].count == 36 else { return nil }
        return parts[index + 1]
    }

    /// A process's executable path (KERN_PROCARGS2: argc, then the path, NUL-terminated).
    private func executablePath(of pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        let start = MemoryLayout<Int32>.size
        guard let end = buffer[start..<size].firstIndex(of: 0) else { return nil }
        return String(decoding: buffer[start..<end], as: UTF8.self)
    }

    private func processIDs(named name: String) -> [pid_t] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return [] }
        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count + 16)
        size = procs.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }
        return procs.prefix(size / MemoryLayout<kinfo_proc>.stride).compactMap { proc in
            var p = proc
            let command = withUnsafePointer(to: &p.kp_proc.p_comm) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) { String(cString: $0) }
            }
            return command == name ? p.kp_proc.p_pid : nil
        }
    }
}
