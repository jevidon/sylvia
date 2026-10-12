@testable import EPUBHarness
import Foundation
import XCTest

/// Readium 3.11.0: a jump into a resource that was just preloaded can be undone when that spread finishes loading.
/// This test records what a single `go(to:)` does (observation, written to evidence) and asserts that the adapter's
/// settle-and-repeat navigation keeps the passage on screen. Simulator.
@MainActor final class NavigationSettleTests: XCTestCase {
    override func tearDown() async throws { TestHost.tearDown() }

    let quote = "From Rusticus"

    func sample(_ s: ReadiumReaderSession) async throws -> [String: Any] {
        let i = try await ReaderProbe.inspect(s, exact: quote, prefix: "", highlightID: nil)
        let scroll = try await ReaderProbe.evaluate(s, "window.scrollX")
        return ["visible": i.visible, "scrollX": scroll, "progression": s.currentLocator?.progression ?? -1]
    }

    func testJumpIntoAFreshResourceStaysPut() async throws {
        var runs: [[String: Any]] = []
        var rawResets = 0
        for attempt in 0 ..< 5 {
            // Readium alone: one go(to:).
            let raw = try await TestHost.open("se-meditations.epub")
            raw.session.repeatsJumpAfterSettle = false
            let ok = await ReaderProbe.goToText(raw.session, href: ScenarioRunner.anchorHref, exact: quote)
            XCTAssertTrue(ok)
            let immediately = try await sample(raw.session)
            try await Task.sleep(for: .milliseconds(1500))
            let later = try await sample(raw.session)
            if (immediately["visible"] as? Bool) == true, (later["visible"] as? Bool) == false { rawResets += 1 }
            TestHost.tearDown()

            // Adapter: go(to:), settle, go(to:) again.
            let adapted = try await TestHost.open("se-meditations.epub")
            let ok2 = await ReaderProbe.goToText(adapted.session, href: ScenarioRunner.anchorHref, exact: quote)
            XCTAssertTrue(ok2)
            try await Task.sleep(for: .milliseconds(1500))
            let settled = try await sample(adapted.session)
            XCTAssertEqual(settled["visible"] as? Bool, true, "attempt \(attempt): adapter navigation did not keep the passage on screen \(settled)")
            TestHost.tearDown()
            runs.append(["attempt": attempt, "readium_single_go_immediately": immediately, "readium_single_go_after_1_5s": later,
                         "adapter_after_1_5s": settled])
        }
        // Second pattern, without the adapter's repeat: from a page inside book-1, a single go(to:) to an endnote far
        // into endnotes.xhtml, then a single go(to:) back. Recorded only (whether Readium undoes a jump depends on timing).
        var linkRuns: [[String: Any]] = []
        var linkResets = 0
        for attempt in 0 ..< 5 {
            let raw = try await TestHost.open("se-meditations.epub")
            let s = raw.session
            s.repeatsJumpAfterSettle = false
            let ok = await ReaderProbe.goToText(s, href: ScenarioRunner.anchorHref, exact: quote)
            XCTAssertTrue(ok)
            try await Task.sleep(for: .milliseconds(1500))
            let start = try await sample(s)
            let startLocator = s.currentLocator
            let followed = await s.followLink(href: "epub/text/endnotes.xhtml#note-6")
            XCTAssertTrue(followed)
            let noteVisible = "(function(){ const e = document.getElementById('note-6'); if (!e) return false; const r = e.getBoundingClientRect(); return r.left >= 0 && r.left < innerWidth; })()"
            // Observations only: right after a jump the visible spread can be torn down while the script runs (WebKit
            // then reports an error), which is recorded rather than failing the test.
            let noteImmediately = (try? await ReaderProbe.evaluate(s, noteVisible)) ?? "evaluation failed"
            try await Task.sleep(for: .milliseconds(1500))
            let noteLater = (try? await ReaderProbe.evaluate(s, noteVisible)) ?? "evaluation failed"
            let returned = await s.returnFromLink()
            XCTAssertTrue(returned)
            try await Task.sleep(for: .milliseconds(1500))
            let back = (try? await sample(s)) ?? ["error": "evaluation failed"]
            // Lost: the endnote did not stay on screen, or the single jump back did not return to the page it left
            // (wherever that page was, even if the first jump into book-1 had itself been undone).
            let reset = noteLater != "1" || back["scrollX"] as? String != start["scrollX"] as? String
                || s.currentLocator?.progression != startLocator?.progression
            if reset { linkResets += 1 }
            linkRuns.append(["attempt": attempt, "start": start, "endnote_visible_immediately": noteImmediately,
                             "endnote_visible_after_1_5s": noteLater, "after_single_go_back_1_5s": back,
                             "start_progression": startLocator?.progression ?? -1, "lost_position": reset,
                             "first_jump_into_book1_was_undone": (start["visible"] as? Bool) != true])
            TestHost.tearDown()
        }
        ReaderProbe.writeEvidence("navigation-race.json", json: [
            "environment": CompatibilityMatrixTests.environment,
            "what": "Open se-meditations.epub (title page), jump to the text 'From Rusticus' in book-1 (page 3 in portrait).",
            "readium_single_go_reset_count": rawResets, "attempts": runs.count, "runs": runs,
            "endnote_round_trip_without_repeat": [
                "what": "From 'From Rusticus' in book-1, a single go(to:) to endnotes.xhtml#note-6 and a single go(to:) back, no adapter repeat.",
                "lost_position_count": linkResets, "attempts": linkRuns.count, "runs": linkRuns,
            ],
        ])
    }
}
