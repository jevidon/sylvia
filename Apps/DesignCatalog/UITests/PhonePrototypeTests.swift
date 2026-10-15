import XCTest

/// Visits every interaction-prototype screen on the iPhone simulator in light, dark and at the
/// largest accessibility text size (AX5): the screen must appear, carry its key accessibility
/// labels (the vocabulary's phrases where a state is shown), and have no truncated text in a type
/// role (the layout audit). A 1x screenshot of each visit is saved as evidence.
@MainActor
final class PhonePrototypeTests: XCTestCase {
    static let excerptRange = "11:12.0 to 11:42.0"
    /// The save button after the durable write: "Saved 14:02" or "Saved 2:02 PM" (whole label).
    static let savedPattern = "Saved [0-9]{1,2}:[0-9]{2}.*"
    /// The quote block of the last card in Thoughts (Walden), which must be reachable by scrolling.
    static let lastThought = "I went to the woods because I wished to live deliberately, to front only the essential facts of life, and see if I could not learn what it had to teach, and not, when I came to die, discover that I had not lived."

    static let visits: [Visit] = [
        Visit(screen: "onboarding", audit: "onboarding",
              labels: ["Import a book", "Connect a Mac", "Add a record", "AI is optional"]),
        Visit(screen: "library", audit: "library",
              labels: ["Library", "Thoughts", "Inbox", "Middlemarch", "Capture the last 30 seconds", "Chapter 20 of 86",
                       "Record only", "Not on this device · from Studio"]),
        Visit(screen: "work.onDevice", audit: "work.middlemarch",
              labels: ["On this device", "Remove download", "Rating", "Editions", "History"]),
        Visit(screen: "work.recordOnly", audit: "work.meditations",
              labels: ["Record only", "Add a file", "No file. The record keeps your history"]),
        Visit(screen: "work.notOnDevice", audit: "work.mobyDick",
              labels: ["Not on this device · from Studio", "Download from Studio"]),
        Visit(screen: "inbox", audit: "inbox",
              labels: ["Receiving", "of 5.2 GB verified", "Pause", "Verifying", "Ready · indexing continues", "Open",
                       "Needs attention", "Resolve", "Needs review", "Waiting for Studio", "Queued"],
              reach: "Resolve"),
        Visit(screen: "inbox.resolve", audit: "inbox.frankenstein",
              labels: ["Needs attention", "protected by DRM", "Import a copy without DRM", "Remove from the Inbox"]),
        Visit(screen: "inbox.review", audit: "inbox.walden",
              labels: ["Needs review", "Attach as an edition", "Keep separate"]),
        Visit(screen: "reader", audit: "reader",
              labels: ["Back", "Reader settings", "Bookmark", "Search in book", "Chapter 20 of 86", "Highlighted"]),
        Visit(screen: "reader.selection", audit: "reader",
              labels: ["Highlight", "Note", "Look up", "Ask"], reach: "Highlight"),
        Visit(screen: "capture.draft", audit: "captureSheet",
              labels: ["Save to thoughts", "Quote", "Your note", "Look up", "Ask", "Save"],
              values: ["Eliot's case for partial sympathy"], reach: "Save"),
        Visit(screen: "capture.saving", audit: "captureSheet", labels: ["Saving…"]),
        Visit(screen: "capture.saved", audit: "captureSheet", labels: [],
              values: ["Eliot's case for partial sympathy"], buttonPattern: PhonePrototypeTests.savedPattern),
        Visit(screen: "capture.failed", audit: "captureSheet", labels: ["Not saved · your text is still here"],
              values: ["Eliot's case for partial sympathy"], reach: "Not saved · your text is still here"),
        Visit(screen: "lookUp", audit: "lookUp", labels: ["incongruities", "Word", "Save"]),
        Visit(screen: "thoughts", audit: "thoughts",
              labels: ["All", "Quotes", "Notes", "Audio", "Generated", "Words", "Play excerpt", "No transcript",
                       "Citation c1"],
              reach: lastThought),
        Visit(screen: "player", audit: "player",
              labels: ["Now playing", "Close player", "Back 30 seconds", "Pause", "Forward 30 seconds",
                       "Capture the last 30 seconds", "Part 14 of 35"],
              reach: "Capture the last 30 seconds"),
        Visit(screen: "player.preserving", audit: "player", labels: ["Moment saved · preserving audio", excerptRange]),
        Visit(screen: "player.saved", audit: "player", labels: ["Audio excerpt saved", "Kept even if you remove the audiobook"]),
        Visit(screen: "player.failed", audit: "player", labels: ["Excerpt not preserved · Retry", "could not be read"],
              reach: "Excerpt not preserved · Retry"),
        Visit(screen: "audioCapture", audit: "audioCapture",
              labels: ["Play excerpt", "Start", "End", "Audio excerpt saved", "No transcript", "Set up transcription"],
              reach: "Set up transcription"),
        Visit(screen: "ask.draft", audit: "ask",
              labels: ["Selected passage", "Passage and nearby text", "Only the passage below is sent",
                       "api.example.com · hosted · example-model-1", "Draft · not sent", "Send to api.example.com"]),
        Visit(screen: "ask.sending", audit: "ask", labels: ["Sending to api.example.com", "Stop"]),
        Visit(screen: "ask.generated", audit: "ask",
              labels: ["Generated", "Citation c1", "Unresolved citation c2", "Complete",
                       "Struck-through citations do not match"],
              reach: "Ask another question"),
        Visit(screen: "ask.interrupted", audit: "ask", labels: ["Interrupted · partial answer", "Citation c1", "Ask again"]),
        Visit(screen: "storage", audit: "storage",
              labels: ["Storage", "Remove download", "Remove excerpt audio", "Manage retained text",
                       "Delete record and thoughts"]),
        Visit(screen: "storage.impact", audit: "impactReport",
              labels: ["Remove the audiobook download?", "Frees 1.9 GB", "One excerpt is still being preserved.",
                       "Wait, then remove", "Cancel", "Remove now and lose that excerpt"],
              reach: "Remove now and lose that excerpt"),
        Visit(screen: "settings", audit: "settings", labels: ["Next save fails", "Show onboarding"]),
    ]

    func testEveryScreenInLight() { run(.light) }
    func testEveryScreenInDark() { run(.dark) }
    func testEveryScreenAtAX5() { run(.ax5) }

    /// The Inbox attention dot: the tab bar's Inbox item reports "Needs attention" while an item
    /// needs the user, and stops once it is resolved.
    func testInboxAttentionDotFollowsTheInbox() {
        let app = Harness.launch(["-SylviaScreen", "inbox.resolve", "-SylviaAppearance", "light"])
        let inboxTab = app.buttons.matching(NSPredicate(format: "label == %@", "Inbox")).firstMatch
        XCTAssertTrue(inboxTab.waitForExistence(timeout: 15))
        XCTAssertEqual(inboxTab.value as? String, "Needs attention")
        app.buttons["Remove from the Inbox"].tap()
        // Walden still needs a review choice, so the dot stays.
        XCTAssertEqual(inboxTab.value as? String, "Needs attention")
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Walden")).firstMatch.tap()
        let attach = app.buttons["Attach as an edition"]
        XCTAssertTrue(attach.waitForExistence(timeout: 10))
        attach.tap()
        let cleared = NSPredicate(format: "value == nil OR value == ''")
        expectation(for: cleared, evaluatedWith: inboxTab)
        waitForExpectations(timeout: 10)
    }

    /// The capture flow end to end: select, Highlight, type a note, Save shows "Saving…" and then
    /// "Saved" only after the simulated durable write; a failed write keeps the text.
    func testCaptureSavesOnlyAfterTheWrite() {
        let app = Harness.launch(["-SylviaScreen", "reader", "-SylviaAppearance", "light", "-SylviaWriteSeconds", "2"])
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "That element of tragedy")).firstMatch.tap()
        app.buttons["Highlight"].tap()
        let field = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Total perception would destroy us.")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Saving…"].waitForExistence(timeout: 5), "Saving… while the write runs")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Saved")).firstMatch.exists,
                       "Saved must not appear before the write returns")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label MATCHES %@", Self.savedPattern)).firstMatch
            .waitForExistence(timeout: 10), "Saved with its time after the write")
    }

    func testFailedSaveKeepsTheText() {
        let app = Harness.launch(["-SylviaScreen", "capture.failed", "-SylviaAppearance", "light"])
        XCTAssertTrue(app.buttons["Not saved · your text is still here"].waitForExistence(timeout: 15))
        Harness.requireValue(app, "Eliot's case for partial sympathy", context: "failed save")
        // The sheet stays: dragging it down from its top edge (where the system's dismiss gesture
        // starts) does not dismiss it while it holds unsaved text, and the text is still there.
        dragSheetDown(app)
        XCTAssertTrue(app.buttons["Not saved · your text is still here"].waitForExistence(timeout: 5))
        Harness.requireValue(app, "Eliot's case for partial sympathy", context: "failed save after the drag")
    }

    /// Control for `testFailedSaveKeepsTheText` (review round 1): the same drag does dismiss the
    /// sheet once its text is durably saved, so the drag really is the system's dismiss gesture.
    func testSavedSheetDismissesWithTheSameDrag() {
        let app = Harness.launch(["-SylviaScreen", "capture.saved", "-SylviaAppearance", "light"])
        let saved = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "Saved [0-9]{1,2}:[0-9]{2}.*")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 15))
        dragSheetDown(app)
        let deadline = Date().addingTimeInterval(8)
        while saved.exists && Date() < deadline { Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertFalse(saved.exists, "the saved sheet was not dismissed by the drag")
    }

    /// A slow drag from just below the top of the sheet to the bottom of the window.
    private func dragSheetDown(_ app: XCUIApplication) {
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.09))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0.1)
    }

    private func run(_ variant: Variant) {
        var results: [ScreenResult] = []
        // Diagnosis only: SYLVIA_ONLY_SCREENS="library,reader" visits just those screens. Such a run
        // always fails the "every screen was visited" check below, so it can never pass as a full run.
        let only = ProcessInfo.processInfo.environment["SYLVIA_ONLY_SCREENS"].map { Set($0.split(separator: ",").map(String.init)) }
        for visit in Self.visits where only?.contains(visit.screen) ?? true {
            XCTContext.runActivity(named: "\(visit.screen) (\(variant.rawValue))") { _ in
                let app = Harness.launch(["-SylviaScreen", visit.screen] + variant.arguments)
                defer { app.terminate() }
                guard let reading = Harness.audit(app, name: visit.audit) else { return }
                Harness.requireCleanAudit(app, reading, name: visit.audit, context: "\(visit.screen) \(variant)")
                for label in visit.labels { Harness.requireLabel(app, label, context: visit.screen) }
                for value in visit.values { Harness.requireValue(app, value, context: visit.screen) }
                if let pattern = visit.buttonPattern { Harness.requireButton(app, matching: pattern, context: visit.screen) }
                let path = Harness.screenshot(visit.screen, folder: "screens/\(Harness.deviceFolder)/\(variant.rawValue)")
                var reached = ""
                if let target = visit.reach, let drags = Harness.reach(app, target, showsMiniPlayer: visit.showsMiniPlayer,
                                                                            context: "\(visit.screen) \(variant)") {
                    let shown = target.count > 40 ? String(target.prefix(40)) + "…" : target
                    reached = "\"\(shown)\" after \(drags) drag\(drags == 1 ? "" : "s")"
                    if drags > 0 {
                        let second = Harness.screenshot("\(visit.screen).reached", folder: "screens/\(Harness.deviceFolder)/\(variant.rawValue)")
                        reached += " (\(second))"
                    }
                }
                results.append(ScreenResult(visit: visit, variant: variant, truncated: reading.truncated,
                                            outside: reading.outside, texts: reading.texts, screenshot: path,
                                            reached: reached))
            }
        }
        XCTAssertEqual(results.count, Self.visits.count, "every screen was visited")
        Harness.writeReport("ui-prototype-\(Harness.deviceFolder)-\(variant.rawValue)-simulator.md",
                            title: "Prototype screens on iPhone, \(variant.rawValue)",
                            environment: Harness.simulatorEnvironment(defaultLabel: "iPhone 17"), results: results)
    }
}
