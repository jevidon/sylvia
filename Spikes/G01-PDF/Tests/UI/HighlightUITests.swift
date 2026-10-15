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

    /// Plan 9.4 "survives an extraction-cache rebuild", in the harness: a stored record whose page text changed since
    /// capture (`-seedDrift`: digest mismatch, range 5 scalars later, stored rectangles 0.05 of the page lower) is
    /// relocated on open, drawn at the passage's current position (the same overlay frames as an undrifted record of
    /// the same passage, not the stale ones), and its new location is saved: after a relaunch it restores exactly.
    func testRelocatedHighlightIsDrawnAndSaved() throws {
        // Reference: the multiline passage (labels-multipage.pdf page index 3, scalars [48, 193)) stored undrifted.
        var app = Harness.launch(["-fixture", "labels-multipage.pdf", "-resetHighlights", "-seedRange", "3:48:193"])
        XCTAssertTrue(Harness.waitFor(10) { Harness.text(app, "status") == "Highlights: 1 stored, 1 restored exactly" }, Harness.text(app, "status"))
        XCTAssertTrue(Harness.waitFor(10) { Harness.text(app, "page").hasPrefix("Page index 3 of") }, Harness.text(app, "page"))
        Thread.sleep(forTimeInterval: 1)
        let reference = Harness.rects(app, "overlayFrames")
        XCTAssertEqual(reference.count, 3, "three overlay lines: \(reference)")
        var log = ["Relocated highlight in the harness, labels-multipage.pdf page index 3, scalars [48, 193)",
                   "reference (undrifted record): \(Harness.text(app, "status")); overlay frames \(reference)"]
        app.terminate()

        // The same passage stored as if the page text had changed since capture.
        app = Harness.launch(["-fixture", "labels-multipage.pdf", "-resetHighlights", "-seedRange", "3:48:193", "-seedDrift"])
        let relocatedStatus = "Highlights: 1 stored, 0 restored exactly, 1 relocated (new location saved)"
        XCTAssertTrue(Harness.waitFor(10) { Harness.text(app, "status") == relocatedStatus }, Harness.text(app, "status"))
        XCTAssertTrue(Harness.waitFor(10) { Harness.text(app, "page").hasPrefix("Page index 3 of") }, Harness.text(app, "page"))
        Thread.sleep(forTimeInterval: 1)
        let relocated = Harness.rects(app, "overlayFrames")
        log.append("drifted record (-seedDrift): \(Harness.text(app, "status")); overlay frames \(relocated)")
        XCTAssertEqual(relocated, reference, "the relocated highlight is drawn where the passage is now, not at its stale rectangles")
        log += checkOverlayOnScreen(app, name: "relocated-highlight", minimumChecked: 3)
        app.terminate()

        // Relaunch without seeding: the saved new location restores exactly.
        app = Harness.launch(["-fixture", "labels-multipage.pdf"])
        XCTAssertTrue(Harness.waitFor(10) { Harness.text(app, "status") == "Highlights: 1 stored, 1 restored exactly" }, Harness.text(app, "status"))
        app.buttons["revealButton"].tap()
        XCTAssertTrue(Harness.waitFor(10) { Harness.text(app, "page").hasPrefix("Page index 3 of") }, Harness.text(app, "page"))
        Thread.sleep(forTimeInterval: 1)
        let afterRelaunch = Harness.rects(app, "overlayFrames")
        log.append("after relaunch: \(Harness.text(app, "status")); overlay frames \(afterRelaunch)")
        XCTAssertEqual(afterRelaunch.count, 3, "three overlay lines after relaunch: \(afterRelaunch)")
        log += checkOverlayOnScreen(app, name: "relocated-highlight-after-relaunch", minimumChecked: 3)
        Harness.writeEvidence("ui-relocated-highlight.txt", log.joined(separator: "\n") + "\n")
    }

    /// Plan 9.4 "survives relaunch" for a selection that ends at a line break: a long press on the last word of a
    /// line selects it with a range that PDFKit reports including the line break (`LineEndSelectionTests`). The
    /// harness saves the highlight, draws it at once, and after a relaunch restores it exactly and draws it again.
    func testLineEndWordHighlightSurvivesRelaunch() throws {
        var app = Harness.launch(["-fixture", "labels-multipage.pdf", "-resetHighlights"])
        XCTAssertTrue(Harness.waitFor(10) { Harness.text(app, "page").hasPrefix("Page index 0 of") }, Harness.text(app, "page"))
        let probe = Harness.rects(app, "lineEndProbePoint")
        XCTAssertEqual(probe.count, 1, "the harness publishes a point on the last character of the first body line")
        let p = try XCTUnwrap(probe.first).split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(p.count, 2)
        Harness.coordinate(app, CGPoint(x: p[0], y: p[1])).press(forDuration: 1.2)
        var log = ["Long press on the last word of the first body line (labels-multipage.pdf page index 0) -> Highlight -> relaunch"]
        let menuHighlight = app.menuItems["Highlight"].firstMatch
        XCTAssertTrue(menuHighlight.waitForExistence(timeout: 5), "the selection edit menu must offer Highlight")
        let selection = Harness.rects(app, "selectionInfo").joined(separator: ";")
        XCTAssertTrue(selection.hasPrefix("pages 0; lines 1;"), selection)
        log.append("selection: \(selection)")
        menuHighlight.tap()
        XCTAssertTrue(Harness.waitFor(5) { Harness.text(app, "status").hasPrefix("Saved highlight (1") }, Harness.text(app, "status"))
        log.append("after Highlight: \(Harness.text(app, "status"))")
        log += checkOverlayOnScreen(app, name: "line-end-highlight-before-relaunch", saveImage: false)
        app.terminate()

        app = Harness.launch(["-fixture", "labels-multipage.pdf"])
        XCTAssertTrue(Harness.waitFor(10) { Harness.text(app, "status") == "Highlights: 1 stored, 1 restored exactly" }, Harness.text(app, "status"))
        log.append("after relaunch: \(Harness.text(app, "status"))")
        log += checkOverlayOnScreen(app, name: "line-end-highlight-after-relaunch", saveImage: false)
        Harness.writeEvidence("ui-line-end-highlight-relaunch.txt", log.joined(separator: "\n") + "\n")
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
