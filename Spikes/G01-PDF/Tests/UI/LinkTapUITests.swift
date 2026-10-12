import XCTest

/// Shared helpers for driving the harness.
@MainActor
enum Harness {
    static func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        return app
    }

    static func rects(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 10) -> [String] {
        let element = app.staticTexts[id]
        guard element.waitForExistence(timeout: timeout) else { return [] }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let value = element.label.trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return value.split(separator: ";").map(String.init) }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return []
    }

    static func rect(_ s: Substring) -> CGRect {
        let v = s.split(separator: ",").compactMap { Double($0) }
        return v.count == 4 ? CGRect(x: v[0], y: v[1], width: v[2], height: v[3]) : .null
    }

    /// Window point of a point in the current page's user space, from the map the harness publishes.
    static func windowPoint(_ app: XCUIApplication, page point: CGPoint) -> CGPoint? {
        let parts = rects(app, "pdfViewFrame")
        guard parts.count == 2 else { return nil }
        let m = parts[1].split(separator: ",").compactMap { Double($0) }
        guard m.count == 6 else { return nil }
        let t = CGAffineTransform(a: m[0], b: m[1], c: m[2], d: m[3], tx: m[4], ty: m[5])
        return point.applying(t)
    }

    static func coordinate(_ app: XCUIApplication, _ point: CGPoint) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y))
    }

    static func tap(_ app: XCUIApplication, at point: CGPoint) {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).tap()
    }

    static func text(_ app: XCUIApplication, _ id: String) -> String {
        let e = app.staticTexts[id]
        return e.exists ? e.label : ""
    }

    static func waitFor(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return condition()
    }

    static var evidenceDirectory: URL {
        let env = ProcessInfo.processInfo.environment["SYLVIA_G01_PDF_EVIDENCE_DIR"]
        let url = env.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("g01-pdf-evidence", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func writeEvidence(_ name: String, _ text: String) {
        let env = ProcessInfo.processInfo.environment
        let header = "simulator \(env["SIMULATOR_MODEL_IDENTIFIER"] ?? "?") (\(env["SIMULATOR_DEVICE_NAME"] ?? "?")), runtime \(env["SIMULATOR_RUNTIME_VERSION"] ?? "?")\n"
        try? Data((header + text).utf8).write(to: evidenceDirectory.appendingPathComponent(name), options: .atomic)
    }
}

/// Real taps on the link annotations of actions.pdf in the harness (simulator). Nothing opens without an explicit
/// confirmation; a /Launch link does nothing; the app stays in the foreground.
@MainActor
final class LinkTapUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testLinkTapsAreInterceptedAndNothingOpens() throws {
        let app = Harness.launch(["-fixture", "actions.pdf"])
        let links = Harness.rects(app, "linkFrames")
        XCTAssertEqual(links.count, 4, "four link annotations on page 0: \(links)")
        let frames = links.map { Harness.rect(Substring($0)) }
        var log = ["Link taps in the harness with LinkInterceptor (actions.pdf)", "link frames (window points): \(links)"]
        let before = XCUIScreen.main.screenshot()
        if let png = before.image.pngData() { try? png.write(to: Harness.evidenceDirectory.appendingPathComponent("ui-links-page.png")) }

        // Link A: custom-scheme URI (the canary).
        Harness.tap(app, at: CGPoint(x: frames[0].midX, y: frames[0].midY))
        XCTAssertTrue(Harness.waitFor(5) { Harness.text(app, "linkLog").contains("blocked: scheme sylvia-g01-canary") })
        // Link C: /Launch.
        Harness.tap(app, at: CGPoint(x: frames[2].midX, y: frames[2].midY))
        XCTAssertTrue(Harness.waitFor(5) { Harness.text(app, "linkLog").contains("blocked: scheme file") })
        // Link B: https. Sylvia asks first and the test declines.
        Harness.tap(app, at: CGPoint(x: frames[1].midX, y: frames[1].midY))
        let alert = app.alerts["Open link?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "an https link must ask before opening")
        XCTAssertTrue(alert.staticTexts["https://example.invalid/track"].exists)
        log.append("https link -> alert \"Open link?\" showing https://example.invalid/track; tapped Cancel")
        alert.buttons["Cancel"].tap()
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(app.state, .runningForeground, "no other app may have been opened")
        XCTAssertEqual(Harness.text(app, "openedURLs"), "URLs opened into the harness: none")
        log.append("linkLog: \(Harness.text(app, "linkLog"))")
        log.append("openedURLs: \(Harness.text(app, "openedURLs"))")

        // Link D: internal GoTo navigates to page index 1.
        Harness.tap(app, at: CGPoint(x: frames[3].midX, y: frames[3].midY))
        XCTAssertTrue(Harness.waitFor(5) { Harness.text(app, "page").hasPrefix("Page index 1 of 2") }, Harness.text(app, "page"))
        log.append("GoTo link -> \(Harness.text(app, "page"))")
        log.append("app state after all taps: runningForeground = \(app.state == .runningForeground)")
        Harness.writeEvidence("ui-link-taps.txt", log.joined(separator: "\n") + "\n")
    }

    /// Control: without the interceptor, a real tap on link A makes PDFKit open the canary URL by itself (it arrives
    /// back in the harness). This shows the interceptor is what prevents it.
    func testControlWithoutInterceptorPDFKitOpensTheLink() throws {
        let app = Harness.launch(["-fixture", "actions.pdf", "-noLinkInterceptor"])
        let frames = Harness.rects(app, "linkFrames").map { Harness.rect(Substring($0)) }
        XCTAssertEqual(frames.count, 4)
        Harness.tap(app, at: CGPoint(x: frames[0].midX, y: frames[0].midY))
        let opened = Harness.waitFor(10) { Harness.text(app, "openedURLs").contains("sylvia-g01-canary://link-uri") }
        XCTAssertTrue(opened, "control: expected PDFKit's default to open the canary; got \(Harness.text(app, "openedURLs"))")
        Harness.writeEvidence("ui-link-control.txt", "Control without LinkInterceptor: tap on link A -> \(Harness.text(app, "openedURLs"))\n")
    }
}
