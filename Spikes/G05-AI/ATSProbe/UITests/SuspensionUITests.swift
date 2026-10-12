import XCTest

/// D4 (plan 14.4, T33): AI requests are foreground work. While the probe app streams a long answer from its in-app
/// fake server through the real adapter and AskCoordinator, the test presses Home, waits, brings the app back and
/// checks that the answer is "Interrupted · partial answer" with its partial text, durable on disk, and that the
/// question was sent once and never resent. This is the simulator run; the device run is checklist step 4.
final class SuspensionUITests: XCTestCase {
    static func number(_ label: String) -> Int {
        Int(label.split(separator: " ").compactMap { Int($0) }.first ?? -1)
    }

    @MainActor
    static func eventually(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return condition()
    }

    @MainActor
    func testLeavingTheForegroundMidStreamLeavesAnInterruptedPartialAnswer() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["suspension.start"].tap()
        let status = app.staticTexts["suspension.status"]
        let characters = app.staticTexts["suspension.chars"]
        let requests = app.staticTexts["suspension.requests"]
        let question = app.staticTexts["suspension.question"]
        let stored = app.staticTexts["suspension.stored"]

        XCTAssertTrue(Self.eventually(timeout: 30) { status.label.hasPrefix("streaming") && Self.number(characters.label) >= 20 },
                      "the answer should be streaming; status=\(status.label) \(characters.label)")
        let before = Self.number(characters.label)

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 5)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        // The app's own log line shows the scene really left the foreground and the stop ran (XCUIApplication.state
        // is not a reliable witness of the background transition on the simulator).
        let stopLine = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "left the foreground: stopped 1 request(s); records written=true")).firstMatch
        XCTAssertTrue(stopLine.waitForExistence(timeout: 10), "the scene-phase handler stopped the request and the record was written")

        XCTAssertTrue(Self.eventually(timeout: 10) { status.label == "interrupted · Interrupted · partial answer" }, "status=\(status.label)")
        XCTAssertTrue(Self.eventually(timeout: 5) { stored.label.hasPrefix("stored interrupted · Interrupted · partial answer") },
                      "the interrupted record is on disk; \(stored.label)")
        let after = Self.number(characters.label)
        XCTAssertGreaterThanOrEqual(after, before, "partial text is kept")
        XCTAssertLessThan(after, 300 * 5, "the stream did not run to its end")
        XCTAssertEqual(requests.label, "requests 1")
        XCTAssertEqual(question.label, "question sent 1 times")

        // Nothing resends or keeps streaming after the return.
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(requests.label, "requests 1")
        XCTAssertEqual(Self.number(characters.label), after)
        XCTAssertEqual(status.label, "interrupted · Interrupted · partial answer")
        print("SUSPENSION-PROBE before-home=\(before) after-return=\(after) status=\(status.label) \(stored.label) \(requests.label) \(question.label)")
    }
}
