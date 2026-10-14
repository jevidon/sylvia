import XCTest

/// Runs the quick-capture control through Control Center on the (unlocked) simulator, as a person would (review R5-01;
/// ADR-0007). `testControlInControlCenterRunsTheCaptureIntent`: with the harness playing, the test opens Control Center
/// from SpringBoard, removes any copy of the "Capture the last 30 seconds" control left by an earlier run, adds it from
/// the controls gallery ("Add Controls", "Add a Control", the G04 Audio section), closes and reopens Control Center and
/// presses the placed control. The system then performs the control `CaptureMomentIntent(surface: .control)`; the
/// harness log line `capture origin=... process=...` (read by `Spikes/G04-Audio/Scripts/quick_capture_simulator_attempt.sh`)
/// names the process that performed it and whether the surface parameter arrived. The two other tests press the placed
/// control when nothing has been heard (review R6-01, device checklist step 12): with the harness not running (the
/// system launches it to perform the intent) and with the harness running its restored, unplayed book. Each test
/// records the number of capture records before and after (`CaptureSummary`; review R6-06). Screenshots are kept as
/// evidence. The Lock Screen placement, the Action button and anything while locked are device checklist steps 9-13.
final class QuickCaptureThroughControlCenterUITests: XCTestCase {
    /// The control kind (`CaptureMomentControl.kind`) is the accessibility identifier of its button in Control Center
    /// and in the gallery; its display name identifies its icon.
    static let kind = "com.jevidon.sylvia.spike.g04audio.capture"
    static let displayName = "Capture the last 30 seconds"

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testControlInControlCenterRunsTheCaptureIntent() throws {
        let harness = XCUIApplication()
        harness.launchArguments = harnessLaunchArguments(autoPlay: true)
        harness.launch()
        let playing = harness.staticTexts.containing(NSPredicate(format: "label CONTAINS 'status playing'")).firstMatch
        XCTAssertTrue(playing.waitForExistence(timeout: 30), "the harness did not start playing")
        let before = try XCTUnwrap(CaptureSummary.read(harness))
        print("g04-quick-capture-control-ui harness_captures_before=\(before.count) newest=\(before.newest)")

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

        // The controls gallery lists the control under the app name; tapping it places it in Control Center.
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
        print("g04-quick-capture-control-ui pressed=\(Self.kind) at=\(logTimestamp())")
        // The system performs the intent; Control Center shows no text for a control button.
        Thread.sleep(forTimeInterval: 6)
        attach(springboard, "control-center-after-press")

        XCUIDevice.shared.press(.home)
        harness.activate()
        Thread.sleep(forTimeInterval: 2)
        attach(harness, "harness-after-control")
        let after = try XCTUnwrap(CaptureSummary.read(harness))
        print("g04-quick-capture-control-ui harness_captures_after=\(after.count) newest=\(after.newest)")
        // One press makes at most one capture; the CI script checks the change against the harness log.
        XCTAssertTrue((0...1).contains(after.count - before.count), "capture records \(before.count) -> \(after.count)")
    }

    /// Review R6-01 (device checklist step 12): the control pressed while the harness is not running. The system launches
    /// the harness in the background to perform the intent; the book it restores has not played in that process, so the
    /// intent answers nothing to capture and no record is written, whether the restore finished before the intent
    /// arrived or not. Needs the control in Control Center (`testControlInControlCenterRunsTheCaptureIntent` places it).
    @MainActor
    func testControlPressedWhileTheHarnessIsNotRunningCapturesNothing() throws {
        let harness = XCUIApplication()
        harness.launchArguments = harnessLaunchArguments(autoPlay: false)
        harness.launch()
        let paused = harness.staticTexts.containing(NSPredicate(format: "label CONTAINS 'status paused'")).firstMatch
        XCTAssertTrue(paused.waitForExistence(timeout: 30), "the harness did not load its book")
        let before = try XCTUnwrap(CaptureSummary.read(harness))
        print("g04-quick-capture-control-ui cold_captures_before=\(before.count) newest=\(before.newest)")
        harness.terminate()
        XCTAssertTrue(harness.wait(for: .notRunning, timeout: 10), "the harness is still running")

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1)
        openControlCenter(springboard)
        let control = springboard.buttons.matching(identifier: Self.kind).firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 10), "the control is not in Control Center")
        control.tap()
        print("g04-quick-capture-control-ui cold_pressed=\(Self.kind) at=\(logTimestamp())")
        Thread.sleep(forTimeInterval: 8)
        attach(springboard, "control-center-after-cold-press")
        print("g04-quick-capture-control-ui harness_state_after_cold_press=\(Self.name(harness.state))")

        XCUIDevice.shared.press(.home)
        // A new launch (it ends the instance the system started, if any) reads the store.
        harness.launch()
        XCTAssertTrue(paused.waitForExistence(timeout: 30), "the harness did not load its book")
        let after = try XCTUnwrap(CaptureSummary.read(harness))
        print("g04-quick-capture-control-ui cold_captures_after=\(after.count) newest=\(after.newest)")
        XCTAssertEqual(after.count, before.count, "a capture was written although nothing had been heard")
    }

    /// Review R6-01: the control pressed while the harness runs with its book restored but not played since launch (the
    /// state of a cold launch once its restore has finished): nothing to capture, no record.
    @MainActor
    func testControlPressedWhileTheRestoredBookHasNotPlayedCapturesNothing() throws {
        let harness = XCUIApplication()
        harness.launchArguments = harnessLaunchArguments(autoPlay: false)
        harness.launch()
        let paused = harness.staticTexts.containing(NSPredicate(format: "label CONTAINS 'status paused'")).firstMatch
        XCTAssertTrue(paused.waitForExistence(timeout: 30), "the harness did not load its book")
        let before = try XCTUnwrap(CaptureSummary.read(harness))
        print("g04-quick-capture-control-ui restored_captures_before=\(before.count) newest=\(before.newest)")

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1)
        openControlCenter(springboard)
        let control = springboard.buttons.matching(identifier: Self.kind).firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 10), "the control is not in Control Center")
        control.tap()
        print("g04-quick-capture-control-ui restored_pressed=\(Self.kind) at=\(logTimestamp())")
        Thread.sleep(forTimeInterval: 6)

        XCUIDevice.shared.press(.home)
        harness.activate()
        Thread.sleep(forTimeInterval: 2)
        let after = try XCTUnwrap(CaptureSummary.read(harness))
        print("g04-quick-capture-control-ui restored_captures_after=\(after.count) newest=\(after.newest)")
        XCTAssertEqual(after.count, before.count, "a capture was written although nothing had been heard")
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

    /// The application state by name (for the test output).
    static func name(_ state: XCUIApplication.State) -> String {
        switch state {
        case .notRunning: "notRunning"
        case .runningBackgroundSuspended: "runningBackgroundSuspended"
        case .runningBackground: "runningBackground"
        case .runningForeground: "runningForeground"
        case .unknown: "unknown"
        @unknown default: "state\(state.rawValue)"
        }
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
