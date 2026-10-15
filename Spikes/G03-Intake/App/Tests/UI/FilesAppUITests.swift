// The Files app route on the simulator (G0.3 review R1-04): an EPUB in On My iPhone (placed there by the CI drop-in,
// step 7, through the simulator's local file-provider storage), shared from the Files app into the extension through
// the file provider, which must be received and imported. Observed on the iOS 26.5 simulator: the Files share sheet
// offers the extension only once the containing app has been launched after installation (before that it offers no
// third-party extension at all), so the test launches the harness first. "Open With" is recorded, not required: it
// showed "No Apps Available" in every run (report finding F12; device checklist step 13).
import XCTest

@MainActor
final class FilesAppUITests: XCTestCase {
    static let fileName = "G03 Files Share.epub"   // Scripts/ci.d/50-g03-intake.sh copies Fixtures/epub/se-walden.epub

    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// Files > Browse > On My iPhone, then long-press the probe file. The CI drop-in places the file and says so with
    /// TEST_RUNNER_G03_FILES_PROBE=placed (forwarded as G03_FILES_PROBE); then a missing file is a failure. Only a run
    /// that did not place it (for example from Xcode by hand) skips.
    private func openFileMenu(_ files: XCUIApplication) throws {
        let placed = ProcessInfo.processInfo.environment["G03_FILES_PROBE"] == "placed"
        // Launch the harness once first, as a user does after installing. In exploration, the Files share sheet offered
        // the extension in a run where the harness had already been launched, and offered no third-party extension in
        // a run on a fresh install where it had not.
        let harness = XCUIApplication()
        harness.launch()
        XCTAssertTrue(harness.staticTexts["harness.summary"].waitForExistence(timeout: 20))
        harness.terminate()
        files.launch()
        let browse = files.tabBars.buttons["Browse"]
        XCTAssertTrue(browse.waitForExistence(timeout: 10))
        browse.tap(); sleep(1); browse.tap()   // the second tap returns to the Browse root
        let onMyPhone = files.cells["DOC.sidebar.item.On My iPhone"]
        XCTAssertTrue(onMyPhone.waitForExistence(timeout: 10))
        onMyPhone.tap()
        let file = files.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", Self.fileName)).firstMatch
        guard file.waitForExistence(timeout: 30) else {
            if !placed { throw XCTSkip("\(Self.fileName) was not placed in Files > On My iPhone (run through the CI drop-in)") }
            XCTFail("\(Self.fileName) was placed in On My iPhone but Files does not show it: \(files.debugDescription)")
            return
        }
        file.press(forDuration: 1.5)
    }

    private func lines(_ app: XCUIApplication, containing needles: [String]) -> String {
        app.debugDescription.split(separator: "\n")
            .filter { line in needles.contains { line.contains($0) } }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " | ")
    }

    func testFilesAppShareSheetOffersTheExtension() throws {
        let files = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
        try openFileMenu(files)
        let share = files.buttons["Share"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        share.tap()
        let target = files.cells.matching(NSPredicate(format: "label == %@", "Sylvia Intake Spike")).firstMatch
        var offered = target.waitForExistence(timeout: 15)
        print("G03-EVIDENCE files app share sheet (On My iPhone, \(Self.fileName)): \(lines(files, containing: ["identifier: 'shareCell'", "identifier: 'actionGroupCell'"]))")
        if !offered {
            let more = files.cells.matching(NSPredicate(format: "identifier == %@ AND label == %@", "shareCell", "More")).firstMatch
            if more.exists {
                more.tap()
                sleep(5)
                offered = target.exists
                print("G03-EVIDENCE files app share sheet, More list: \(lines(files, containing: ["Table,", "Sylvia"]))")
            }
        }
        print("G03-EVIDENCE files app share sheet offers Sylvia Intake Spike: \(offered)")
        XCTAssertTrue(offered, "the Files share sheet did not offer the extension after the harness was launched: \(files.debugDescription)")
        // Offered: a real share through the Files app's file provider (in-place file representation).
        if !target.isHittable { files.collectionViews.firstMatch.swipeLeft() }
        target.tap()
        let received = files.staticTexts["share.received"]
        XCTAssertTrue(received.waitForExistence(timeout: 60), "\(files.debugDescription)")
        print("G03-EVIDENCE files app share: extension reports '\(files.staticTexts["share.receivedDetail"].label)'")
        print("G03-EVIDENCE files app share: \(files.staticTexts["share.representations"].label)")
        print("G03-EVIDENCE files app share: \(files.staticTexts["share.protection"].label)")
        XCTAssertTrue(files.staticTexts["share.receivedDetail"].label.contains("997147 bytes"))
        files.buttons["share.done"].tap()
        files.terminate()
        // The harness scans on launch and again on foreground; the scan log keeps the last few scans.
        let app = XCUIApplication()
        app.launch()
        let predicate = NSPredicate(format: "label CONTAINS %@", "accepted=1")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: app.staticTexts["harness.scanLog"])], timeout: 30), .completed,
                       "the Files share was not imported: \(app.staticTexts["harness.scanLog"].label)")
        print("G03-EVIDENCE files app share: harness scans \(app.staticTexts["harness.scanLog"].label); summary \(app.staticTexts["harness.summary"].label)")
        app.terminate()
    }

    func testFilesAppOpenWithOffersTheHarness() throws {
        let files = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
        try openFileMenu(files)
        let openWith = files.buttons["Open With"].firstMatch
        XCTAssertTrue(openWith.waitForExistence(timeout: 10))
        openWith.tap()
        sleep(2)
        let offered = files.buttons["Sylvia Intake Spike"].exists
        print("G03-EVIDENCE files app Open With menu: \(lines(files, containing: ["No Apps Available", "Sylvia Intake Spike", "Preview with Quick Look"]))")
        print("G03-EVIDENCE files app Open With offers Sylvia Intake Spike: \(offered)")
        guard offered else {
            files.terminate()
            return
        }
        files.buttons["Sylvia Intake Spike"].tap()
        let app = XCUIApplication()
        let message = app.staticTexts["harness.message"]
        let predicate = NSPredicate(format: "label CONTAINS %@", "Opened file staged")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: message)], timeout: 30), .completed)
        print("G03-EVIDENCE files app Open With: harness says '\(message.label)'")
    }
}
