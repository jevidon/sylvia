import XCTest

/// Plan 8.3 "excessive recursion", from outside the app process (simulator). Readium 3.11.0's content iterator and
/// search service are run over g01-deep-nesting.epub (10,000 nested spans) once without the adapter's controls and
/// once with them, and over g01-nesting-bypass.epub (nesting a text-level scanner measured as shallow) with them.
/// Without the controls the app is expected to crash (stack overflow); these tests pin that down so a Readium upgrade
/// that fixes it is noticed, and show that the adapter keeps the app alive.
///
/// Whether the app crashed is decided here, deterministically, by the app's own process: it wrote its pid before the
/// walk and `kill(pid, 0)` fails with ESRCH once it has exited without reporting `parse-done`. That the exit was a
/// stack overflow is decided by the app itself: `Harness/CrashSignalRecorder.c` (installed before `main` when
/// `SYLVIA_CRASH_SIGNAL_FILE` is set) records the fatal signal from an alternate signal stack, with the fault address and
/// stack pointer against the crashing thread's stack bounds, and the test requires `kind=stack-overflow` (review R2-03:
/// macOS does not always write a crash report, and "the process exited" alone does not say how). The CI drop-in also
/// matches each crashed pid logged here with its crash report when there is one (`Scripts/ci.d/31-g01-epub.sh`), which
/// must show the stack overflow in Readium's content iterator. XCTest's own record of the crash is not relied on: it
/// depends on XCTest collecting diagnostics from the simulator, which failed in one review run ("unable to find
/// utility simctl"), so the crash went unrecorded and a strict expected failure failed the test (review R1-03).
final class DeepNestingUITests: XCTestCase {
    override func setUp() {
        // The expected crash is recorded as an (expected) failure; keep going so the outcome is still checked and logged.
        continueAfterFailure = true
    }

    enum Outcome: Equatable { case finished(String), crashed(String), timedOut(String) }

    /// Launches the `parse-<mode>-<safety>` scenario and waits for it to finish or for the app to stop running.
    /// The scenario's status is read from a file (not the accessibility tree), so a crash never races a UI query.
    @MainActor func runParse(mode: String, safety: String, fixture: String = "g01-deep-nesting.epub") -> Outcome {
        let statusFile = FileManager.default.temporaryDirectory.appendingPathComponent("g01-parse-\(mode)-\(safety)-\(UUID().uuidString).txt")
        let app = XCUIApplication()
        app.launchArguments = ["-scenario", "parse-\(mode)-\(safety)", "-fixture", fixture]
        let signalFile = URL(fileURLWithPath: statusFile.path + ".signal")
        app.launchEnvironment["SYLVIA_SCENARIO_STATUS_FILE"] = statusFile.path
        app.launchEnvironment["SYLVIA_CRASH_SIGNAL_FILE"] = signalFile.path
        app.launch()
        func read() -> String { ((try? String(contentsOf: statusFile, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        /// The fatal-signal lines the app's recorder wrote ("none" when it wrote none).
        func signals() -> String {
            let lines = ((try? String(contentsOf: signalFile, encoding: .utf8)) ?? "").split(separator: "\n").filter { $0.hasPrefix("signal=") }
            return lines.isEmpty ? "signal_record=none" : "signal_record=[" + lines.joined(separator: "; ") + "]"
        }
        var last = ""
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            last = read().isEmpty ? last : read()
            if last.contains("phase=parse-done") {
                app.terminate()
                return .finished(last + " " + signals())
            }
            // XCUIApplication.state was not reliably updated after a crash in this setup, so the app's own process
            // is checked: simulator apps are host processes, and kill(pid, 0) fails with ESRCH once it has exited.
            if let pid = Self.pid(in: last), kill(pid, 0) != 0, errno == ESRCH {
                last = read().isEmpty ? last : read()
                let ending = last + " " + signals()
                return last.contains("phase=parse-done") ? .finished(ending) : .crashed(ending + " exited=1")
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        app.terminate()
        return .timedOut(last)
    }

    static func pid(in status: String) -> pid_t? {
        guard let r = status.range(of: "pid=") else { return nil }
        return pid_t(status[r.upperBound...].prefix { $0.isNumber })
    }

    @MainActor func log(_ name: String, _ outcome: Outcome) {
        guard let dir = ProcessInfo.processInfo.environment["SYLVIA_EVIDENCE_DIR"], !dir.isEmpty else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("ui-deep-nesting.log")
        let line = "\(name): \(outcome)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// XCTest may record the app's crash as a test failure; `XCTExpectFailure` absorbs that one issue. It is not strict
    /// (XCTest does not always record the crash; see above), and its matcher accepts only XCTest's crash report, never
    /// this test's own assertions, which carry the `outcome:` prefix. The assertion that the crash happened is
    /// `guard case .crashed` below.
    @MainActor func expectCrash() {
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        options.issueMatcher = { !$0.compactDescription.contains("outcome:") && $0.compactDescription.contains("crashed") }
        XCTExpectFailure("Readium 3.11.0 overflows the stack on 10,000 nested elements", options: options)
    }

    @MainActor func testReadiumContentIteratorAloneCrashesOnDeepNesting() {
        expectCrash()
        let outcome = runParse(mode: "iterator", safety: "raw")
        log("iterator raw (Readium 3.11.0 alone)", outcome)
        guard case let .crashed(last) = outcome else { return XCTFail("outcome: expected Readium's content iterator to stop the app; got \(outcome)") }
        XCTAssertTrue(last.contains("phase=parse-started"), "outcome: \(last)")
        XCTAssertTrue(last.contains("kind=stack-overflow"), "outcome: the app's signal record does not show a stack overflow: \(last)")
    }

    @MainActor func testReadiumSearchAloneCrashesOnDeepNesting() {
        expectCrash()
        let outcome = runParse(mode: "search", safety: "raw")
        log("search raw (Readium 3.11.0 alone)", outcome)
        guard case let .crashed(last) = outcome else { return XCTFail("outcome: expected Readium's search service to stop the app; got \(outcome)") }
        XCTAssertTrue(last.contains("phase=parse-started"), "outcome: \(last)")
        XCTAssertTrue(last.contains("kind=stack-overflow"), "outcome: the app's signal record does not show a stack overflow: \(last)")
    }

    @MainActor func testAdapterKeepsTheIteratorAlive() {
        let outcome = runParse(mode: "iterator", safety: "adapter")
        log("iterator through the adapter", outcome)
        guard case let .finished(status) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(status.contains("signal_record=none"), status)
        XCTAssertTrue(status.contains("unavailable=OEBPS/c2.xhtml"), status)
    }

    @MainActor func testAdapterKeepsSearchAlive() {
        let outcome = runParse(mode: "search", safety: "adapter")
        log("search through the adapter", outcome)
        guard case let .finished(status) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(status.contains("signal_record=none"), status)
        XCTAssertTrue(status.contains("count=0"), status)
        XCTAssertTrue(status.contains("unavailable=OEBPS/c2.xhtml"), status)
    }

    /// Review R1-01: the nesting a text-level scanner measured as shallow crashed the app through the adapter. Now the
    /// comment-wrapped spans are never served and the unmatched-end-tag chapter is withheld.
    @MainActor func testAdapterKeepsTheIteratorAliveOnParserDivergenceNesting() {
        let outcome = runParse(mode: "iterator", safety: "adapter", fixture: "g01-nesting-bypass.epub")
        log("iterator through the adapter, g01-nesting-bypass.epub", outcome)
        guard case let .finished(status) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(status.contains("signal_record=none"), status)
        XCTAssertTrue(status.contains("unavailable=OEBPS/c3.xhtml"), status)
    }

    @MainActor func testAdapterKeepsSearchAliveOnParserDivergenceNesting() {
        let outcome = runParse(mode: "search", safety: "adapter", fixture: "g01-nesting-bypass.epub")
        log("search through the adapter, g01-nesting-bypass.epub", outcome)
        guard case let .finished(status) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(status.contains("signal_record=none"), status)
        XCTAssertTrue(status.contains("count=0"), status)
        XCTAssertTrue(status.contains("unavailable=OEBPS/c3.xhtml"), status)
    }
}
