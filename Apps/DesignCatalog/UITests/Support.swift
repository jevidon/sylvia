import XCTest

/// Shared helpers for the design catalog's UI smoke tests (G0.6 part 3).
///
/// Every launch turns the layout audit on (`-SylviaLayoutAudit YES`), so each screen exposes an
/// element "layoutAudit.<screen>" whose value reads "<t> truncated, <o> outside of <n> texts" (the T51 proxy of
/// ADR-0013 Section 9, measured in a real window). Evidence goes to `SYLVIA_EVIDENCE_DIR`, passed
/// as `TEST_RUNNER_SYLVIA_EVIDENCE_DIR` by `Scripts/ci.d/21-design-catalog.sh`.
enum Variant: String, CaseIterable {
    case light, dark, ax5

    var arguments: [String] {
        switch self {
        case .light: ["-SylviaAppearance", "light"]
        case .dark: ["-SylviaAppearance", "dark"]
        // The largest accessibility text size, through UIKit's own launch argument (the same trait
        // the Settings app changes), in light.
        case .ax5: ["-SylviaAppearance", "light",
                    "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
    }
}

/// One screen of the prototype: how to open it, the audit name it reports, and labels that must
/// be on it.
struct Visit {
    let screen: String
    let audit: String
    let labels: [String]
    /// Values (text field contents) that must be on it.
    var values: [String] = []
    /// A button whose whole label matches this regular expression must be on it (for labels that
    /// a plain "contains" check cannot pin down, such as "Saved 14:02").
    var buttonPattern: String? = nil
    /// An element (exact label) that must be reachable by scrolling: after upward drags its whole
    /// frame lies inside the window, below the status bar and above the mini-player (on screens
    /// that show it), and it is hittable. When a drag was needed, a second screenshot
    /// "<screen>.reached" shows it.
    var reach: String? = nil
    /// True on the area screens and the screens pushed inside them, where the mini-player floats
    /// above the tab bar; false for onboarding, under the full-screen reader and player, and in sheets.
    var showsMiniPlayer: Bool {
        ["library", "work.onDevice", "work.recordOnly", "work.notOnDevice", "inbox", "inbox.resolve", "inbox.review",
         "thoughts", "storage", "settings"].contains(screen)
    }
}

struct AuditReading: Equatable {
    let truncated: Int
    let outside: Int
    let texts: Int
}

struct ScreenResult {
    let visit: Visit
    let variant: Variant
    let truncated: Int
    let outside: Int
    let texts: Int
    let screenshot: String
    /// "Resolve after 2 drags" when the visit required an element to be reachable.
    var reached: String = ""
}

@MainActor
enum Harness {
    static var evidenceDirectory: URL? {
        ProcessInfo.processInfo.environment["SYLVIA_EVIDENCE_DIR"].map { URL(fileURLWithPath: $0) }
    }

    /// The evidence folder and report name for this simulator: "iphone" (iPhone 17) unless the CI
    /// drop-in passes another (`TEST_RUNNER_SYLVIA_DEVICE_FOLDER=iphone-se`).
    static var deviceFolder: String {
        ProcessInfo.processInfo.environment["SYLVIA_DEVICE_FOLDER"] ?? "iphone"
    }

    /// Folder for catalog-page screenshots on this simulator.
    static var catalogFolder: String {
        deviceFolder == "iphone" ? "screens/catalog" : "screens/\(deviceFolder)/catalog"
    }

    /// "simulator (iPhone 17; model iPhone18,3, iOS 26.5)": the device type named by the CI drop-in,
    /// plus the model identifier and runtime the simulator itself reports.
    static func simulatorEnvironment(defaultLabel: String) -> String {
        let env = ProcessInfo.processInfo.environment
        let label = env["SYLVIA_DEVICE_LABEL"] ?? defaultLabel
        let model = env["SIMULATOR_MODEL_IDENTIFIER"] ?? "unknown model"
        let runtime = env["SIMULATOR_RUNTIME_VERSION"].map { "iOS \($0)" } ?? "unknown runtime"
        return "simulator (\(label); model \(model), \(runtime))"
    }

    static func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + ["-SylviaLayoutAudit", "YES"]
        app.launch()
        return app
    }

    /// Waits for the audit element of `name` and returns its reading once it reports at least one
    /// text and two consecutive readings agree (layout has settled).
    static func audit(_ app: XCUIApplication, name: String, file: StaticString = #filePath,
                      line: UInt = #line) -> AuditReading? {
        let element = app.descendants(matching: .any)["layoutAudit.\(name)"]
        guard element.waitForExistence(timeout: 20) else {
            XCTFail("no layout audit for screen \(name)", file: file, line: line)
            return nil
        }
        var previous: AuditReading?
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if let reading = parse(element.value as? String), reading.texts > 0 {
                if let previous, previous == reading { return reading }
                previous = reading
            }
            Thread.sleep(forTimeInterval: 0.7)
        }
        XCTFail("layout audit for \(name) never settled: \(String(describing: element.value))", file: file, line: line)
        return nil
    }

    /// Requires no truncated text and no text outside the window; a failure names each text's role
    /// and frame (from the screen's "layoutAuditDetail.<name>" element).
    static func requireCleanAudit(_ app: XCUIApplication, _ reading: AuditReading, name: String, context: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        guard reading.truncated != 0 || reading.outside != 0 else { return }
        let element = app.descendants(matching: .any)["layoutAuditDetail.\(name)"]
        let detail = element.exists ? (element.value as? String ?? "") : "(no detail element)"
        XCTFail("\(context): \(reading.truncated) truncated, \(reading.outside) outside the window: \(detail)",
                file: file, line: line)
    }

    /// Parses "3 truncated, 1 outside of 57 texts".
    static func parse(_ value: String?) -> AuditReading? {
        guard let parts = value?.split(separator: " "), parts.count == 7, parts[1] == "truncated,",
              parts[3] == "outside", let t = Int(parts[0]), let o = Int(parts[2]), let n = Int(parts[5])
        else { return nil }
        return AuditReading(truncated: t, outside: o, texts: n)
    }

    /// Requires an element whose label (or value, for states such as "Highlighted") contains `label`.
    static func requireLabel(_ app: XCUIApplication, _ label: String, context: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let query = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", label, label))
        XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 10), "\(context): no element labelled \"\(label)\"",
                      file: file, line: line)
    }

    static func requireValue(_ app: XCUIApplication, _ value: String, context: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let query = app.descendants(matching: .any).matching(NSPredicate(format: "value CONTAINS %@", value))
        XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 10), "\(context): no element with value \"\(value)\"",
                      file: file, line: line)
    }

    /// Drags the upper part of the screen upward until the element labelled exactly `label` is
    /// wholly visible: its whole frame inside the window, below the status bar, above the
    /// mini-player when `showsMiniPlayer` (the floating player covers the content under it), and
    /// hittable. `isHittable` alone is not enough: XCUITest reports an element hittable when any
    /// part of it is visible, and an earlier version of this check passed with the Resolve button
    /// mostly under the mini-player. Returns the number of drags needed, or nil (with a failure).
    static func reach(_ app: XCUIApplication, _ label: String, showsMiniPlayer: Bool, context: String,
                      file: StaticString = #filePath, line: UInt = #line) -> Int? {
        let predicate = NSPredicate(format: "label == %@", label)
        let matches = app.descendants(matching: .any).matching(predicate)
        guard matches.firstMatch.waitForExistence(timeout: 10) else {
            XCTFail("\(context): no element labelled exactly \"\(label)\"", file: file, line: line)
            return nil
        }
        let window = app.windows.firstMatch.frame
        // The status bar: 54-62 pt on Face ID iPhones, 20 pt on the iPhone SE, 24 pt on iPad.
        let top = window.minY + (window.height > 700 ? 62 : 20)
        let miniPlayer = app.descendants(matching: .any)["miniPlayer"]
        var bottom = window.maxY
        if showsMiniPlayer {
            guard miniPlayer.waitForExistence(timeout: 5) else {
                XCTFail("\(context): the mini-player is not on this screen", file: file, line: line)
                return nil
            }
            bottom = miniPlayer.frame.minY
        }
        let band = bottom - top
        // The element to bring into view: not the mini-player's own copy of the label (the
        // mini-player stays in the accessibility tree under the full-screen player, and its capture
        // control has the same label as the player's).
        func target() -> XCUIElement? {
            let inMiniPlayer = miniPlayer.exists
                ? Set(miniPlayer.descendants(matching: .any).matching(predicate).allElementsBoundByIndex.map { "\($0.frame)" })
                : []
            return matches.allElementsBoundByIndex.first { !inMiniPlayer.contains("\($0.frame)") }
        }
        // Wholly inside the band and hittable. An element taller than the band (a long quotation
        // at AX5) counts once its bottom edge is inside the band, that is, once the end of it has
        // scrolled clear of the mini-player.
        func whollyVisible(_ f: CGRect) -> Bool {
            f.maxY <= bottom + 0.5 && f.maxY >= top && (f.minY >= top - 0.5 || f.height > band)
                && f.minX >= window.minX - 0.5 && f.maxX <= window.maxX + 0.5
        }
        // Drags in the upper part of the screen, above the mini-player (at AX5 on the iPhone SE it
        // starts at about 34% of the screen height). Short, slow drags held at the end so the
        // scroll view does not coast move the content about 8% of the screen, less than the
        // band's slack, so the element cannot jump over the band; a fling is used only while the
        // element is more than a screen away.
        func drag(from: CGFloat, to: CGFloat, fling: Bool = false) {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to))
            if fling {
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
            } else {
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
            }
        }
        let maximum = 150
        var last = CGRect.null
        for drags in 0...maximum {
            guard let element = target() else {
                XCTFail("\(context): only the mini-player carries \"\(label)\"", file: file, line: line)
                return nil
            }
            let f = element.frame
            last = f
            if whollyVisible(f) && element.isHittable { return drags }
            let tooLow = f.maxY > bottom
            if tooLow && f.minY > window.maxY + window.height {
                drag(from: 0.30, to: 0.04, fling: true)
            } else if tooLow {
                drag(from: 0.26, to: 0.18)
            } else {
                drag(from: 0.18, to: 0.26)
            }
        }
        XCTFail("\(context): \"\(label)\" was never wholly visible between y \(top) and \(bottom) after \(maximum) drags; last frame \(last), hittable \(target()?.isHittable ?? false)",
                file: file, line: line)
        return nil
    }

    /// Requires a button whose whole label matches `pattern` (a regular expression).
    static func requireButton(_ app: XCUIApplication, matching pattern: String, context: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        let query = app.buttons.matching(NSPredicate(format: "label MATCHES %@", pattern))
        XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 10), "\(context): no button whose label matches \(pattern)",
                      file: file, line: line)
    }

    /// Saves a screenshot at 1x (small PNGs for the evidence folder) and attaches it to the result.
    @discardableResult
    static func screenshot(_ name: String, folder: String) -> String {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .deleteOnSuccess
        XCTContext.runActivity(named: "screenshot \(name)") { $0.add(attachment) }
        guard let directory = evidenceDirectory?.appendingPathComponent(folder) else { return "" }
        let image = shot.image
        let size = CGSize(width: image.size.width, height: image.size.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(name).png")
            try small.pngData()?.write(to: url)
            return "\(folder)/\(name).png"
        } catch {
            XCTFail("could not save screenshot \(name): \(error)")
            return ""
        }
    }

    /// Writes a text file (a Markdown report) into the evidence folder.
    static func writeText(_ fileName: String, _ text: String) {
        guard let directory = evidenceDirectory else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try (text + "\n").write(to: directory.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
        } catch {
            XCTFail("could not write \(fileName): \(error)")
        }
    }

    /// Writes a Markdown table of the visits.
    static func writeReport(_ fileName: String, title: String, environment: String, results: [ScreenResult]) {
        guard let directory = evidenceDirectory else { return }
        var lines = ["# \(title)", "", "Environment: \(environment). Generated by the DesignCatalogUITests target.", "",
                     "| Screen | Variant | Audit screen | Truncated / outside / texts | Labels required | Reachable | Screenshot |",
                     "| --- | --- | --- | --- | --- | --- | --- |"]
        for r in results {
            let labels = ((r.visit.labels + r.visit.values).map { "\"\($0)\"" }
                + (r.visit.buttonPattern.map { ["button matching `\($0)`"] } ?? [])).joined(separator: ", ")
            lines.append("| \(r.visit.screen) | \(r.variant.rawValue) | \(r.visit.audit) | \(r.truncated) / \(r.outside) / \(r.texts) | \(labels) | \(r.reached) | \(r.screenshot) |")
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? (lines.joined(separator: "\n") + "\n").write(to: directory.appendingPathComponent(fileName),
                                                          atomically: true, encoding: .utf8)
    }
}
