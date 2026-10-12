import XCTest

/// Accessibility on the simulator: the Highlight actions are exposed as accessibility elements, and Xcode's
/// accessibility audit runs on the reader screen. This is not a VoiceOver result (device checklist step 6).
@MainActor
final class AccessibilityUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testHighlightActionsAreExposedAndAuditRuns() throws {
        let app = Harness.launch(["-fixture", "labels-multipage.pdf", "-resetHighlights"])
        XCTAssertTrue(Harness.waitFor(10) { Harness.text(app, "page").hasPrefix("Page index 0 of") }, Harness.text(app, "page"))
        var log = ["Accessibility of the reader screen, labels-multipage.pdf"]

        // Toolbar action: an accessibility button with a spoken label.
        let toolbar = app.buttons["Highlight selection"]
        XCTAssertTrue(toolbar.waitForExistence(timeout: 5), "toolbar Highlight is not an accessibility element")
        XCTAssertTrue(toolbar.isHittable)
        XCTAssertEqual(toolbar.identifier, "highlightButton")
        log.append("toolbar: button, label \"\(toolbar.label)\", hittable \(toolbar.isHittable)")

        // The PDF view is an accessibility element (PDFKit exposes the page text to assistive technologies).
        let pdfView = app.otherElements["pdfView"].exists ? app.otherElements["pdfView"] : app.descendants(matching: .any)["pdfView"]
        XCTAssertTrue(pdfView.exists, "the PDF view is not in the accessibility hierarchy")
        log.append("PDF view: element type \(pdfView.elementType.rawValue), \(pdfView.children(matching: .any).count) accessibility children")

        // Edit-menu action after a selection.
        let probe = try XCTUnwrap(Harness.rects(app, "probePoint").first).split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(probe.count, 2)
        Harness.coordinate(app, CGPoint(x: probe[0], y: probe[1])).press(forDuration: 1.2)
        let menuItem = app.menuItems["Highlight"].firstMatch
        XCTAssertTrue(menuItem.waitForExistence(timeout: 5), "the edit menu must offer Highlight")
        XCTAssertTrue(menuItem.isHittable)
        log.append("edit menu: menu item \"\(menuItem.label)\", hittable \(menuItem.isHittable)")
        menuItem.tap()
        XCTAssertTrue(Harness.waitFor(5) { Harness.text(app, "status").hasPrefix("Saved highlight (1") }, Harness.text(app, "status"))
        let status = app.staticTexts["status"]
        log.append("after Highlight the status line is an accessibility element: \"\(status.label)\"")

        // Xcode's accessibility audit of the reader screen. Every issue is recorded; the test fails on any issue
        // that concerns the PDF view, the Highlight button or the status line.
        var issues: [String] = []
        var blocking: [String] = []
        try app.performAccessibilityAudit { issue in
            let element = issue.element
            let id = element?.identifier ?? ""
            let label = element?.label ?? ""
            let line = "\(Self.name(of: issue.auditType)) on \(element.map { "\($0.elementType.rawValue)" } ?? "-") id \"\(id)\" label \"\(label.prefix(40))\": \(issue.compactDescription)"
            issues.append(line)
            if ["pdfView", "highlightButton", "status"].contains(id) || label == "Highlight selection" { blocking.append(line) }
            return true // recorded here; judged below
        }
        log.append("accessibility audit (all audit types): \(issues.count) issues")
        log += issues.map { "  - " + $0 }
        XCTAssertEqual(blocking, [], "audit issues on the reader's own controls")
        Harness.writeEvidence("ui-accessibility.txt", log.joined(separator: "\n") + "\n")
    }

    static func name(of type: XCUIAccessibilityAuditType) -> String {
        let names: [(XCUIAccessibilityAuditType, String)] = [
            (.contrast, "contrast"), (.elementDetection, "elementDetection"), (.hitRegion, "hitRegion"),
            (.sufficientElementDescription, "sufficientElementDescription"), (.dynamicType, "dynamicType"),
            (.textClipped, "textClipped"), (.trait, "trait"),
        ]
        let matched = names.filter { type.contains($0.0) }.map(\.1)
        return matched.isEmpty ? "auditType \(type.rawValue)" : matched.joined(separator: "+")
    }
}
