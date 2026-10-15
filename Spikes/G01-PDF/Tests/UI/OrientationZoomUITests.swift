import XCTest

/// Plan 9.4 survival across an orientation change, and overlay alignment when zoomed and in landscape (simulator):
/// the stored highlight on rotated.pdf page 1 (/Rotate 90) is checked on screen in portrait, landscape, landscape
/// zoomed and portrait zoomed. A person's judgement of alignment on a device remains device checklist step 5.
@MainActor
final class OrientationZoomUITests: ScreenCheckTestCase {
    override func tearDown() {
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
        super.tearDown()
    }

    func waitForOrientation(_ app: XCUIApplication, landscape: Bool) -> Bool {
        Harness.waitFor(10) { (app.frame.width > app.frame.height) == landscape }
    }

    /// The larger side of the first published overlay line (fill plus underline), in window points.
    func firstLineLength(_ app: XCUIApplication) -> CGFloat {
        guard let first = Harness.rects(app, "overlayFrames").first else { return 0 }
        let parts = first.split(separator: " ")
        guard parts.count == 2 else { return 0 }
        let r = Harness.rect(parts[0].dropFirst(2)).union(Harness.rect(parts[1].dropFirst(2)))
        return max(r.width, r.height)
    }

    func testHighlightSurvivesOrientationChangeAndStaysAlignedWhenZoomed() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = Harness.launch(["-fixture", "rotated.pdf", "-resetHighlights", "-seedRange", "1:58:189"])
        let restored = "Highlights: 1 stored, 1 restored exactly"
        XCTAssertTrue(Harness.waitFor(10) { Harness.text(app, "status") == restored }, Harness.text(app, "status"))
        XCTAssertTrue(Harness.waitFor(10) { Harness.text(app, "page").hasPrefix("Page index 1 of") }, Harness.text(app, "page"))
        var log = ["Highlight on rotated.pdf page index 1 (/Rotate 90) through orientation changes and zoom"]
        let lineCount = Harness.rects(app, "overlayFrames").count
        XCTAssertEqual(lineCount, 3)

        log.append("1. portrait, fit to width")
        log += checkOverlayOnScreen(app, name: "orientation-1-portrait", minimumChecked: 3)
        let portraitLength = firstLineLength(app)

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitForOrientation(app, landscape: true), "the harness did not rotate to landscape")
        app.buttons["revealButton"].tap() // scroll the highlight into view at the new layout
        XCTAssertTrue(Harness.waitFor(10) { Harness.text(app, "page").hasPrefix("Page index 1 of") }, Harness.text(app, "page"))
        log.append("2. landscape (device landscapeLeft), app frame \(app.frame.integral), status: \(Harness.text(app, "status"))")
        XCTAssertEqual(Harness.text(app, "status"), restored)
        XCTAssertEqual(Harness.rects(app, "overlayFrames").count, lineCount)
        log += checkOverlayOnScreen(app, name: "orientation-2-landscape")
        let landscapeLength = firstLineLength(app)

        app.buttons["zoomButton"].tap() // 2.5 x the fit scale, scrolled to the highlight
        XCTAssertTrue(Harness.waitFor(5) { self.firstLineLength(app) > landscapeLength * 2 }, "the view did not zoom")
        log.append("3. landscape zoomed to 2.5 x fit: first line \(Int(firstLineLength(app))) pt long vs \(Int(landscapeLength)) pt at fit")
        log += checkOverlayOnScreen(app, name: "orientation-3-landscape-zoomed")

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitForOrientation(app, landscape: false), "the harness did not rotate back to portrait")
        app.buttons["revealButton"].tap()
        log.append("4. back to portrait, still zoomed: first line \(Int(firstLineLength(app))) pt long vs \(Int(portraitLength)) pt at fit; status: \(Harness.text(app, "status"))")
        XCTAssertEqual(Harness.text(app, "status"), restored)
        XCTAssertEqual(Harness.rects(app, "overlayFrames").count, lineCount)
        log += checkOverlayOnScreen(app, name: "orientation-4-portrait-zoomed")
        Harness.writeEvidence("ui-orientation-zoom.txt", log.joined(separator: "\n") + "\n")
    }
}
