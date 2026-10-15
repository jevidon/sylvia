@testable import EPUBHarness
import Foundation
import G01EPUBCore
import UIKit
import XCTest

/// Deliverable 5 (T15, same asset): a saved highlight stays on the same text through settings changes and
/// rotation, and its saved locator reopens the passage. Relaunch is covered from outside the process by
/// `ReaderUITests.testHighlightSurvivesRotationAndRelaunch`. Simulator.
@MainActor final class AnchorStabilityTests: XCTestCase {
    override func tearDown() async throws {
        TestHost.tearDown()
        await rotate(to: .portrait)
    }

    func rotate(to orientation: UIInterfaceOrientationMask) async {
        let scene = TestHost.scene
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { _ in }
            c.resume()
        }
        try? await Task.sleep(for: .seconds(1.5))
    }

    func capture(_ screen: ReaderScreen, quote: String, href: String) async throws -> SavedHighlight {
        let s = screen.session
        let moved = await ReaderProbe.goToText(s, href: href, exact: quote)
        XCTAssertTrue(moved)
        _ = try await ReaderProbe.call(s, "selectText(\(ReaderProbe.jsString(quote)), null)")
        let selection = await ReaderProbe.waitForSelection(s)
        XCTAssertEqual(selection?.exactText, quote)
        let captured = await screen.capture(note: nil)
        return try XCTUnwrap(captured)
    }

    func testCaptureDoesNotMoveThePage() async throws {
        let screen = try await TestHost.open("se-meditations.epub")
        let s = screen.session
        let moved = await ReaderProbe.goToText(s, href: ScenarioRunner.anchorHref, exact: ScenarioRunner.anchorQuote)
        XCTAssertTrue(moved)
        let before = try await ReaderProbe.evaluate(s, "window.scrollX")
        _ = try await ReaderProbe.call(s, "selectText(\(ReaderProbe.jsString(ScenarioRunner.anchorQuote)), null)")
        _ = await ReaderProbe.waitForSelection(s)
        let captured = await screen.capture(note: nil)
        let saved = try XCTUnwrap(captured)
        await s.settle()
        let after = try await ReaderProbe.evaluate(s, "window.scrollX")
        XCTAssertEqual(before, after, "saving a highlight moved the page")
        let i = try await ReaderProbe.inspect(s, exact: saved.anchor.exactText, prefix: saved.anchor.prefix, highlightID: saved.id)
        XCTAssertTrue(i.visible && i.covered, "\(i.raw)")
    }

    func testHighlightFollowsTheTextThroughSettingsAndRotation() async throws {
        let screen = try await TestHost.open("se-meditations.epub")
        let s = screen.session
        let saved = try await capture(screen, quote: ScenarioRunner.anchorQuote, href: ScenarioRunner.anchorHref)
        let savedLocatorJSON = saved.locator.json
        var log: [[String: Any]] = []

        struct Step { let name: String; let change: (inout ReaderSettings) -> Void; let rotation: UIInterfaceOrientationMask? }
        let steps: [Step] = [
            Step(name: "font 28 pt", change: { $0.fontSizePoints = 28 }, rotation: nil),
            Step(name: "font 14 pt", change: { $0.fontSizePoints = 14 }, rotation: nil),
            Step(name: "theme Night", change: { $0.theme = .night }, rotation: nil),
            Step(name: "line spacing step 3", change: { $0.lineSpacingStep = 3 }, rotation: nil),
            Step(name: "line spacing step 0", change: { $0.lineSpacingStep = 0 }, rotation: nil),
            Step(name: "margins wide", change: { $0.marginStep = 2 }, rotation: nil),
            Step(name: "system sans", change: { $0.typeface = .systemSans }, rotation: nil),
            Step(name: "theme Paper, Literata, 19 pt", change: { $0.theme = .paper; $0.typeface = .literata; $0.fontSizePoints = 19; $0.lineSpacingStep = 1; $0.marginStep = 1 }, rotation: nil),
            Step(name: "rotate landscape", change: { _ in }, rotation: .landscapeRight),
            Step(name: "font 24 pt in landscape", change: { $0.fontSizePoints = 24 }, rotation: nil),
            Step(name: "rotate portrait", change: { _ in }, rotation: .portrait),
            Step(name: "scroll mode", change: { $0.scroll = true; $0.fontSizePoints = 19 }, rotation: nil),
            Step(name: "paginated again", change: { $0.scroll = false }, rotation: nil),
        ]

        for step in steps {
            if let r = step.rotation {
                await rotate(to: r)
            } else {
                var settings = s.settings
                step.change(&settings)
                s.apply(settings: settings)
            }
            await s.settle()
            // Position after the change, before any explicit navigation (Readium restores by progression).
            let restored = try await ReaderProbe.inspect(s, exact: saved.anchor.exactText, prefix: saved.anchor.prefix, highlightID: saved.id)
            // The highlight must cover the same text wherever the quote now lies.
            var inspection = restored
            let covered = await ReaderProbe.wait(timeout: .seconds(8)) {
                inspection = (try? await ReaderProbe.inspect(s, exact: saved.anchor.exactText, prefix: saved.anchor.prefix, highlightID: saved.id)) ?? inspection
                return inspection.covered && inspection.renderings == 1
            }
            XCTAssertTrue(covered, "\(step.name): highlight not on the quote: \(inspection.raw)")
            // Navigating to the saved locator lands on the passage.
            let went = await s.navigate(to: saved.locator)
            XCTAssertTrue(went, step.name)
            var landed = inspection
            let visible = await ReaderProbe.wait(timeout: .seconds(5)) {
                landed = (try? await ReaderProbe.inspect(s, exact: saved.anchor.exactText, prefix: saved.anchor.prefix, highlightID: saved.id)) ?? landed
                return landed.visible && landed.covered && landed.renderings == 1
            }
            XCTAssertTrue(visible, "\(step.name): saved locator did not reopen the passage: \(landed.raw)")
            let size = screen.view.bounds.size
            log.append([
                "step": step.name, "view_width": size.width, "view_height": size.height,
                "quote_lines": landed.quoteRectCount, "highlight_boxes": landed.boxes.count, "covered": landed.covered,
                "renderings": landed.renderings, "duplicate_repairs_so_far": s.duplicateRepairs,
                "visible_after_navigate": landed.visible, "visible_before_navigate": restored.visible,
                "current_locator_after_navigate": s.currentLocator?.json ?? "",
            ])
            if step.name == "rotate landscape" || step.name == "theme Night" {
                if let image = await ReaderProbe.snapshot(s) { ReaderProbe.writePNG("anchor-\(step.name.replacingOccurrences(of: " ", with: "-")).png", image) }
            }
        }
        XCTAssertEqual(saved.locator.json, savedLocatorJSON, "the stored locator is never rewritten")
        ReaderProbe.writeEvidence("anchor-stability.json", json: [
            "environment": CompatibilityMatrixTests.environment, "fixture": "se-meditations.epub",
            "saved_locator": savedLocatorJSON, "steps": log,
        ])
    }

    /// Plan 9.4: a highlight survives an extraction-cache rebuild. Re-extracting yields the same blocks and the same
    /// Sylvia offsets for the same selection.
    func testExtractionRebuildGivesTheSameOffsets() async throws {
        let screen = try await TestHost.open("se-meditations.epub")
        let s = screen.session
        let moved = await ReaderProbe.goToText(s, href: ScenarioRunner.anchorHref, exact: ScenarioRunner.anchorQuote)
        XCTAssertTrue(moved)
        _ = try await ReaderProbe.call(s, "selectText(\(ReaderProbe.jsString(ScenarioRunner.anchorQuote)), null)")
        let waited = await ReaderProbe.waitForSelection(s)
        let selection = try XCTUnwrap(waited)
        let first = await EPUBExtraction.extract(s.publication)
        let second = await EPUBExtraction.extract(s.publication)
        XCTAssertEqual(first.map(\.blocks), second.map(\.blocks))
        XCTAssertEqual(first.map(\.chunks), second.map(\.chunks))
        let a = try CaptureBuilder.anchor(for: selection, assetID: "x", assetDigest: s.opened.sha256, extraction: first)
        let b = try CaptureBuilder.anchor(for: selection, assetID: "x", assetDigest: s.opened.sha256, extraction: second)
        XCTAssertNotNil(a.textOffsets)
        XCTAssertEqual(a.textOffsets, b.textOffsets)
    }
}
