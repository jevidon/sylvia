import XCTest

/// A smoke run of the app itself on the simulator (review H-05 of the decisions round, 22 October 2026). The unit tests
/// compile `Core/` only, so this is the check that `App/` works before the device run: the app delegate and its
/// notification wiring, the background refresh registration, the real 2 s ticker, the tone in an app process (it keeps
/// the app running in the background) and the screen. It launches the app, starts a run, sends the app to the
/// background for 14 s, brings it back, stops the run, and launches the app again. Its assertions read the screen's
/// status line; `Scripts/harness-checks.sh` then copies the app's `harness.log` out of the simulator and checks every
/// line of the run (step 14).
///
/// The simulator cannot lock, and its protection readback is not faithful: nothing here is device evidence (device
/// checklist step 3 is). The tone plays at the configuration's test volume, 0.01: the app is launched with
/// `SYLVIA_AUDIBLE_PLAYBACK=0`, and it is never muted (CLAUDE.md).
@MainActor
final class LockHarnessSmokeUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// The counters of the status line: "Running <run>: attempt N, A acknowledged, F failed, L while locked (LF failed),
    /// G gaps." or "Stopped <run> after N attempts: A acknowledged, F failed, ...".
    struct Status {
        var text: String
        var attempts: Int
        var acknowledged: Int
        var failed: Int
        var gaps: Int

        init?(_ text: String) {
            guard let m = text.firstMatch(of: /(?:attempt |after )(\d+)(?: attempts)?[,:] (\d+) acknowledged, (\d+) failed, .*? (\d+) gaps\./),
                  let attempts = Int(m.output.1), let acknowledged = Int(m.output.2), let failed = Int(m.output.3),
                  let gaps = Int(m.output.4) else { return nil }
            self.text = text
            self.attempts = attempts
            self.acknowledged = acknowledged
            self.failed = failed
            self.gaps = gaps
        }
    }

    private func status(_ app: XCUIApplication) -> String {
        app.staticTexts["harness.status"].label
    }

    /// Waits until the status line satisfies `condition`, for at most `timeout` seconds; returns the last one read.
    private func waitForStatus(_ app: XCUIApplication, timeout: TimeInterval, _ what: String,
                               _ condition: (String) -> Bool) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var last = status(app)
        while Date() < deadline {
            last = status(app)
            if condition(last) { return last }
            _ = XCTWaiter.wait(for: [expectation(description: "poll")], timeout: 0.5)
        }
        XCTFail("the status line did not show \(what) within \(Int(timeout)) s; it read: \(last)")
        return last
    }

    private func pause(_ seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [expectation(description: "pause \(seconds) s")], timeout: seconds)
    }

    /// Taps a button once it can be hit: just after the app is brought back from the background its window is still
    /// animating in, and a tap then has no hit point (a first run of this test tapped Stop at {-1, -1}, and the run
    /// went on).
    private func tapWhenHittable(_ button: XCUIElement, timeout: TimeInterval, _ what: String) {
        XCTAssertTrue(button.waitForExistence(timeout: timeout), "\(what) exists")
        let deadline = Date().addingTimeInterval(timeout)
        while !button.isHittable && Date() < deadline { pause(0.5) }
        XCTAssertTrue(button.isHittable, "\(what) can be tapped within \(Int(timeout)) s")
        button.tap()
    }

    func testStartBackgroundForegroundStopRelaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["SYLVIA_AUDIBLE_PLAYBACK"] = "0"
        app.launch()
        XCTAssertTrue(app.staticTexts["harness.status"].waitForExistence(timeout: 60), "the harness's screen")
        _ = waitForStatus(app, timeout: 10, "the idle screen") { $0.hasPrefix("Idle.") }

        tapWhenHittable(app.buttons["harness.start"], timeout: 20, "Start")
        let running = try XCTUnwrap(Status(waitForStatus(app, timeout: 30, "four attempts") {
            ($0.hasPrefix("Running ") && (Status($0)?.attempts ?? 0) >= 4)
        }))
        // No failed attempt: every attempt's capture was acknowledged (the acknowledged count also holds earlier runs'
        // items, so it is not compared with this run's attempts).
        XCTAssertEqual(running.failed, 0, running.text)
        XCTAssertEqual(running.gaps, 0, running.text)

        // In the background the tone keeps the app running: the attempts go on, 2 s apart, with no gap.
        XCUIDevice.shared.press(.home)
        pause(14)
        app.activate()
        let back = try XCTUnwrap(Status(waitForStatus(app, timeout: 20, "the run after the background") {
            $0.hasPrefix("Running ") && Status($0) != nil
        }))
        XCTAssertGreaterThanOrEqual(back.attempts, running.attempts + 6, "about 7 attempts in 14 s: \(back.text)")
        XCTAssertEqual(back.failed, 0, back.text)
        XCTAssertEqual(back.gaps, 0, "no gap: the app was not suspended in the background: \(back.text)")

        tapWhenHittable(app.buttons["harness.stop"], timeout: 20, "Stop")
        let stopped = try XCTUnwrap(Status(waitForStatus(app, timeout: 20, "the stopped run and its check") {
            $0.hasPrefix("Stopped ") && $0.contains("Last check: passed.")
        }))
        XCTAssertEqual(stopped.failed, 0, stopped.text)
        XCTAssertEqual(stopped.gaps, 0, stopped.text)
        XCTAssertGreaterThanOrEqual(stopped.attempts, back.attempts, stopped.text)

        // A new process: it reads how the run ended and checks the library the run left.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["harness.status"].waitForExistence(timeout: 60), "the harness's screen after the relaunch")
        let relaunched = waitForStatus(app, timeout: 20, "the last run and a passed check") {
            $0.hasPrefix("Idle. Last run ") && $0.contains("Last check: passed.")
        }
        XCTAssertTrue(relaunched.contains("\(stopped.attempts) attempts, \(stopped.acknowledged) acknowledged"), relaunched)
        app.terminate()
    }
}
