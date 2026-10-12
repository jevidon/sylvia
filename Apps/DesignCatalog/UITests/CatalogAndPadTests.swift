import XCTest

/// The component gallery used for the G0.6 device review: the index, the display switches, every
/// sample page, and the text-field labels the package's offscreen renderer cannot see.
@MainActor
final class CatalogGalleryTests: XCTestCase {
    func testIndexAndDisplaySwitches() {
        let app = Harness.launch(["-SylviaAppearance", "light"])
        XCTAssertNotNil(Harness.audit(app, name: "catalog"))
        for label in ["Design catalog", "Appearance", "Text size", "Increase Contrast", "Bold Text", "Colors", "Type",
                      "Markers and status", "Symbols", "All components", "Open the prototype"] {
            Harness.requireLabel(app, label, context: "catalog index")
        }
        let summary = app.descendants(matching: .any)["display.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        app.buttons["Dark"].tap()
        let contrast = app.switches["Increase Contrast"]
        XCTAssertTrue(contrast.exists)
        // SwiftUI toggles respond to a tap on the switch itself, at the trailing edge of the row.
        contrast.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline && !(summary.label.contains("Dark") && summary.label.contains("Increase Contrast")) {
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertTrue(summary.label.contains("Dark") && summary.label.contains("Increase Contrast"),
                      "display summary: \(summary.label); switch value: \(String(describing: contrast.value))")
        Harness.screenshot("catalog-dark-ic", folder: Harness.catalogFolder)
    }

    /// Every component sample page opens, has accessibility elements and no truncated text, in light.
    func testEverySamplePage() {
        let app = Harness.launch(["-SylviaAppearance", "light", "-SylviaPage", "allComponents"])
        guard let reading = Harness.audit(app, name: "components") else { return }
        Harness.requireCleanAudit(app, reading, name: "components", context: "all components (light)")
        Harness.screenshot("all-components-light", folder: Harness.catalogFolder)
    }

    /// The text-field sample in a real window: both fields carry their labels (the package's
    /// offscreen renderer exposes no text fields; AccessibilityTreeTests defers this check here).
    func testTextFieldSampleLabels() {
        let app = Harness.launch(["-SylviaAppearance", "light", "-SylviaPage", "component.textField"])
        XCTAssertNotNil(Harness.audit(app, name: "component.textField"))
        XCTAssertTrue(app.textFields["Search"].waitForExistence(timeout: 10) || app.textViews["Search"].exists,
                      "search field labelled Search")
        XCTAssertTrue(app.textViews["Question"].exists || app.textFields["Question"].exists, "question field labelled")
    }

    /// The color page reads every token back from the compiled asset catalog in the window's
    /// appearance and measures every contrast pair: none below its threshold in any appearance.
    func testColorPageContrastInEveryAppearance() {
        for (appearance, contrast) in [("light", false), ("dark", false), ("light", true), ("dark", true)] {
            var arguments = ["-SylviaAppearance", appearance, "-SylviaPage", "colors"]
            if contrast { arguments += ["-SylviaIncreaseContrast", "YES"] }
            let app = Harness.launch(arguments)
            let summary = app.descendants(matching: .any)["contrast.summary"]
            XCTAssertTrue(summary.waitForExistence(timeout: 15))
            XCTAssertTrue(summary.label.hasSuffix("0 below the threshold."), "\(appearance) IC \(contrast): \(summary.label)")
            // The page measured the appearance that was asked for, not the default one.
            let expected = (appearance == "dark" ? "Dark" : "Light") + (contrast ? " · Increase Contrast" : "")
            XCTAssertTrue(summary.label.contains("pairs in \(expected);"), "\(appearance) IC \(contrast): \(summary.label)")
            Harness.screenshot("colors-\(appearance)\(contrast ? "-ic" : "")", folder: Harness.catalogFolder)
            app.terminate()
        }
    }
}

/// The iPad regular-width layout (Section 4.1, 4.4.7): the sidebar replaces the tab bar, and the
/// reader adapts to a side pane. Runs only on the iPad simulator (the CI drop-in selects it).
@MainActor
final class PadLayoutTests: XCTestCase {
    static let visits: [Visit] = [
        Visit(screen: "library", audit: "library", labels: ["Library", "Thoughts", "Inbox", "Middlemarch"]),
        Visit(screen: "inbox", audit: "inbox", labels: ["Receiving", "Needs attention", "Resolve"]),
        Visit(screen: "thoughts", audit: "thoughts", labels: ["Quotes", "Generated"]),
        Visit(screen: "reader.selection", audit: "reader",
              labels: ["In this book", "Ask about the selection", "Highlight", "Hide thoughts"]),
    ]

    func testRegularWidthLayout() {
        XCTAssertEqual(UIDevice.current.userInterfaceIdiom, .pad, "PadLayoutTests must run on an iPad simulator")
        var results: [ScreenResult] = []
        for variant in Variant.allCases {
            for visit in Self.visits {
                XCTContext.runActivity(named: "\(visit.screen) (\(variant.rawValue))") { _ in
                    let app = Harness.launch(["-SylviaScreen", visit.screen] + variant.arguments)
                    defer { app.terminate() }
                    guard let reading = Harness.audit(app, name: visit.audit) else { return }
                    Harness.requireCleanAudit(app, reading, name: visit.audit, context: "\(visit.screen) \(variant)")
                    for label in visit.labels { Harness.requireLabel(app, label, context: visit.screen) }
                    if visit.screen != "reader.selection" {
                        // The sidebar: the Library row sits at the leading edge near the top, not
                        // in a bottom tab bar.
                        let library = app.buttons.matching(NSPredicate(format: "label == %@", "Library")).firstMatch
                        XCTAssertTrue(library.exists)
                        let window = app.windows.firstMatch.frame
                        XCTAssertLessThan(library.frame.midY, window.midY, "\(visit.screen): Library item is not in a sidebar")
                        XCTAssertLessThan(library.frame.minX, window.width / 3)
                    }
                    let path = Harness.screenshot(visit.screen, folder: "screens/ipad/\(variant.rawValue)")
                    results.append(ScreenResult(visit: visit, variant: variant, truncated: reading.truncated,
                                                outside: reading.outside, texts: reading.texts, screenshot: path))
                }
            }
        }
        XCTAssertEqual(results.count, Self.visits.count * Variant.allCases.count)
        Harness.writeReport("ui-prototype-ipad-simulator.md", title: "Prototype in regular width on iPad",
                            environment: Harness.simulatorEnvironment(defaultLabel: "iPad (A16)"), results: results)
    }
}
