import XCTest

/// T41 on the simulator: the harness app is terminated mid-transfer (XCUIApplication.terminate) and launched
/// again; the transfer must finish from its verified parts. Run by
/// Spikes/G02-Transfer/Scripts/simulator-relaunch-run.sh, which starts the sources and then checks the app's
/// event log (pulled from the simulator) for parts fetched twice.
///
/// Environment variables (TEST_RUNNER_ prefix): G02_UI_CODES and G02_UICLOSE_CODES, files of pairing codes for
/// a throttled source that keeps connections open and one that closes every connection (so each part needs a
/// new TLS handshake, and so a new trust challenge, while the app is not running); G02_UI_WAIT_SECONDS.
///
/// What terminate() is: the test runner kills the app's process, as when the system ends a suspended app.
/// It is not a force-quit from the app switcher (after which iOS cancels the app's background transfers);
/// that, true suspension, a reboot and a locked phone are device checklist steps.
@MainActor
final class TerminateRelaunchUITests: XCTestCase {
    let environment = ProcessInfo.processInfo.environment

    func testTerminatedMidTransferResumesFromVerifiedParts() throws {
        try run(codesVariable: "G02_UI_CODES", tag: "keep-alive")
    }

    func testTerminatedMidTransferWhenEveryPartNeedsANewConnection() throws {
        try run(codesVariable: "G02_UICLOSE_CODES", tag: "connection-close")
    }

    private func run(codesVariable: String, tag: String) throws {
        continueAfterFailure = false
        let codes = try XCTUnwrap(environment[codesVariable], "\(codesVariable) not set (run simulator-relaunch-run.sh)")
        let waitSeconds = Double(environment["G02_UI_WAIT_SECONDS"] ?? "") ?? 30
        let app = XCUIApplication()
        app.launchArguments = ["-G02ResetState"]
        app.launchEnvironment["G02_PAIRING_CODE_FILE"] = codes
        app.launch()

        // Pair: the code goes into the same field a paste would fill; the fingerprint is shown in groups of four
        // before anything is sent.
        element(app, "pairing.useTestCode").tap()
        let fingerprint = element(app, "pairing.fingerprint")
        let groups = fingerprint.label.split(separator: " ")
        XCTAssertEqual(groups.count, 16, "fingerprint \(fingerprint.label)")
        XCTAssertTrue(groups.allSatisfy { $0.count == 4 && $0.allSatisfy { "0123456789ABCDEF".contains($0) } })
        element(app, "pairing.pair").tap()
        XCTAssertTrue(waitForLabel(app, "pairing.status", timeout: 60) { $0.hasPrefix("Paired with") })

        element(app, "source.browse").tap()
        element(app, "catalog.download.sim-ui").tap()

        // Terminate once at least two parts are verified and before the transfer can finish.
        XCTAssertTrue(waitForLabel(app, "job.verifiedCount", timeout: 120) { (Self.count($0) ?? 0) >= 2 })
        let verifiedBefore = Self.count(element(app, "job.verifiedCount").label) ?? 0
        let stageBefore = element(app, "job.stage").label
        XCTAssertNotEqual(stageBefore, "Imported", "the transfer finished before it could be interrupted")
        app.terminate()
        XCTAssertEqual(app.state, .notRunning)
        print("G02-UI \(tag): terminated with \(verifiedBefore) verified parts (stage \(stageBefore)); app not running for \(Int(waitSeconds)) s")
        Thread.sleep(forTimeInterval: waitSeconds)

        // Relaunch (no reset): reconciliation keeps the verified parts and the job finishes.
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(waitForLabel(app, "reconciliation.kept", timeout: 60) { $0.hasPrefix("kept verified parts") })
        let kept = element(app, "reconciliation.kept").label
        let summary = element(app, "reconciliation.summary").label
        print("G02-UI \(tag): after relaunch: \(summary); \(kept)")
        XCTAssertGreaterThanOrEqual(Self.number(after: "kept verified parts ", in: kept) ?? -1, verifiedBefore)
        XCTAssertTrue(waitForLabel(app, "job.stage", timeout: 300) { $0 == "Imported" }, "job did not finish after relaunch")
        print("G02-UI \(tag): imported after relaunch; \(element(app, "job.verified").label); \(element(app, "job.received").label)")
    }

    // MARK: Helpers

    private func element(_ app: XCUIApplication, _ identifier: String, timeout: TimeInterval = 20) -> XCUIElement {
        let query = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        var attempt = 0
        while !query.exists && Date() < deadline {
            if !query.waitForExistence(timeout: 1) { Self.scroll(app, attempt: attempt) }
            attempt += 1
        }
        XCTAssertTrue(query.exists, "no element \(identifier)")
        return query
    }

    private func waitForLabel(_ app: XCUIApplication, _ identifier: String, timeout: TimeInterval, _ predicate: (String) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var attempt = 0
        while Date() < deadline {
            let query = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            if query.exists, predicate(query.label) { return true }
            if !query.exists {
                Self.scroll(app, attempt: attempt)
                attempt += 1
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    /// The harness is one long list: an element may be above or below the visible part (the jobs section is
    /// near the top, the catalog buttons further down), so look up first, then down, and repeat.
    static func scroll(_ app: XCUIApplication, attempt: Int) {
        if attempt % 8 < 3 { app.swipeDown() } else { app.swipeUp() }
    }

    static func count(_ label: String) -> Int? { number(after: "verifiedParts=", in: label) }

    static func number(after prefix: String, in label: String) -> Int? {
        guard let range = label.range(of: prefix) else { return nil }
        return Int(label[range.upperBound...].prefix { $0.isNumber })
    }
}
