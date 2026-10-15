import UIKit
import XCTest

/// Selections made with simulated touches in the harness (simulator): a long press selects a word, then the end
/// selection handle is dragged down across lines, and from the left column into the right one. This reduces the risk
/// before the finger checks on a device (device checklist steps 1-2); it is not a judgement of how selection feels.
@MainActor
final class SelectionGestureUITests: ScreenCheckTestCase {
    /// Long-presses at a page point, then drags the end handle of the resulting selection towards another page
    /// point, as a person would: if the selection end lands on a different line than aimed for (UIKit offsets the
    /// effective point of a handle drag from the touch), the next drag corrects by the observed vertical miss. At most
    /// three drags; every one is logged. Returns the published selection shape before and after.
    func selectThenDragEndHandle(_ app: XCUIApplication, name: String, pressAt start: CGPoint, dragTo end: CGPoint,
                                 expectedLines: Int, log: inout [String]) throws -> (before: String, after: String) {
        let press = try XCTUnwrap(Harness.windowPoint(app, page: start), "page-to-window map not published")
        Harness.coordinate(app, press).press(forDuration: 1.2)
        let before = Harness.rects(app, "selectionInfo").joined(separator: ";")
        saveScreen("\(name)-1-long-press")
        XCTAssertTrue(before.contains("lines 1"), "the long press should select one word: \(before)")
        log.append("long press at page \(start) = window \(press.rounded); selection: \(before)")
        let aim = try XCTUnwrap(Harness.windowPoint(app, page: end))
        var target = aim
        var after = before
        for attempt in 1...3 {
            let lines = Harness.rects(app, "selectionFrames").map { Harness.rect(Substring($0)) }
            let last = try XCTUnwrap(lines.last, "no selection frames published")
            // The end handle sits at the trailing edge of the last selected line.
            let handle = CGPoint(x: last.maxX, y: last.midY)
            let shapeBefore = after
            Harness.coordinate(app, handle).press(forDuration: 0.3, thenDragTo: Harness.coordinate(app, target),
                                                   withVelocity: 60, thenHoldForDuration: 0.5)
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                after = Harness.rects(app, "selectionInfo", timeout: 1).joined(separator: ";")
                if after != shapeBefore { break }
                Thread.sleep(forTimeInterval: 0.2)
            }
            let landed = Harness.rects(app, "selectionFrames").map { Harness.rect(Substring($0)) }.last ?? .null
            log.append("drag \(attempt): end handle from window \(handle.rounded) to \(target.rounded) (aim: page \(end) = window \(aim.rounded)); "
                       + "selection: \(after); last line now \(landed.integral)")
            if after.contains("lines \(expectedLines);") || landed.isNull { break }
            target.y += aim.y - landed.midY
        }
        saveScreen("\(name)-2-after-drag")
        print(log.joined(separator: "\n"))
        return (before, after)
    }

    /// Keeps a screenshot in the test result bundle (not in the evidence directory, to keep it small).
    func saveScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func highlightAndCheck(_ app: XCUIApplication, name: String, expectedLines: Int, log: inout [String]) {
        let button = app.buttons["highlightButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        XCTAssertTrue(Harness.waitFor(5) { Harness.text(app, "status").hasPrefix("Saved highlight (1") }, Harness.text(app, "status"))
        log.append("toolbar Highlight -> \(Harness.text(app, "status"))")
        XCTAssertEqual(Harness.rects(app, "overlayFrames").count, expectedLines, "one overlay line per selected line")
        log += checkOverlayOnScreen(app, name: name, minimumChecked: expectedLines)
    }

    /// labels-multipage.pdf page index 0: long press on a word in the first body line (page point 200,703), drag the
    /// end handle to the third line (page point 300,673; lines are 15 pt apart).
    func testDragEndHandleAcrossThreeLines() throws {
        let app = Harness.launch(["-fixture", "labels-multipage.pdf", "-resetHighlights"])
        XCTAssertTrue(Harness.waitFor(10) { Harness.text(app, "page").hasPrefix("Page index 0 of") }, Harness.text(app, "page"))
        var log = ["Touch selection across lines, labels-multipage.pdf page index 0 (simulated touches, XCUICoordinate)"]
        let (_, after) = try selectThenDragEndHandle(app, name: "drag-three-lines", pressAt: CGPoint(x: 200, y: 703), dragTo: CGPoint(x: 300, y: 673), expectedLines: 3, log: &log)
        XCTAssertTrue(after.hasPrefix("pages 0; lines 3;"), "the drag should extend the selection to three lines: \(after)")
        highlightAndCheck(app, name: "drag-three-lines", expectedLines: 3, log: &log)
        Harness.writeEvidence("ui-drag-selection-lines.txt", log.joined(separator: "\n") + "\n")
    }

    /// two-column.pdf: long press on "spines" in the last line of the left column (page point 155,568), drag the end
    /// handle into the second line of the right column (page point 400,688).
    func testDragEndHandleFromLeftColumnIntoRightColumn() throws {
        let app = Harness.launch(["-fixture", "two-column.pdf", "-resetHighlights"])
        XCTAssertTrue(Harness.waitFor(10) { Harness.text(app, "page").hasPrefix("Page index 0 of") }, Harness.text(app, "page"))
        var log = ["Touch selection across columns, two-column.pdf (simulated touches, XCUICoordinate)"]
        let (_, after) = try selectThenDragEndHandle(app, name: "drag-cross-column", pressAt: CGPoint(x: 155, y: 568), dragTo: CGPoint(x: 400, y: 688), expectedLines: 3, log: &log)
        // Reading order: the rest of the left column's last line, then the right column's first two lines.
        XCTAssertTrue(after.hasPrefix("pages 0; lines 3;"), "the drag should select into the right column: \(after)")
        let frames = Harness.rects(app, "selectionFrames").map { Harness.rect(Substring($0)) }
        let left = try XCTUnwrap(Harness.windowPoint(app, page: CGPoint(x: 72, y: 0))).x
        let right = try XCTUnwrap(Harness.windowPoint(app, page: CGPoint(x: 324, y: 0))).x
        XCTAssertEqual(frames.count, 3)
        if frames.count == 3 {
            XCTAssertLessThan(frames[0].minX, right - 20, "first line is in the left column")
            XCTAssertEqual(frames[1].minX, right, accuracy: 3, "second line starts the right column")
            XCTAssertEqual(frames[2].minX, right, accuracy: 3, "third line is in the right column")
        }
        log.append("line frames \(frames.map(\.integral)); left column starts at window x \(Int(left)), right column at \(Int(right))")
        highlightAndCheck(app, name: "drag-cross-column", expectedLines: 3, log: &log)
        Harness.writeEvidence("ui-drag-selection-columns.txt", log.joined(separator: "\n") + "\n")
    }
}

extension SelectionGestureUITests {
    /// The affine map from the current page's user space to window points that the harness publishes.
    func pageToWindow(_ app: XCUIApplication) throws -> CGAffineTransform {
        let parts = Harness.rects(app, "pdfViewFrame")
        let values = parts.count == 2 ? parts[1].split(separator: ",").compactMap { Double($0) } : []
        let m = try XCTUnwrap(values.count == 6 ? values : nil, "page-to-window map not published: \(parts)")
        return CGAffineTransform(a: m[0], b: m[1], c: m[2], d: m[3], tx: m[4], ty: m[5])
    }

    /// `selectThenDragEndHandle` for any page rotation: the published selection line frames (window points) are
    /// mapped back to page space, the end handle is taken at the trailing end of the last line in page space (where
    /// the text ends, whichever way the page is turned on screen), and a miss is corrected along the page's own y
    /// axis. Every drag is logged.
    func selectThenDragEndHandleInPageSpace(_ app: XCUIApplication, name: String, pressAt start: CGPoint, dragTo end: CGPoint,
                                            expectedLines: Int, log: inout [String]) throws -> String {
        let map = try pageToWindow(app)
        let press = start.applying(map)
        Harness.coordinate(app, press).press(forDuration: 1.2)
        var after = Harness.rects(app, "selectionInfo").joined(separator: ";")
        saveScreen("\(name)-1-long-press")
        XCTAssertTrue(after.contains("lines 1"), "the long press should select one word: \(after)")
        log.append("long press at page \(start) = window \(press.rounded); selection: \(after)")
        var aimY = end.y
        for attempt in 1...3 {
            let map = try pageToWindow(app)
            let inverse = map.inverted()
            let lines = Harness.rects(app, "selectionFrames").map { Harness.rect(Substring($0)).applying(inverse) }
            let last = try XCTUnwrap(lines.last, "no selection frames published")
            let handle = CGPoint(x: last.maxX, y: last.midY).applying(map)
            let target = CGPoint(x: end.x, y: aimY).applying(map)
            let shapeBefore = after
            Harness.coordinate(app, handle).press(forDuration: 0.3, thenDragTo: Harness.coordinate(app, target),
                                                   withVelocity: 60, thenHoldForDuration: 0.5)
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                after = Harness.rects(app, "selectionInfo", timeout: 1).joined(separator: ";")
                if after != shapeBefore { break }
                Thread.sleep(forTimeInterval: 0.2)
            }
            let inverseAfter = try pageToWindow(app).inverted()
            let landed = Harness.rects(app, "selectionFrames").map { Harness.rect(Substring($0)).applying(inverseAfter) }.last ?? .null
            log.append("drag \(attempt): end handle from window \(handle.rounded) (page \(CGPoint(x: last.maxX, y: last.midY).rounded)) "
                       + "to window \(target.rounded) (page \(CGPoint(x: end.x, y: aimY).rounded)); selection: \(after); "
                       + "last line now page \(landed.integral)")
            if after.contains("lines \(expectedLines);") || landed.isNull { break }
            aimY += end.y - landed.midY
        }
        saveScreen("\(name)-2-after-drag")
        return after
    }

    /// rotated.pdf, pages turned 90, 180 and 270 degrees and 270 with an offset CropBox (device checklist step 3):
    /// long press on a word in the first body line, drag the end handle into the second line, Highlight, and check
    /// the overlay on screen at 2.5 x the fit scale. One fresh launch per page.
    func testDragEndHandleOnRotatedPages() throws {
        // Physical page index, rotation, the long-press point on the first line and the drag target on the second
        // (page space; lines are 15 pt apart, from y = 700 at x = 72, or y = 640 at x = 40 on page 5).
        let pages: [(index: Int, rotation: Int, press: CGPoint, drag: CGPoint)] = [
            (1, 90, CGPoint(x: 200, y: 703), CGPoint(x: 300, y: 688)),
            (2, 180, CGPoint(x: 200, y: 703), CGPoint(x: 300, y: 688)),
            (3, 270, CGPoint(x: 200, y: 703), CGPoint(x: 300, y: 688)),
            (5, 270, CGPoint(x: 150, y: 643), CGPoint(x: 250, y: 628)),
        ]
        var log = ["Touch selection on rotated pages, rotated.pdf (simulated touches, XCUICoordinate; one launch per page)"]
        // Written however the test ends, so a failed run still shows every drag and pixel measurement.
        defer { Harness.writeEvidence("ui-drag-selection-rotated.txt", log.joined(separator: "\n") + "\n") }
        for page in pages {
            let app = Harness.launch(["-fixture", "rotated.pdf", "-resetHighlights", "-startPage", "\(page.index)"])
            // The harness publishes the touch geometry for the -startPage page; PDFView's current page (the status
            // line) can be the one before it for the last page, which cannot scroll to the top of the view. The
            // selection's page is asserted after the drag.
            XCTAssertTrue(Harness.waitFor(10) { Harness.text(app, "page").hasPrefix("Page index ") }, Harness.text(app, "page"))
            Thread.sleep(forTimeInterval: 1)
            log.append("page index \(page.index) (/Rotate \(page.rotation)); status line: \(Harness.text(app, "page"))")
            let after = try selectThenDragEndHandleInPageSpace(app, name: "drag-rotate-\(page.index)", pressAt: page.press,
                                                                dragTo: page.drag, expectedLines: 2, log: &log)
            XCTAssertTrue(after.hasPrefix("pages \(page.index); lines 2;"), "page \(page.index): the drag should extend the selection to two lines: \(after)")
            // Saved and drawn, then checked on screen at 2.5 x the fit scale (the harness's Zoom button scrolls to
            // the highlight). At fit scale these pages are drawn at about half size, so the underline is 0.7 pt
            // (2 px) and straddles pixel rows: antialiasing lightens it beyond the check's tolerance (page 2 measured
            // (153,105,45) at its darkest, 29 from #8A5410). At 2.5 x it is wide enough to measure.
            let button = app.buttons["highlightButton"]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
            XCTAssertTrue(Harness.waitFor(5) { Harness.text(app, "status").hasPrefix("Saved highlight (1") }, Harness.text(app, "status"))
            log.append("toolbar Highlight -> \(Harness.text(app, "status"))")
            XCTAssertEqual(Harness.rects(app, "overlayFrames").count, 2, "one overlay line per selected line")
            app.buttons["zoomButton"].tap()
            Thread.sleep(forTimeInterval: 1)
            log.append("Zoom (2.5 x fit scale, scrolled to the highlight; geometry published for page index \(page.index)):")
            log += checkOverlayOnScreen(app, name: "drag-rotate-\(page.index)", minimumChecked: 2)
            app.terminate()
        }
    }
}

extension CGPoint {
    var rounded: CGPoint { CGPoint(x: (x * 10).rounded() / 10, y: (y * 10).rounded() / 10) }
}
