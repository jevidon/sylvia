import UIKit
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

    /// The text form fields the harness publishes for the current page: field name -> value.
    static func fieldValues(_ app: XCUIApplication) -> [String: String] {
        var out: [String: String] = [:]
        for pair in text(app, "fieldValues").split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 { out[String(parts[0])] = String(parts[1]) }
        }
        return out
    }

    /// Taps a text field at a page point, types one digit and taps the page outside the field, so editing ends and
    /// PDFKit commits the value. A digit, because the keyboard's autocorrection rewrote typed letters on commit and
    /// not the same way every run ("Secondy" became "Secondhand" or "Seconds"); it leaves a word ending in a digit
    /// alone. The digit is on the numbers layout, reached with the "more" key (up to three tries, each logged by the
    /// caller as a layout switch). On a newly created simulator the
    /// keyboard first shows its one-time "slide to type" introduction over the keys, with a Continue button; it is
    /// dismissed and reported. Returns whether the keyboard appeared, whether the introduction was dismissed, whether
    /// the digit was tapped, and the layout switches it took.
    static func typeDigit(_ digit: String, intoFieldAt field: CGPoint, outside: CGPoint,
                          app: XCUIApplication) -> (keyboard: Bool, introduction: Bool, typed: Bool, layoutSwitches: Int) {
        tap(app, at: field)
        let keyboard = app.keyboards.firstMatch
        guard keyboard.waitForExistence(timeout: 5) else { return (false, false, false, 0) }
        Thread.sleep(forTimeInterval: 1)
        let introductionContinue = app.buttons["Continue"]
        let introduction = introductionContinue.exists && introductionContinue.isHittable
        if introduction {
            introductionContinue.tap()
            Thread.sleep(forTimeInterval: 1)
        }
        var key = keyboard.keys[digit]
        var switches = 0
        while !key.exists, switches < 3 {
            let more = keyboard.keys["more"] // the key that switches between the letters and numbers layouts
            guard more.waitForExistence(timeout: 3) else { break }
            more.tap()
            switches += 1
            key = keyboard.keys[digit]
            _ = key.waitForExistence(timeout: 2)
        }
        guard key.exists else { return (true, introduction, false, switches) }
        key.tap()
        Thread.sleep(forTimeInterval: 0.5)
        tap(app, at: outside)
        _ = waitFor(5) { !app.keyboards.firstMatch.exists }
        return (true, introduction, true, switches)
    }

    static func writeEvidence(_ name: String, _ text: String) {
        let env = ProcessInfo.processInfo.environment
        let header = "simulator \(env["SIMULATOR_MODEL_IDENTIFIER"] ?? "?") (\(env["SIMULATOR_DEVICE_NAME"] ?? "?")), runtime \(env["SIMULATOR_RUNTIME_VERSION"] ?? "?")\n"
        writeEvidenceData(name, Data((header + text).utf8))
    }

    /// A screen image for the evidence directory, under the repository's 2 MB limit for an evidence image.
    static func writeEvidencePNG(_ name: String, _ image: UIImage) {
        guard let png = image.pngData() else { return XCTFail("PNG encoding failed for evidence \(name)") }
        guard png.count < 2_000_000 else { return XCTFail("evidence image \(name) is \(png.count) bytes; the limit is 2 MB") }
        writeEvidenceData(name, png)
    }

    /// Fails the test when the file cannot be written: a silent failure would leave an earlier run's file in place,
    /// to be read as this run's evidence.
    static func writeEvidenceData(_ name: String, _ data: Data) {
        do {
            try data.write(to: evidenceDirectory.appendingPathComponent(name), options: .atomic)
        } catch {
            XCTFail("could not write evidence \(name) to \(evidenceDirectory.path): \(error)")
        }
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
        Harness.writeEvidencePNG("ui-links-page.png", XCUIScreen.main.screenshot().image)

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

    /// The links of actions-chained.pdf (page 0, rows 28 pt apart from y = 700 in page space, each rectangle
    /// [68, y - 6, 420, y + 14]) and what a tap on each does with the interceptor installed and without it ("-" for
    /// link D without it: its https URL would open Safari).
    static let chainedLinks: [(label: String, interceptor: String, noInterceptor: String)] = [
        ("A GoTo + /Next canary", "page 1", "page 1"),
        ("B NextPage + /Next canary", "page 1", "page 1"),
        ("C GoTo + /Next [canary URI, Launch, JavaScript]", "page 1", "page 1"),
        ("D https + /Next canary", "ask", "-"),
        ("E no /A, /AA {U} canary", "blocked", "opens sylvia-g01-canary://aa-mouse-up-only"),
        ("F GoTo page 3 + /AA every trigger", "page 2", "page 2"),
        ("G GoTo + /Next cycle", "page 1", "page 1"),
        ("H no /A, /AA {D, U} canaries", "nothing", "nothing"),
        ("I no /A, /AA {U, D} canaries", "nothing", "nothing"),
        ("J no /A, /AA {D} canary", "nothing", "nothing"),
        ("K no /A, /AA {U, E} canaries", "blocked", "opens sylvia-g01-canary://aa-up-enter-u"),
        ("L canary URI + /Next canary", "blocked", "opens sylvia-g01-canary://uri-first"),
    ]
    /// The three text fields (page-space y of their row; merged with every trigger; separate field dictionary with
    /// the triggers; separate widget with /AA /U only), their values in the file and the digit typed into each.
    static let chainedFields: [(name: String, y: CGFloat, value: String, digit: String)] = [
        ("note", 350, "Typed", "1"), ("second", 322, "Second", "2"), ("third", 294, "Third", "3"),
    ]

    /// Taps one link of actions-chained.pdf in a fresh launch on page index 0 and checks the expected outcome.
    func tapChainedLink(_ index: Int, expect: String, launchArguments: [String], log: inout [String]) throws {
        let label = Self.chainedLinks[index].label
        let app = Harness.launch(["-fixture", "actions-chained.pdf"] + launchArguments)
        XCTAssertTrue(Harness.waitFor(10) { Harness.text(app, "page").hasPrefix("Page index 0 of 3") }, Harness.text(app, "page"))
        let point = try XCTUnwrap(Harness.windowPoint(app, page: CGPoint(x: 244, y: 704 - 28 * CGFloat(index))), "page-to-window map not published")
        Harness.tap(app, at: point)
        let none = "URLs opened into the harness: none"
        switch expect {
        case "ask":
            let alert = app.alerts["Open link?"]
            XCTAssertTrue(alert.waitForExistence(timeout: 5), "\(label): an https link must ask before opening")
            XCTAssertTrue(alert.staticTexts["https://example.invalid/chained"].exists, label)
            alert.buttons["Cancel"].tap()
            XCTAssertEqual(Harness.text(app, "linkLog"), "Links: ask: https://example.invalid/chained", label)
        case "blocked":
            XCTAssertTrue(Harness.waitFor(5) { Harness.text(app, "linkLog") == "Links: blocked: scheme sylvia-g01-canary is not allowed" },
                          "\(label): \(Harness.text(app, "linkLog"))")
        case let opens where opens.hasPrefix("opens "):
            let url = String(opens.dropFirst("opens ".count))
            XCTAssertTrue(Harness.waitFor(10) { Harness.text(app, "openedURLs") == "URLs opened into the harness: \(url)" },
                          "control, \(label): PDFKit's default should open \(url); \(Harness.text(app, "openedURLs"))")
        case "nothing":
            Thread.sleep(forTimeInterval: 1)
        default:
            let page = expect.dropFirst("page ".count)
            XCTAssertTrue(Harness.waitFor(5) { Harness.text(app, "page").hasPrefix("Page index \(page) of 3") }, "\(label): \(Harness.text(app, "page"))")
        }
        Thread.sleep(forTimeInterval: 2)
        if expect.hasPrefix("page") || expect == "nothing" {
            XCTAssertEqual(Harness.text(app, "linkLog"), "", "\(label): nothing may reach the delegate")
        }
        if expect == "nothing" {
            XCTAssertTrue(Harness.text(app, "page").hasPrefix("Page index 0 of 3"), "\(label): \(Harness.text(app, "page"))")
        }
        if !expect.hasPrefix("opens ") {
            XCTAssertEqual(Harness.text(app, "openedURLs"), none, label)
        } else {
            // Exactly the presented URL: never the /Next URL or the other /AA trigger.
            XCTAssertEqual(Harness.text(app, "openedURLs"), "URLs opened into the harness: \(expect.dropFirst("opens ".count))", label)
        }
        XCTAssertEqual(app.state, .runningForeground, "\(label): no other app may have been opened")
        log.append("\(label): tap at window \(point.rounded) -> \(Harness.text(app, "page")); "
                   + "linkLog \"\(Harness.text(app, "linkLog"))\"; \(Harness.text(app, "openedURLs")); foreground \(app.state == .runningForeground)")
        app.terminate()
    }

    /// Taps each text field of actions-chained.pdf, types a digit and taps outside it, in one launch; nothing may
    /// reach the delegate or open, and each field must then hold its value with the digit appended.
    func typeIntoChainedFields(launchArguments: [String], log: inout [String]) throws -> XCUIApplication {
        let app = Harness.launch(["-fixture", "actions-chained.pdf"] + launchArguments)
        XCTAssertTrue(Harness.waitFor(10) { Harness.text(app, "page").hasPrefix("Page index 0 of 3") }, Harness.text(app, "page"))
        XCTAssertTrue(Harness.waitFor(5) { Harness.fieldValues(app).count == 3 }, Harness.text(app, "fieldValues"))
        XCTAssertEqual(Harness.fieldValues(app), Dictionary(uniqueKeysWithValues: Self.chainedFields.map { ($0.name, $0.value) }))
        let outside = try XCTUnwrap(Harness.windowPoint(app, page: CGPoint(x: 300, y: 150)))
        for field in Self.chainedFields {
            let point = try XCTUnwrap(Harness.windowPoint(app, page: CGPoint(x: 280, y: field.y + 4)))
            let result = Harness.typeDigit(field.digit, intoFieldAt: point, outside: outside, app: app)
            XCTAssertTrue(result.keyboard, "\(field.name): tapping the text field should start editing it")
            XCTAssertTrue(result.typed, "\(field.name): the keyboard has the digit key")
            let expected = field.value + field.digit
            XCTAssertTrue(Harness.waitFor(5) { Harness.fieldValues(app)[field.name] == expected },
                          "\(field.name): the typed digit must reach the field; values \(Harness.text(app, "fieldValues"))")
            Thread.sleep(forTimeInterval: 1)
            XCTAssertEqual(Harness.text(app, "openedURLs"), "URLs opened into the harness: none", field.name)
            XCTAssertEqual(Harness.text(app, "linkLog"), "", "\(field.name): no field action reaches the delegate")
            XCTAssertEqual(app.state, .runningForeground)
            log.append("field \(field.name): tap at window \(point.rounded), keyboard \(result.keyboard), "
                       + (result.introduction ? "keyboard's slide-to-type introduction dismissed (Continue), " : "")
                       + "typed \"\(field.digit)\" (\(result.layoutSwitches) switch(es) to the numbers layout), "
                       + "tapped outside at window \(outside.rounded) -> value \"\(Harness.fieldValues(app)[field.name] ?? "?")\"; "
                       + "linkLog \"\(Harness.text(app, "linkLog"))\"; \(Harness.text(app, "openedURLs")); foreground \(app.state == .runningForeground)")
        }
        return app
    }

    /// Real taps on actions-chained.pdf, where every URI and JavaScript action aims at the canary scheme except link D's
    /// https URI (/Next chains, links without /A whose /AA holds mouse-up, mouse-down or both, a link with every /AA
    /// trigger, three text fields with /AA in the widget, the field dictionary or both, document /AA close, save and
    /// print triggers). Each link is tapped in a fresh launch on page index 0. Opening the file also exercises the
    /// /OpenAction and page 0's /AA /O, but the harness itself shows page 0 after opening, so whether those GoTo actions
    /// to page index 2 run is checked by `ChainedActionTests`, not here. Then each field is tapped, given a digit and
    /// left, and the file is closed by opening another one from the Open menu.
    /// Nothing opens; only the https link asks; the presented /AA canaries (links E and K) and link L's canary are
    /// blocked by the policy; links H, I and J, the fields and the close reach nothing; the app stays in the foreground.
    func testChainedAndAdditionalActionTaps() throws {
        var log = ["Real taps on actions-chained.pdf in the harness with LinkInterceptor, one fresh launch per link"]
        for (i, link) in Self.chainedLinks.enumerated() {
            try tapChainedLink(i, expect: link.interceptor, launchArguments: [], log: &log)
        }
        // The fields: a tap (/AA /D, /U, /Fo), a typed digit (/AA /K), a tap outside (/AA /Bl, /V, /F, /C).
        let app = try typeIntoChainedFields(launchArguments: [], log: &log)

        // Close the file as the reader does when another one is opened (Open menu): the document leaves the view.
        app.buttons["openMenu"].tap()
        let next = "labels-multipage.pdf"
        // The menu's entries are exposed as buttons or as menu items depending on how the system presents the menu.
        let asButton = app.buttons[next]
        let asMenuItem = app.menuItems[next]
        XCTAssertTrue(Harness.waitFor(5) { asButton.exists || asMenuItem.exists }, "the Open menu lists \(next)")
        (asButton.exists ? asButton : asMenuItem).tap()
        XCTAssertTrue(Harness.waitFor(10) { Harness.text(app, "page").hasPrefix("Page index 0 of 8") }, Harness.text(app, "page"))
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(Harness.text(app, "openedURLs"), "URLs opened into the harness: none", "closing the file opens nothing")
        XCTAssertEqual(Harness.text(app, "linkLog"), "", "closing the file reaches nothing")
        XCTAssertEqual(app.state, .runningForeground)
        log.append("closed by opening \(next) from the Open menu -> \(Harness.text(app, "page")); linkLog \"\(Harness.text(app, "linkLog"))\"; "
                   + "\(Harness.text(app, "openedURLs")); foreground \(app.state == .runningForeground)")
        Harness.writeEvidence("ui-link-taps-chained.txt", log.joined(separator: "\n") + "\n")
    }

    /// Control for the test above: the same real taps without the interceptor (`-noLinkInterceptor`, PDFKit's default),
    /// except link D, whose https URL would open Safari. PDFKit itself runs nothing named by /Next and nothing for
    /// links H, I and J, and opens exactly the presented URL of links E, K and L (the canary comes back to the harness):
    /// those taps are live without the delegate. Tapping, typing into and leaving the three fields opens nothing
    /// without the delegate too: a tap on field three starts editing rather than performing the widget's presented
    /// /AA /U action.
    func testChainedTapsWithoutInterceptorControl() throws {
        var log = ["Control: real taps on actions-chained.pdf in the harness without LinkInterceptor (-noLinkInterceptor), one fresh launch per link"]
        for (i, link) in Self.chainedLinks.enumerated() where link.noInterceptor != "-" {
            try tapChainedLink(i, expect: link.noInterceptor, launchArguments: ["-noLinkInterceptor"], log: &log)
        }
        log.append("D https + /Next canary: not tapped without the interceptor (its https URL would open Safari)")
        let app = try typeIntoChainedFields(launchArguments: ["-noLinkInterceptor"], log: &log)
        app.terminate()
        Harness.writeEvidence("ui-link-taps-chained-control.txt", log.joined(separator: "\n") + "\n")
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
