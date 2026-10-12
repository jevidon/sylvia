import UIKit
import XCTest

/// From outside the app process: rotation of the simulator, a full terminate-and-relaunch, and a real tap on a
/// noteref link (simulator). The app runs scripted scenarios (`ScenarioRunner`) and reports on `scenario.status`.
final class ReaderUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor func waitForStatus(_ app: XCUIApplication, containing needle: String, timeout: TimeInterval = 60) -> String {
        let label = app.staticTexts["scenario.status"]
        let deadline = Date().addingTimeInterval(timeout)
        var last = ""
        while Date() < deadline {
            if label.exists {
                last = label.label
                if last.contains(needle) { return last }
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTFail("status never contained \"\(needle)\"; last: \"\(last)\"")
        return last
    }

    @MainActor func saveScreenshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["SYLVIA_EVIDENCE_DIR"], !dir.isEmpty else { return }
        let image = shot.image
        let size = CGSize(width: image.size.width / 2, height: image.size.height / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? small.pngData()?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
    }

    @MainActor func appendLog(_ line: String) {
        guard let dir = ProcessInfo.processInfo.environment["SYLVIA_EVIDENCE_DIR"], !dir.isEmpty else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("ui-tests.log")
        let text = line + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// T15 from outside: save a highlight, rotate both ways, terminate, relaunch: the highlight is redrawn on the same
    /// text and the saved locator reopens the passage each time.
    @MainActor func testHighlightSurvivesRotationAndRelaunch() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-scenario", "anchor", "-fixture", "se-meditations.epub", "-reset", "1"]
        app.launch()
        let created = waitForStatus(app, containing: "phase=created")
        appendLog("testHighlightSurvivesRotationAndRelaunch created: \(created)")
        XCTAssertTrue(created.contains("ok=1"), created)
        saveScreenshot("ui-anchor-1-created.png")

        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = waitForStatus(app, containing: "phase=rotated w=874")
        appendLog("testHighlightSurvivesRotationAndRelaunch landscape: \(landscape)")
        XCTAssertTrue(landscape.contains("ok=1"), landscape)
        saveScreenshot("ui-anchor-2-landscape.png")

        XCUIDevice.shared.orientation = .portrait
        let portrait = waitForStatus(app, containing: "phase=rotated w=402")
        appendLog("testHighlightSurvivesRotationAndRelaunch portrait: \(portrait)")
        XCTAssertTrue(portrait.contains("ok=1"), portrait)

        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["-scenario", "anchor", "-fixture", "se-meditations.epub"]
        relaunched.launch()
        let after = waitForStatus(relaunched, containing: "phase=relaunch")
        appendLog("testHighlightSurvivesRotationAndRelaunch relaunch: \(after)")
        XCTAssertTrue(after.contains("ok=1"), after)
        saveScreenshot("ui-anchor-3-relaunched.png")
        relaunched.terminate()
    }

    /// A real tap on the first noteref of Book I: Readium hands the note to the adapter, which shows it in place.
    @MainActor func testTappingANoterefShowsTheNoteWithoutMoving() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-scenario", "footnote", "-fixture", "se-meditations.epub", "-reset", "1"]
        app.launch()
        let ready = waitForStatus(app, containing: "phase=ready")
        appendLog("testTappingANoterefShowsTheNoteWithoutMoving ready: \(ready)")
        let link = app.webViews.links["1"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 20), "noteref link not exposed to accessibility")
        link.tap()
        let note = waitForStatus(app, containing: "phase=note")
        appendLog("testTappingANoterefShowsTheNoteWithoutMoving note: \(note)")
        XCTAssertTrue(note.contains("unchanged=1"), note)
        XCTAssertTrue(note.contains("Annius Verius"), note)
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "note popup not shown")
        saveScreenshot("ui-footnote-note.png")
        app.terminate()
    }
}
