import UIKit
import XCTest

/// Pairing entry paths on the simulator (review findings R1-09, R1-10): pasting the code from the
/// pasteboard, opening a `sylvia://pair/v1#...` link through the system, and replacing the code's address
/// before pairing (an address that leads to another Mac fails the pin check and that Mac receives nothing).
/// Only QR scanning is left to the device (it needs a camera). Run by
/// Spikes/G02-Transfer/Scripts/simulator-pairing-entry-run.sh, which starts the sources and checks their
/// request logs afterwards.
///
/// Environment variables (TEST_RUNNER_ prefix): G02_ENTRY_CODES (a file of pairing codes, one per line, for
/// the genuine source), G02_ROGUE_PORT (a second source with its own key, on 127.0.0.1).
@MainActor
final class PairingEntryUITests: XCTestCase {
    let environment = ProcessInfo.processInfo.environment

    override func setUp() {
        continueAfterFailure = false
    }

    /// Paste: the code is put on the pasteboard and pasted into the field with the standard paste command.
    func testPastedCodeShowsTheFingerprintThenPairs() throws {
        let code = try code(line: 1)
        let app = launch(codeLine: 1)
        UIPasteboard.general.string = code
        let field = element(app, "pairing.code")
        field.tap()
        paste(into: field, app: app)
        XCTAssertTrue(waitForValue(field, timeout: 10) { $0 == code }, "the field does not hold exactly the pasted code")
        UIPasteboard.general.string = ""
        element(app, "pairing.check").tap()
        try pairAndExpectSuccess(app, tag: "paste")
    }

    /// Link: the system opens `sylvia://pair/v1#...` in the harness (CFBundleURLTypes), which fills the field.
    func testOpenedPairingLinkShowsTheFingerprintThenPairs() throws {
        let code = try code(line: 2)
        let link = "sylvia://pair/v1#" + code.dropFirst("SYLVIA1-".count)
        let app = launch(codeLine: 2)
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: link)))
        // The system may ask whether to open the app; answer Open if it does.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Open"].waitForExistence(timeout: 3) { springboard.buttons["Open"].tap() }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        try pairAndExpectSuccess(app, tag: "link")
    }

    /// Address replaced before pairing: first with the rogue source's address (pin mismatch, nothing sent), then
    /// the genuine code again with its own address (the invitation was never used, so pairing succeeds).
    func testReplacedAddressLeadingToAnotherMacSendsNothing() throws {
        let roguePort = try XCTUnwrap(environment["G02_ROGUE_PORT"], "G02_ROGUE_PORT not set (run simulator-pairing-entry-run.sh)")
        let app = launch(codeLine: 3)
        element(app, "pairing.useTestCode").tap()
        let fingerprint = element(app, "pairing.fingerprint").label
        element(app, "pairing.overrideHost").tap()
        element(app, "pairing.overrideHost").typeText("127.0.0.1")
        element(app, "pairing.overridePort").tap()
        element(app, "pairing.overridePort").typeText(roguePort)
        element(app, "pairing.overrideUse").tap()
        XCTAssertTrue(waitForLabel(app, "pairing.status", timeout: 10) { $0.hasPrefix("Pairing will connect only to 127.0.0.1:\(roguePort)") })
        XCTAssertEqual(element(app, "pairing.fingerprint").label, fingerprint, "the fingerprint must stay the code's")
        element(app, "pairing.pair").tap()
        XCTAssertTrue(waitForLabel(app, "pairing.status", timeout: 60) { $0.contains("pinMismatch") }, "pairing with the other Mac did not fail on the pin")
        print("G02-UI override: status after pairing through the rogue address: \(element(app, "pairing.status").label)")
        // The same code with its own address: the genuine Mac never saw the invitation, so it is still valid.
        element(app, "pairing.useTestCode").tap()
        try pairAndExpectSuccess(app, tag: "override-then-genuine")
    }

    // MARK: Helpers

    private func code(line: Int) throws -> String {
        let file = try XCTUnwrap(environment["G02_ENTRY_CODES"], "G02_ENTRY_CODES not set (run simulator-pairing-entry-run.sh)")
        let codes = try String(contentsOfFile: file, encoding: .utf8).split(separator: "\n").map(String.init)
        XCTAssertGreaterThanOrEqual(codes.count, line)
        return codes[line - 1]
    }

    private func launch(codeLine: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-G02ResetState"]
        app.launchEnvironment["G02_PAIRING_CODE_FILE"] = environment["G02_ENTRY_CODES"]
        app.launchEnvironment["G02_PAIRING_CODE_LINE"] = String(codeLine)
        app.launch()
        return app
    }

    /// Pastes with the edit menu's Paste, as a person does: a tap on the focused field or a long press shows
    /// the menu (it does not always appear on the first try). Command-V is not used: in the simulator a
    /// hardware-keyboard paste can involve the Mac's pasteboard, and one run with it never sent the request.
    private func paste(into field: XCUIElement, app: XCUIApplication) {
        let menuPaste = app.menuItems["Paste"]
        for attempt in 1...4 {
            if attempt % 2 == 1 { field.tap() } else { field.press(forDuration: 1.2) }
            if menuPaste.waitForExistence(timeout: 3) {
                menuPaste.tap()
                print("G02-UI paste: pasted with the edit menu's Paste (attempt \(attempt))")
                return
            }
        }
        XCTFail("the edit menu with Paste did not appear")
    }

    private func pairAndExpectSuccess(_ app: XCUIApplication, tag: String) throws {
        let fingerprint = element(app, "pairing.fingerprint")
        let groups = fingerprint.label.split(separator: " ")
        XCTAssertEqual(groups.count, 16, "fingerprint \(fingerprint.label)")
        XCTAssertTrue(groups.allSatisfy { $0.count == 4 && $0.allSatisfy { "0123456789ABCDEF".contains($0) } })
        element(app, "pairing.pair").tap()
        let paired = waitForLabel(app, "pairing.status", timeout: 60) { $0.hasPrefix("Paired with") }
        if !paired {
            // The status line never holds the code or a secret (HarnessModel.pair), so it can be logged.
            print("G02-UI \(tag): pairing did not succeed; status: \(element(app, "pairing.status").label)")
        }
        XCTAssertTrue(paired, "pairing failed")
        XCTAssertTrue(element(app, "source.name").exists)
        print("G02-UI \(tag): fingerprint shown in 16 groups of four, then paired: \(element(app, "pairing.status").label)")
    }

    private func element(_ app: XCUIApplication, _ identifier: String, timeout: TimeInterval = 20) -> XCUIElement {
        let query = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        var attempt = 0
        while !query.exists && Date() < deadline {
            if !query.waitForExistence(timeout: 1) { TerminateRelaunchUITests.scroll(app, attempt: attempt) }
            attempt += 1
        }
        XCTAssertTrue(query.exists, "no element \(identifier)")
        return query
    }

    private func waitForLabel(_ app: XCUIApplication, _ identifier: String, timeout: TimeInterval, _ predicate: (String) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var attempt = 0
        while Date() < deadline {
            let query = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            if query.exists, predicate(query.label) { return true }
            if !query.exists {
                TerminateRelaunchUITests.scroll(app, attempt: attempt)
                attempt += 1
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    private func waitForValue(_ element: XCUIElement, timeout: TimeInterval, _ predicate: (String) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let value = element.value as? String, predicate(value) { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }
}
