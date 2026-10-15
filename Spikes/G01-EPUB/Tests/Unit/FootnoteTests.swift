@testable import EPUBHarness
import Foundation
import XCTest

/// Deliverable 6: endnote links and return-after-link (plan 9.1, 9.4). Simulator.
@MainActor final class FootnoteTests: XCTestCase {
    override func tearDown() async throws { TestHost.tearDown() }

    /// A click on a Standard Ebooks noteref goes through Readium's link handling: the adapter receives the note
    /// content and the reading position does not move.
    func testNoterefShowsTheNoteWithoutMoving() async throws {
        let screen = try await TestHost.open("se-meditations.epub")
        let s = screen.session
        let moved = await ReaderProbe.goToText(s, href: ScenarioRunner.anchorHref, exact: "From Diognetus,")
        XCTAssertTrue(moved)
        try await Task.sleep(for: .milliseconds(500))
        let before = try XCTUnwrap(s.currentLocator)
        let scrollBefore = try await ReaderProbe.evaluate(s, "window.scrollX")
        var shown: String?
        s.onNote = { html, _ in shown = html }
        // A DOM click on <a id="noteref-5" epub:type="noteref" href="endnotes.xhtml#note-5">.
        _ = try await ReaderProbe.evaluate(s, "document.getElementById('noteref-5').click(); true")
        let got = await ReaderProbe.wait(timeout: .seconds(5)) { shown != nil }
        XCTAssertTrue(got, "Readium did not report the note")
        let note = (shown ?? "").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        XCTAssertTrue(note.contains("Diognetus"), note)
        // What the harness popup shows: plain text, no markup.
        let popup = ReaderScreen.plainText(fromNoteHTML: shown ?? "")
        XCTAssertTrue(popup.contains("Diognetus") && !popup.contains("<"), popup)
        try await Task.sleep(for: .milliseconds(500))
        let after = try XCTUnwrap(s.currentLocator)
        XCTAssertEqual(after.href, before.href)
        XCTAssertEqual(after.progression, before.progression)
        let scrollAfter = try await ReaderProbe.evaluate(s, "window.scrollX")
        XCTAssertEqual(scrollAfter, scrollBefore)
        ReaderProbe.writeEvidence("footnote-note.json", json: [
            "before": before.json, "after": after.json, "note_text": note.trimmingCharacters(in: .whitespacesAndNewlines),
            "note_href": s.lastNote?.href ?? "", "referrer_html": s.lastNote?.referrer ?? "",
        ])
    }

    /// Following an internal link (here to an endnote) and returning lands on the exact prior position.
    func testReturnAfterLinkRestoresTheExactPosition() async throws {
        let screen = try await TestHost.open("se-meditations.epub")
        let s = screen.session
        let anchorText = "From Rusticus"
        let moved = await ReaderProbe.goToText(s, href: ScenarioRunner.anchorHref, exact: anchorText)
        XCTAssertTrue(moved)
        try await Task.sleep(for: .milliseconds(500))
        let before = try XCTUnwrap(s.currentLocator)
        let scrollBefore = try await ReaderProbe.evaluate(s, "window.scrollX")
        XCTAssertGreaterThan(Double(scrollBefore) ?? 0, 0, "start somewhere past the first page")
        let visibleBefore = try await ReaderProbe.inspect(s, exact: anchorText, prefix: "", highlightID: nil)
        XCTAssertTrue(visibleBefore.visible)

        let followed = await s.followLink(href: "epub/text/endnotes.xhtml#note-6")
        XCTAssertTrue(followed)
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(s.currentLocator?.href, "epub/text/endnotes.xhtml")
        let atNote = try await ReaderProbe.evaluate(s, "(function(){ const r = document.getElementById('note-6').getBoundingClientRect(); return r.left >= 0 && r.left < innerWidth; })()")
        XCTAssertEqual(atNote, "1", "the endnote is on screen")

        let returned = await s.returnFromLink()
        XCTAssertTrue(returned)
        try await Task.sleep(for: .milliseconds(800))
        let after = try XCTUnwrap(s.currentLocator)
        XCTAssertEqual(after.href, before.href)
        XCTAssertEqual(after.progression, before.progression)
        XCTAssertEqual(after.position, before.position)
        let scrollAfter = try await ReaderProbe.evaluate(s, "window.scrollX")
        XCTAssertEqual(scrollAfter, scrollBefore)
        let visibleAfter = try await ReaderProbe.inspect(s, exact: anchorText, prefix: "", highlightID: nil)
        XCTAssertTrue(visibleAfter.visible)
        XCTAssertEqual(s.linkHistoryDepth, 0)
        ReaderProbe.writeEvidence("footnote-return.json", json: [
            "before": before.json, "after": after.json, "scrollX_before": scrollBefore, "scrollX_after": scrollAfter,
        ])
    }

    /// A link activated inside the publication (the endnote's backlink, `epub:type="backlink"`, which is not a noteref)
    /// goes through Readium's link delegate into the adapter, which records the position it leaves; returning twice
    /// walks back through the endnote to the original reading position.
    func testTappedInternalLinkAndReturnWalkBackThroughHistory() async throws {
        let screen = try await TestHost.open("se-meditations.epub")
        let s = screen.session
        let moved = await ReaderProbe.goToText(s, href: ScenarioRunner.anchorHref, exact: "From Rusticus")
        XCTAssertTrue(moved)
        try await Task.sleep(for: .milliseconds(500))
        let start = try XCTUnwrap(s.currentLocator)
        let startScroll = try await ReaderProbe.evaluate(s, "window.scrollX")

        let followed = await s.followLink(href: "epub/text/endnotes.xhtml#note-6")
        XCTAssertTrue(followed)
        try await Task.sleep(for: .milliseconds(800))
        let atNote = try XCTUnwrap(s.currentLocator)
        XCTAssertEqual(atNote.href, "epub/text/endnotes.xhtml")
        let noteScroll = try await ReaderProbe.evaluate(s, "window.scrollX")
        XCTAssertEqual(s.linkHistoryDepth, 1)

        // A DOM click on the backlink: Readium's own click handling reports the link to the navigator delegate.
        _ = try await ReaderProbe.evaluate(s, "document.querySelector('#note-6 a[role=\"doc-backlink\"]').click(); true")
        let arrived = await ReaderProbe.wait(timeout: .seconds(5)) { s.currentLocator?.href == ScenarioRunner.anchorHref }
        XCTAssertTrue(arrived, "backlink did not navigate: \(s.currentLocator?.href ?? "nil")")
        try await Task.sleep(for: .milliseconds(1000))
        XCTAssertEqual(s.linkHistoryDepth, 2, "the tapped link did not record the position it left")
        let noterefVisible = try await ReaderProbe.evaluate(s, "(function(){ const r = document.getElementById('noteref-6').getBoundingClientRect(); return r.left >= 0 && r.left < innerWidth; })()")
        XCTAssertEqual(noterefVisible, "1", "the backlink target is on screen")

        let back1 = await s.returnFromLink()
        XCTAssertTrue(back1)
        try await Task.sleep(for: .milliseconds(800))
        let backAtNote = try XCTUnwrap(s.currentLocator)
        XCTAssertEqual(backAtNote.href, atNote.href)
        XCTAssertEqual(backAtNote.progression, atNote.progression)
        let backNoteScroll = try await ReaderProbe.evaluate(s, "window.scrollX")
        XCTAssertEqual(backNoteScroll, noteScroll)

        let back2 = await s.returnFromLink()
        XCTAssertTrue(back2)
        try await Task.sleep(for: .milliseconds(800))
        let backAtStart = try XCTUnwrap(s.currentLocator)
        XCTAssertEqual(backAtStart.href, start.href)
        XCTAssertEqual(backAtStart.progression, start.progression)
        let backStartScroll = try await ReaderProbe.evaluate(s, "window.scrollX")
        XCTAssertEqual(backStartScroll, startScroll)
        XCTAssertEqual(s.linkHistoryDepth, 0)
        ReaderProbe.writeEvidence("footnote-backlink-history.json", json: [
            "environment": CompatibilityMatrixTests.environment,
            "start": start.json, "start_scrollX": startScroll, "at_note": atNote.json, "note_scrollX": noteScroll,
            "after_first_return": backAtNote.json, "after_first_return_scrollX": backNoteScroll,
            "after_second_return": backAtStart.json, "after_second_return_scrollX": backStartScroll,
        ])
    }
}
