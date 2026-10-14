import XCTest

/// Runs the quick-capture App Shortcut through the system on the (unlocked) simulator, to see which process performs
/// `CaptureMomentIntent` (ADR-0007; G0.4 review gap). The harness is launched playing (`-g04AutoPlay YES`); the test
/// then opens the Shortcuts app, which lists the harness App Shortcut "Capture moment" in its library, and taps it,
/// as a person would. It records screenshots and the number of capture records the harness holds before and after
/// (`CaptureSummary`; review R6-06). The harness log line `capture origin=... process=...` is read afterwards by
/// `Spikes/G04-Audio/Scripts/quick_capture_simulator_attempt.sh`, which checks the counts against it. Locked-device
/// behaviour is not shown here (device checklist steps 9-13).
final class QuickCaptureThroughShortcutsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAppShortcutTileInShortcutsRunsTheCaptureIntent() throws {
        let harness = XCUIApplication()
        harness.launchArguments = harnessLaunchArguments(autoPlay: true)
        harness.launch()
        // The harness shows "status playing" once it has loaded the book and started playing.
        let playing = harness.staticTexts.containing(NSPredicate(format: "label CONTAINS 'status playing'")).firstMatch
        XCTAssertTrue(playing.waitForExistence(timeout: 30), "the harness did not start playing")
        let before = try XCTUnwrap(CaptureSummary.read(harness))
        print("g04-quick-capture-ui harness_captures_before=\(before.count) newest=\(before.newest)")

        let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
        shortcuts.launch()
        // Dismiss anything left over (an alert from an earlier run, a first-run sheet).
        for label in ["OK", "Continue", "Not Now"] {
            let button = shortcuts.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
            if button.waitForExistence(timeout: 2) { button.tap() }
        }
        let tile = shortcuts.descendants(matching: .any).matching(NSPredicate(format: "label == 'Capture moment'")).firstMatch
        if !tile.waitForExistence(timeout: 5) {
            // Not on the current screen: go to the library tab (the label also names other elements, so take the first).
            let library = shortcuts.buttons.matching(NSPredicate(format: "label == 'Library'")).firstMatch
            if library.waitForExistence(timeout: 5) { library.tap() }
        }
        attach(shortcuts, "shortcuts-library")
        XCTAssertTrue(tile.waitForExistence(timeout: 20), "the Shortcuts app does not list the App Shortcut 'Capture moment'")
        tile.tap()
        print("g04-quick-capture-ui tapped=Capture moment at=\(logTimestamp())")
        // The intent runs and the system shows its dialog (the reply phrase) or an error.
        Thread.sleep(forTimeInterval: 8)
        attach(shortcuts, "shortcuts-after-tap")
        let texts = shortcuts.staticTexts.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
        print("g04-quick-capture-ui shortcuts_texts_after_tap=\(texts)")
        let alert = shortcuts.alerts.firstMatch
        if alert.exists {
            let alertTexts = alert.descendants(matching: .any).allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
            print("g04-quick-capture-ui shortcuts_alert=\(alertTexts)")
        }

        harness.activate()
        Thread.sleep(forTimeInterval: 2)
        attach(harness, "harness-after-tap")
        let after = try XCTUnwrap(CaptureSummary.read(harness))
        print("g04-quick-capture-ui harness_captures_after=\(after.count) newest=\(after.newest)")
        // One tap makes at most one capture (the system refuses an ad-hoc-signed build: none). The CI script checks the
        // change against the captures the harness logged.
        XCTAssertTrue((0...1).contains(after.count - before.count), "capture records \(before.count) -> \(after.count)")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
