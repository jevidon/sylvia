// The app's own import routes on the simulator (G0.3 review R2-05):
// - "Import from Files": the system document picker, opening a file in place from Files > On My iPhone (placed there by
//   the CI drop-in, step 7), so the importer gets a security-scoped provider URL and reads it inside a coordinated read.
//   This is fallback route step 1 ("Open Sylvia, choose Import, then Files") and the "Files import" that T08 compares
//   open-in duplicates with.
// - A raw supported file in the Finder drop area (plan 8.5), imported with the drop area's Import button. The file is put
//   in Documents by the harness's "Place test file in drop area" button, standing in for Finder's file-sharing copy,
//   which the simulator does not have (the Finder copy itself is device checklist steps 28-30).
// Both tests hold whether or not the same bytes were imported earlier on this simulator (FilesAppUITests runs first and
// shares the same EPUB through the extension): they wait for a new outcome, never for a different one.
// Evidence lines start with "G03-EVIDENCE".
import XCTest

@MainActor
final class ImportRoutesUITests: XCTestCase {
    static let filesProbeName = "G03 Files Share.epub"   // Scripts/ci.d/50-g03-intake.sh copies Fixtures/epub/se-walden.epub
    static let filesProbeBytes = 997_147

    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["harness.summary"].waitForExistence(timeout: 20))
        return app
    }

    /// Scrolls the harness list until the element can be tapped.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 where !(element.exists && element.isHittable) { app.swipeUp() }
        XCTAssertTrue(element.exists && element.isHittable, "not reachable: \(element)\n\(app.debugDescription)")
    }

    private func waitForLabel(_ element: XCUIElement, _ format: String, _ text: String, timeout: TimeInterval = 30) -> String {
        let predicate = NSPredicate(format: format, text)
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
        XCTAssertEqual(result, .completed, "expected \(format) '\(text)', found '\(element.label)'")
        return element.label
    }

    private func waitForMessage(_ app: XCUIApplication, containing text: String) -> String {
        waitForLabel(app.staticTexts["harness.message"], "label CONTAINS %@", text)
    }

    /// Opens the document picker and picks the probe file from On My iPhone. The picker's own controls are the Files
    /// app's (Browse, the On My iPhone sidebar item, file cells). Tapping "Import from Files" clears the harness message.
    private func pickProbeFile(_ app: XCUIApplication) throws {
        let placed = ProcessInfo.processInfo.environment["G03_FILES_PROBE"] == "placed"
        let pick = app.buttons["harness.pick"]
        reveal(pick, in: app)
        pick.tap()
        let browse = app.buttons["Browse"].firstMatch
        if browse.waitForExistence(timeout: 15) {
            browse.tap(); sleep(1)
            if browse.isHittable { browse.tap() }   // a second tap returns to the Browse root
        }
        let onMyPhone = app.cells["DOC.sidebar.item.On My iPhone"]
        XCTAssertTrue(onMyPhone.waitForExistence(timeout: 15), "document picker did not show On My iPhone:\n\(app.debugDescription)")
        onMyPhone.tap()
        let file = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", Self.filesProbeName)).firstMatch
        guard file.waitForExistence(timeout: 30) else {
            if !placed { throw XCTSkip("\(Self.filesProbeName) was not placed in Files > On My iPhone (run through the CI drop-in)") }
            XCTFail("\(Self.filesProbeName) was placed in On My iPhone but the picker does not show it:\n\(app.debugDescription)")
            return
        }
        file.tap()
        // Single selection picks on tap; some layouts also need Open.
        let open = app.buttons["Open"].firstMatch
        if open.waitForExistence(timeout: 2), open.isHittable { open.tap() }
    }

    func testDocumentPickerImportsInPlaceAndFlagsTheSameFileAsDuplicate() throws {
        let app = launch()
        try pickProbeFile(app)
        let first = waitForMessage(app, containing: "Picked file")
        let detail = waitForLabel(app.staticTexts["harness.pickerDetail"], "label BEGINSWITH %@", "pick 1:")
        print("G03-EVIDENCE document picker, first pick: '\(first)'; \(detail)")
        XCTAssertTrue(first.contains("Picked file staged: 1 file(s)") && first.contains("\(Self.filesProbeBytes) bytes"), first)
        // staged, or needs_review when the share extension already imported the same EPUB on this simulator.
        XCTAssertTrue(first.contains("state staged") || first.contains("state needs_review"), first)
        XCTAssertFalse(detail.contains("Documents/Inbox") || detail.contains("tmp"),
                       "an in-place pick hands over the provider's file, not a copy in the app's container: \(detail)")
        XCTAssertTrue(detail.contains("picked from outside the app container") && detail.contains("security-scoped access granted: true"),
                      "the picker must hand over a security-scoped URL to the provider's file: \(detail)")
        // The picked file is never modified or removed (I-08), measured (review R3-05): the same device, inode, size and
        // modification time before and after the import, and its SHA-256 afterwards equals the bytes that were staged.
        XCTAssertTrue(detail.contains("source identity before and after the import equal (device, inode, size, modification time): true"),
                      "the picked file's identity changed during the import: \(detail)")
        XCTAssertTrue(detail.contains("\(Self.filesProbeBytes) bytes"), "the identity line records the picked file's size: \(detail)")
        XCTAssertTrue(detail.contains("source SHA-256 afterwards equals the imported bytes: true"),
                      "the picked file's bytes differ from what was imported: \(detail)")

        try pickProbeFile(app)
        let second = waitForMessage(app, containing: "Picked file")
        let secondDetail = waitForLabel(app.staticTexts["harness.pickerDetail"], "label BEGINSWITH %@", "pick 2:")
        print("G03-EVIDENCE document picker, same file again: '\(second)'; \(secondDetail)")
        XCTAssertTrue(second.contains("state needs_review"), "the same bytes again are a duplicate, as on every route: \(second)")
        XCTAssertTrue(secondDetail.contains("source identity before and after the import equal (device, inode, size, modification time): true")
                      && secondDetail.contains("source SHA-256 afterwards equals the imported bytes: true"), secondDetail)
        print("G03-EVIDENCE document picker: app summary \(app.staticTexts["harness.summary"].label)")
    }

    /// Puts the deterministic stand-in for a Finder copy in Documents (the same bytes every time) and taps its Import.
    private func placeAndImport(_ name: String, in app: XCUIApplication) -> String {
        let place = app.buttons["harness.placeDropFile"]
        reveal(place, in: app)
        place.tap()
        _ = waitForMessage(app, containing: "Placed \(name)")
        for _ in 0..<5 where !(app.buttons["harness.import.\(name)"].exists && app.buttons["harness.import.\(name)"].isHittable) {
            app.swipeDown()
        }
        let importButton = app.buttons["harness.import.\(name)"]
        reveal(importButton, in: app)
        importButton.tap()
        return waitForMessage(app, containing: "Imported \(name)")
    }

    func testRawFileInDropAreaImportsAndStaysUntilRemoved() throws {
        let app = launch()
        let name = "G03 Finder Copy.epub"
        let first = placeAndImport(name, in: app)
        print("G03-EVIDENCE raw drop-area file: '\(first)'")
        XCTAssertTrue(first.contains("1 files, state ") && first.contains("route documents_file"), first)
        XCTAssertTrue(first.contains("state staged") || first.contains("state needs_review"), first)
        XCTAssertTrue(app.buttons["harness.import.\(name)"].exists, "a raw Finder file stays in the drop area after its import")

        // The same bytes copied in again (Placed replaces the file) are a duplicate.
        let second = placeAndImport(name, in: app)
        print("G03-EVIDENCE raw drop-area file, the same bytes again: '\(second)'")
        XCTAssertTrue(second.contains("state needs_review") && second.contains("route documents_file"), second)

        let remove = app.buttons["harness.remove.\(name)"]
        reveal(remove, in: app)
        remove.tap()
        let gone = NSPredicate(format: "exists == false")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: app.buttons["harness.import.\(name)"])], timeout: 10), .completed)
        print("G03-EVIDENCE raw drop-area file: removed by the user; app summary \(app.staticTexts["harness.summary"].label)")
    }
}
