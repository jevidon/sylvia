import XCTest

/// On-screen checks in the harness (simulator): the stored highlight is drawn by the live PDFView on a rotated page,
/// a highlight made from a touch selection appears at once (PDFView.setNeedsDisplay, with a control without it) and
/// survives a relaunch.
@MainActor
final class HighlightUITests: ScreenCheckTestCase {
    func testStoredHighlightIsDrawnOnScreenOnRotatedPage() throws {
        // rotated.pdf page 1 (/Rotate 90), scalar range [58, 189): the same text as the rotate-90 anchor sample.
        let app = Harness.launch(["-fixture", "rotated.pdf", "-resetHighlights", "-seedRange", "1:58:189"])
        XCTAssertTrue(Harness.waitFor(10) { Harness.text(app, "status").contains("1 restored exactly") }, Harness.text(app, "status"))
        XCTAssertTrue(Harness.waitFor(10) { Harness.text(app, "page").hasPrefix("Page index 1 of") }, Harness.text(app, "page"))
        let report = checkOverlayOnScreen(app, name: "overlay-rotate-90-screen")
        Harness.writeEvidence("ui-overlay-rotate-90.txt", "Live PDFView screen capture, rotated.pdf page 1 (/Rotate 90)\n" + report.joined(separator: "\n") + "\n")
    }

    func testTouchSelectionHighlightSurvivesRelaunch() throws {
        var app = Harness.launch(["-fixture", "labels-multipage.pdf", "-resetHighlights"])
        let probe = Harness.rects(app, "probePoint")
        XCTAssertEqual(probe.count, 1)
        let p = probe[0].split(separator: ",").compactMap { Double($0) }
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: p[0], dy: p[1])).press(forDuration: 1.2)
        var log = ["Touch selection (long press on page index 0 at page point 200,703) -> Highlight -> relaunch"]
        XCTAssertTrue(Harness.waitFor(10) { Harness.text(app, "timing").hasPrefix("Open ") }, "the harness reports its open time")
        log.append("timing line: \(Harness.text(app, "timing"))")
        // The long press selects a word and shows the edit menu; Sylvia's "Highlight" item is in it.
        let menuHighlight = app.menuItems["Highlight"].firstMatch
        XCTAssertTrue(menuHighlight.waitForExistence(timeout: 5), "the selection edit menu must offer Highlight")
        let selection = Harness.rects(app, "selectionInfo").joined(separator: ";")
        XCTAssertTrue(selection.hasPrefix("pages 0; lines 1;"), selection)
        log.append("selection: \(selection)")
        log.append("edit menu offers Highlight: \(menuHighlight.exists); tapped it")
        menuHighlight.tap()
        XCTAssertTrue(Harness.waitFor(5) { Harness.text(app, "status").hasPrefix("Saved highlight (1") }, Harness.text(app, "status"))
        log.append("after Highlight: \(Harness.text(app, "status"))")
        // The harness dismisses the saved selection and redraws with PDFView.setNeedsDisplay() only (no document
        // reset): the new highlight must be on screen. The control test below shows it is not without that call.
        XCTAssertTrue(Harness.waitFor(5) { Harness.text(app, "selectionInfo").trimmingCharacters(in: .whitespaces).isEmpty },
                      "the saved selection is dismissed")
        log.append("selection after saving: dismissed")
        log += checkOverlayOnScreen(app, name: "touch-highlight-before-relaunch")

        app.terminate()
        app = Harness.launch(["-fixture", "labels-multipage.pdf"])
        XCTAssertTrue(Harness.waitFor(10) { Harness.text(app, "status") == "Highlights: 1 stored, 1 restored exactly" }, Harness.text(app, "status"))
        log.append("after relaunch: \(Harness.text(app, "status"))")
        log += checkOverlayOnScreen(app, name: "touch-highlight-after-relaunch")
        Harness.writeEvidence("ui-touch-highlight-relaunch.txt", log.joined(separator: "\n") + "\n")
    }

    /// Control for the redraw: with `-noRedrawAfterHighlight` the harness saves the highlight and dismisses the
    /// selection but does not call `PDFView.setNeedsDisplay()`. PDFView keeps its cached tiles, so the new highlight
    /// is not on screen; it is drawn after the next relaunch. This shows the call is what puts it on screen.
    func testControlWithoutRedrawNewHighlightIsNotOnScreen() throws {
        let app = Harness.launch(["-fixture", "labels-multipage.pdf", "-resetHighlights", "-noRedrawAfterHighlight"])
        let probe = Harness.rects(app, "probePoint")
        XCTAssertEqual(probe.count, 1)
        let p = probe[0].split(separator: ",").compactMap { Double($0) }
        Harness.coordinate(app, CGPoint(x: p[0], y: p[1])).press(forDuration: 1.2)
        let menuHighlight = app.menuItems["Highlight"].firstMatch
        XCTAssertTrue(menuHighlight.waitForExistence(timeout: 5))
        menuHighlight.tap()
        XCTAssertTrue(Harness.waitFor(5) { Harness.text(app, "status").hasPrefix("Saved highlight (1") }, Harness.text(app, "status"))
        XCTAssertTrue(Harness.waitFor(5) { Harness.text(app, "selectionInfo").trimmingCharacters(in: .whitespaces).isEmpty })
        var log = ["Control: Highlight without PDFView.setNeedsDisplay() (-noRedrawAfterHighlight), labels-multipage.pdf page index 0",
                   "after Highlight: \(Harness.text(app, "status")); selection dismissed"]
        log += checkOverlayOnScreen(app, name: "control-no-redraw", expectOverlay: false)
        Harness.writeEvidence("ui-redraw-control.txt", log.joined(separator: "\n") + "\n")
    }
}
