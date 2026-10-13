import XCTest

/// Runs the quick-capture control through Control Center on the (unlocked) simulator, as a person would (review R5-01;
/// ADR-0007): with the harness playing, the test opens Control Center from SpringBoard, removes any copy of the
/// "Capture the last 30 seconds" control left by an earlier run, adds it from the controls gallery ("Add Controls",
/// "Add a Control", the G04 Audio section), closes and reopens Control Center and presses the placed control. The
/// system then performs the control's `CaptureMomentIntent(surface: .control)`; the harness log line `capture
/// origin=... process=...` (read by `Spikes/G04-Audio/Scripts/quick_capture_simulator_attempt.sh`) names the
/// process that performed it and whether the surface parameter arrived. Screenshots are kept as evidence. The Lock
/// Screen placement, the Action button and anything while locked are device checklist steps 9-13.
final class QuickCaptureThroughControlCenterUITests: XCTestCase {
    /// The control's kind (`CaptureMomentControl.kind`) is the accessibility identifier of its button in Control
    /// Center and in the gallery; its display name identifies its icon.
    static let kind = "com.jevidon.sylvia.spike.g04audio.capture"
    static let displayName = "Capture the last 30 seconds"

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testControlInControlCenterRunsTheCaptureIntent() throws {
        let harness = XCUIApplication()
        // Quiet (1 % volume) unless SYLVIA_AUDIBLE_PLAYBACK=1 (forwarded by the script as TEST_RUNNER_SYLVIA_AUDIBLE_PLAYBACK).
        let audible = ProcessInfo.processInfo.environment["SYLVIA_AUDIBLE_PLAYBACK"] == "1"
        harness.launchArguments = ["-g04AutoPlay", "YES", "-g04AudiblePlayback", audible ? "YES" : "NO"]
        harness.launch()
        let playing = harness.staticTexts.containing(NSPredicate(format: "label CONTAINS 'status playing'")).firstMatch
        XCTAssertTrue(playing.waitForExistence(timeout: 30), "the harness did not start playing")
        print("g04-quick-capture-control-ui harness_captures_before=\(originTexts(harness).count)")

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1)
        openControlCenter(springboard)

        // Edit mode: remove every copy an earlier run placed, so this run shows the whole path (add, then press).
        let addControls = springboard.buttons["Add Controls"]
        XCTAssertTrue(addControls.waitForExistence(timeout: 5), "Control Center has no 'Add Controls' button")
        addControls.tap()
        let placed = springboard.icons.matching(identifier: Self.displayName)
        var removed = 0
        while placed.count > 0, removed < 10 {
            let delete = placed.firstMatch.buttons["DeleteButton"]
            XCTAssertTrue(delete.waitForExistence(timeout: 5), "a placed control has no delete button in edit mode")
            delete.tap()
            removed += 1
            Thread.sleep(forTimeInterval: 1)
        }
        print("g04-quick-capture-control-ui removed_earlier_copies=\(removed)")

        // The controls gallery lists the control under the app's name; tapping it places it in Control Center.
        let addControl = springboard.buttons["Add a Control"]
        XCTAssertTrue(addControl.waitForExistence(timeout: 5), "edit mode has no 'Add a Control' button")
        addControl.tap()
        let galleryItem = springboard.icons[Self.displayName]
        XCTAssertTrue(galleryItem.waitForExistence(timeout: 15), "the controls gallery does not list '\(Self.displayName)'")
        attach(springboard, "control-gallery")
        galleryItem.tap()
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(placed.count, 1, "the control was not placed in Control Center")

        // Leave edit mode (close Control Center), then open it again as a person would to use the control.
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        openControlCenter(springboard)
        let control = springboard.buttons.matching(identifier: Self.kind).firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 10), "the placed control is not in Control Center")
        XCTAssertTrue(control.isHittable, "the placed control cannot be pressed")
        control.tap()
        print("g04-quick-capture-control-ui pressed=\(Self.kind) at=\(ISO8601DateFormatter().string(from: Date()))")
        // The system performs the intent; Control Center shows no text for a control button.
        Thread.sleep(forTimeInterval: 6)
        attach(springboard, "control-center-after-press")

        XCUIDevice.shared.press(.home)
        harness.activate()
        Thread.sleep(forTimeInterval: 2)
        attach(harness, "harness-after-control")
        let origins = originTexts(harness)
        print("g04-quick-capture-control-ui harness_captures_after=\(origins.count) origins=\(origins)")
    }

    /// Opens Control Center with a swipe down from the top right corner (retried: the first swipe after a launch is
    /// sometimes taken as a notification-centre or home gesture).
    @MainActor
    private func openControlCenter(_ springboard: XCUIApplication) {
        let addControls = springboard.buttons["Add Controls"]
        for attempt in 1...3 {
            let start = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.005))
            let end = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.6))
            start.press(forDuration: 0.1, thenDragTo: end)
            if addControls.waitForExistence(timeout: 4) { return }
            print("g04-quick-capture-control-ui control_center_not_open attempt=\(attempt)")
            XCUIDevice.shared.press(.home)
            Thread.sleep(forTimeInterval: 1)
        }
        XCTFail("Control Center did not open")
    }

    /// The origin line of every capture the harness lists (`intent.control@<process>` for the control,
    /// `intent@<process>` for the App Shortcut, `player`, ...).
    @MainActor
    private func originTexts(_ app: XCUIApplication) -> [String] {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'intent' OR label == 'player'"))
            .allElementsBoundByIndex.map(\.label)
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
