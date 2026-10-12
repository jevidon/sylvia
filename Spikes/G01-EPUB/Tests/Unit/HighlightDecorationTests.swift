@testable import EPUBHarness
import Foundation
import G01EPUBCore
@preconcurrency import ReadiumNavigator
import UIKit
import XCTest

/// Deliverable 3: the saved highlight is drawn as an `ochre.tint` fill plus an `ochre` underline (plan 4.4.8),
/// verified in the DOM (computed styles), in pixels (web view snapshot) and as screenshots, Paper and Night.
@MainActor final class HighlightDecorationTests: XCTestCase {
    override func tearDown() async throws { TestHost.tearDown() }

    struct Expect { var fill: [Int]; var underline: [Int]; var ground: [Int] }
    static let paper = Expect(fill: [241, 228, 200], underline: [138, 84, 16], ground: [244, 242, 237])
    static let night = Expect(fill: [58, 46, 23], underline: [217, 162, 74], ground: [22, 21, 18])

    func testOchreFillAndUnderlineInPaperAndNight() async throws {
        let screen = try await TestHost.open("se-meditations.epub")
        let s = screen.session
        let quote = ScenarioRunner.anchorQuote
        let moved = await ReaderProbe.goToText(s, href: ScenarioRunner.anchorHref, exact: quote)
        XCTAssertTrue(moved)
        _ = try await ReaderProbe.call(s, "selectText(\(ReaderProbe.jsString(quote)), null)")
        let selection = await ReaderProbe.waitForSelection(s)
        XCTAssertNotNil(selection)
        let captured = await screen.capture(note: nil)
        let saved = try XCTUnwrap(captured, "capture failed")
        XCTAssertEqual(screen.statusLabel.text, "Saved")
        // Readium clears the web view selection; its debounced selectionchange then empties `currentSelection`.
        let cleared = await ReaderProbe.wait(timeout: .seconds(3)) { s.currentSelection == nil }
        XCTAssertTrue(cleared, "selection is cleared after saving")

        // Navigating to the saved locator lands on the passage (Readium resolves it by its text).
        let back = await s.navigate(to: saved.locator)
        XCTAssertTrue(back)

        var report: [String: Any] = ["environment": CompatibilityMatrixTests.environment, "quote": quote]
        for (theme, expect) in [(ReaderTheme.paper, Self.paper), (.night, Self.night)] {
            var settings = s.settings
            settings.theme = theme
            s.apply(settings: settings)
            await s.settle()
            // Wait for the decoration to be (re)drawn with this theme's colors and to cover the quote.
            var inspection: ReaderProbe.Inspection?
            let drawn = await ReaderProbe.wait(timeout: .seconds(10)) {
                inspection = try? await ReaderProbe.inspect(s, exact: quote, prefix: saved.anchor.prefix, highlightID: saved.id)
                guard let i = inspection, i.covered, !i.boxes.isEmpty, i.renderings == 1 else { return false }
                return i.boxes.allSatisfy { rgb($0["bg"] as? String) == expect.fill }
            }
            let i = try XCTUnwrap(inspection)
            XCTAssertTrue(drawn, "\(theme): decoration not drawn with the expected fill: \(i.raw)")
            XCTAssertTrue(i.visible, "\(theme): quote not on screen: \(i.raw)")
            XCTAssertEqual(i.renderings, 1, "\(theme): highlight drawn \(i.renderings) times")
            for box in i.boxes {
                XCTAssertEqual(rgb(box["bg"] as? String), expect.fill, "\(theme) fill")
                XCTAssertEqual(rgb(box["ub"] as? String), expect.underline, "\(theme) underline color")
                XCTAssertEqual(box["uw"] as? String, "\(SylviaReaderStyle.underlinePixels)px", "\(theme) underline width")
                XCTAssertEqual(box["us"] as? String, "solid", "\(theme) underline style")
                XCTAssertEqual(box["z"] as? String, "-1", "\(theme) drawn behind the text")
            }
            let style = try await ReaderProbe.call(s, "style('p')")
            XCTAssertEqual(rgb(style["rootBackground"] as? String), expect.ground, "\(theme) ground")

            // Pixels: inside the first box, the dominant color is the fill (glyphs are ink); the bottom row is the underline.
            try await Task.sleep(for: .milliseconds(400))
            let snap = await ReaderProbe.snapshot(s)
            let image = try XCTUnwrap(snap, "no snapshot")
            let first = try XCTUnwrap(i.boxes.first)
            let rect = CGRect(x: first["x"] as? Double ?? 0, y: first["y"] as? Double ?? 0, width: first["w"] as? Double ?? 0, height: first["h"] as? Double ?? 0)
            let pixels = try XCTUnwrap(PixelSampler(image: image))
            let fillSample = pixels.dominant(in: rect.insetBy(dx: 2, dy: 2).divided(atDistance: rect.height - 6, from: .minYEdge).slice)
            let underlineSample = pixels.dominant(in: CGRect(x: rect.minX + 2, y: rect.maxY - 1.5, width: rect.width - 4, height: 1))
            XCTAssertTrue(close(fillSample, expect.fill), "\(theme) fill pixels \(fillSample) vs \(expect.fill)")
            XCTAssertTrue(close(underlineSample, expect.underline), "\(theme) underline pixels \(underlineSample) vs \(expect.underline)")
            let name = "highlight-\(theme.rawValue).png"
            ReaderProbe.writePNG(name, image)
            report[theme.rawValue] = [
                "boxes": i.boxes, "covered": i.covered, "visible": i.visible, "quote_lines": i.quoteRectCount, "renderings": i.renderings,
                "pixel_fill_dominant": fillSample, "pixel_underline_row": underlineSample, "screenshot": name,
                "luminance_fill": luminance(expect.fill), "luminance_underline": luminance(expect.underline),
                "luminance_ground": luminance(expect.ground),
            ]
        }
        ReaderProbe.writeEvidence("highlight-decoration.json", json: report)
    }

    /// Back-to-back preference changes (the race recorded in decoration-race.json) converge to exactly one set
    /// of boxes in the last theme's colors once the adapter's refresh has run.
    func testRapidSettingsChangesConverge() async throws {
        let screen = try await TestHost.open("se-meditations.epub")
        let s = screen.session
        let quote = ScenarioRunner.anchorQuote
        let moved = await ReaderProbe.goToText(s, href: ScenarioRunner.anchorHref, exact: quote)
        XCTAssertTrue(moved)
        _ = try await ReaderProbe.call(s, "selectText(\(ReaderProbe.jsString(quote)), null)")
        _ = await ReaderProbe.waitForSelection(s)
        let captured = await screen.capture(note: nil)
        let saved = try XCTUnwrap(captured)
        await s.settle()
        let single = try await ReaderProbe.inspect(s, exact: quote, prefix: saved.anchor.prefix, highlightID: saved.id).boxes.count
        XCTAssertGreaterThan(single, 0)
        var settings = s.settings
        for theme in [ReaderTheme.paper, .night, .paper, .night] {
            settings.theme = theme
            s.apply(settings: settings)
        }
        settings.fontSizePoints = 21
        s.apply(settings: settings)
        await s.settle()
        let converged = await ReaderProbe.wait(timeout: .seconds(8)) {
            guard let i = try? await ReaderProbe.inspect(s, exact: quote, prefix: saved.anchor.prefix, highlightID: saved.id) else { return false }
            return i.covered && i.renderings == 1 && i.boxes.allSatisfy { rgb($0["bg"] as? String) == Self.night.fill }
        }
        let final = try await ReaderProbe.inspect(s, exact: quote, prefix: saved.anchor.prefix, highlightID: saved.id)
        let all = try await ReaderProbe.call(s, "inspect('', '', null)")
        XCTAssertTrue(converged, "boxes did not converge: \(final.raw)")
        XCTAssertEqual((all["boxes"] as? [[String: Any]])?.count, final.boxes.count, "no stray boxes from earlier themes")
        XCTAssertEqual(final.renderings, 1)
        ReaderProbe.writeEvidence("highlight-rapid-settings.json", json: [
            "boxes_before": single, "boxes_after": final.boxes.count, "quote_lines_after": final.quoteRectCount,
            "all_highlight_boxes_in_dom": (all["boxes"] as? [[String: Any]])?.count ?? -1, "refreshes": s.highlightRefreshCount,
            "renderings_after": final.renderings, "duplicate_repairs": s.duplicateRepairs,
        ])
    }

    /// Readium alone versus the adapter, for the race the adapter works around: a decoration drawn, then two
    /// preference changes back to back (Paper, Night) with the Night decoration applied immediately (what a quick
    /// theme switch right after saving a highlight does). The Readium-only path calls the navigator directly, so the
    /// adapter's own duplicate check never runs on it; the boxes left in the DOM 4 s later are recorded, not asserted
    /// (the race depends on timing). The assertion is on the adapter path, which must end with exactly one rendering in
    /// the Night colors every time.
    func testDecorationRaceReadiumAloneVersusAdapter() async throws {
        var runs: [[String: Any]] = []
        for attempt in 0 ..< 3 {
            let screen = try await TestHost.open("se-meditations.epub")
            let s = screen.session
            let quote = ScenarioRunner.anchorQuote
            let moved = await ReaderProbe.goToText(s, href: ScenarioRunner.anchorHref, exact: quote)
            XCTAssertTrue(moved)
            _ = try await ReaderProbe.call(s, "selectText(\(ReaderProbe.jsString(quote)), null)")
            let selected = await ReaderProbe.waitForSelection(s)
            let selection = try XCTUnwrap(selected)
            s.clearSelection()
            let locator = try ReadiumReaderSession.readiumLocator(selection.locator)
            let id = "race-\(attempt)"
            func decoration(_ theme: ReaderTheme) -> Decoration {
                Decoration(id: id, locator: locator, style: SylviaReaderStyle.highlightStyle(theme: theme))
            }

            // Readium alone.
            var paper = s.settings
            paper.theme = .paper
            var night = paper
            night.theme = .night
            s.navigator.apply(decorations: [decoration(.paper)], in: ReadiumReaderSession.highlightGroup)
            s.navigator.submitPreferences(SylviaReaderStyle.preferences(for: paper))
            s.navigator.submitPreferences(SylviaReaderStyle.preferences(for: night))
            s.navigator.apply(decorations: [decoration(.night)], in: ReadiumReaderSession.highlightGroup)
            var samples: [[String: Any]] = []
            for second in 1 ... 4 {
                try await Task.sleep(for: .seconds(1))
                let raw = try await ReaderProbe.call(s, "inspect('', '', null)")
                let boxes = (raw["boxes"] as? [[String: Any]]) ?? []
                samples.append(["after_s": second, "boxes": boxes.count, "item_containers": raw["itemContainers"] as? Int ?? -1,
                                "fills": Array(Set(boxes.compactMap { $0["bg"] as? String })).sorted()])
            }
            let quoteLines = (try await ReaderProbe.call(s, "inspect(\(ReaderProbe.jsString(quote)), '', null)"))["quoteRects"] as? Int ?? -1
            s.navigator.apply(decorations: [], in: ReadiumReaderSession.highlightGroup)
            try await Task.sleep(for: .milliseconds(300))

            // Adapter: the same highlight as a saved record, then Paper and Night through apply(settings:).
            let presentation = HighlightPresentation(id: id, locator: selection.locator)
            s.apply(settings: paper)
            await s.settle()
            s.apply(highlights: [presentation])
            s.apply(settings: paper)
            s.apply(settings: night)
            await s.settle()
            var adapted = try await ReaderProbe.inspect(s, exact: quote, prefix: selection.prefix, highlightID: id)
            let converged = await ReaderProbe.wait(timeout: .seconds(8)) {
                adapted = (try? await ReaderProbe.inspect(s, exact: quote, prefix: selection.prefix, highlightID: id)) ?? adapted
                return adapted.covered && adapted.renderings == 1 && adapted.boxes.allSatisfy { rgb($0["bg"] as? String) == Self.night.fill }
            }
            XCTAssertTrue(converged, "attempt \(attempt): adapter did not converge: \(adapted.raw)")
            runs.append([
                "attempt": attempt, "quote_lines_in_night": quoteLines, "readium_alone": samples,
                "adapter_boxes": adapted.boxes.count, "adapter_renderings": adapted.renderings, "adapter_converged": converged,
                "adapter_refreshes": s.highlightRefreshCount, "adapter_duplicate_repairs": s.duplicateRepairs,
            ])
            TestHost.tearDown()
        }
        let duplicated = runs.filter { run in
            ((run["readium_alone"] as? [[String: Any]])?.last?["item_containers"] as? Int ?? 0) > 1
        }.count
        ReaderProbe.writeEvidence("decoration-race.json", json: [
            "environment": CompatibilityMatrixTests.environment,
            "what": "se-meditations.epub, book-1, the 'From my governor' passage. Readium alone: apply(decorations, Paper), submitPreferences(Paper), submitPreferences(Night), apply(decorations, Night), DOM sampled each second for 4 s. Adapter: apply(highlights:), apply(settings: Paper), apply(settings: Night), settle.",
            "readium_alone_runs_left_with_duplicate_renderings": duplicated, "attempts": runs.count,
            "runs": runs,
        ])
    }

    /// The adapter's duplicate repair: a second copy of the highlight's item container (what Readium leaves after the
    /// race recorded in decoration-race.json) is detected and the group is redrawn once.
    func testDuplicateRenderingIsRepaired() async throws {
        let screen = try await TestHost.open("se-meditations.epub")
        let s = screen.session
        let quote = ScenarioRunner.anchorQuote
        let moved = await ReaderProbe.goToText(s, href: ScenarioRunner.anchorHref, exact: quote)
        XCTAssertTrue(moved)
        _ = try await ReaderProbe.call(s, "selectText(\(ReaderProbe.jsString(quote)), null)")
        _ = await ReaderProbe.waitForSelection(s)
        let captured = await screen.capture(note: nil)
        let saved = try XCTUnwrap(captured)
        try await Task.sleep(for: .seconds(1.5))
        let before = try await ReaderProbe.inspect(s, exact: quote, prefix: saved.anchor.prefix, highlightID: saved.id)
        XCTAssertEqual(before.renderings, 1)
        let nothingToRepair = await s.repairDuplicateHighlights()
        XCTAssertFalse(nothingToRepair)
        // Inject a duplicate: clone the highlight's item container next to it.
        _ = try await ReaderProbe.evaluate(s, """
        (function () { const box = document.querySelector('[data-sylvia-highlight-id="\(saved.id)"]');
          const item = box.parentElement; item.parentElement.appendChild(item.cloneNode(true)); return true; })()
        """)
        let injected = try await ReaderProbe.inspect(s, exact: quote, prefix: saved.anchor.prefix, highlightID: saved.id)
        XCTAssertEqual(injected.renderings, 2)
        let repaired = await s.repairDuplicateHighlights()
        XCTAssertTrue(repaired)
        var after = injected
        let ok = await ReaderProbe.wait(timeout: .seconds(5)) {
            after = (try? await ReaderProbe.inspect(s, exact: quote, prefix: saved.anchor.prefix, highlightID: saved.id)) ?? after
            return after.renderings == 1 && after.covered
        }
        XCTAssertTrue(ok, "\(after.raw)")
        XCTAssertEqual(s.duplicateRepairs, 1)
    }

    /// A selection across two paragraphs: Readium's highlight text is `selection.toString()` (one "\n" between
    /// paragraphs) while the DOM text has the source indentation; the decoration must still find the range.
    func testCrossParagraphSelectionStillDecorates() async throws {
        let screen = try await TestHost.open("se-meditations.epub")
        let s = screen.session
        let moved = await ReaderProbe.goToText(s, href: ScenarioRunner.anchorHref, exact: "government of my temper.")
        XCTAssertTrue(moved)
        _ = try await ReaderProbe.call(s, "selectBetween(\(ReaderProbe.jsString("government of my temper.")), \(ReaderProbe.jsString("From the reputation")))")
        let waited = await ReaderProbe.waitForSelection(s)
        let sel = try XCTUnwrap(waited)
        let captured = await screen.capture(note: nil)
        let saved = try XCTUnwrap(captured)
        let drawn = await ReaderProbe.wait(timeout: .seconds(8)) {
            let boxes = (try? await ReaderProbe.call(s, "inspect('', '', \(ReaderProbe.jsString(saved.id)))"))?["boxes"] as? [[String: Any]]
            return (boxes?.count ?? 0) >= 2
        }
        let raw = try await ReaderProbe.call(s, "inspect('', '', \(ReaderProbe.jsString(saved.id)))")
        ReaderProbe.writeEvidence("highlight-cross-paragraph.json", json: ["selection": sel.exactText, "result": raw, "drawn": drawn])
        XCTAssertTrue(drawn, "cross-paragraph highlight not drawn: \(raw)")
    }

    func close(_ a: [Int], _ b: [Int], tolerance: Int = 6) -> Bool {
        a.count >= 3 && zip(a.prefix(3), b).allSatisfy { abs($0 - $1) <= tolerance }
    }

    /// WCAG relative luminance, to show the underline still separates from the fill once color is removed.
    func luminance(_ c: [Int]) -> Double {
        func ch(_ v: Int) -> Double { let x = Double(v) / 255; return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return ((0.2126 * ch(c[0]) + 0.7152 * ch(c[1]) + 0.0722 * ch(c[2])) * 1000).rounded() / 1000
    }
}

/// Reads RGBA pixels of a snapshot; coordinates are in points (the web view's CSS px).
struct PixelSampler {
    let width: Int, height: Int, scale: CGFloat
    let bytes: [UInt8]

    init?(image: UIImage) {
        guard let cg = image.cgImage else { return nil }
        width = cg.width
        height = cg.height
        scale = image.scale
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = buffer
    }

    func pixel(_ x: Int, _ y: Int) -> [Int] {
        let i = (y * width + x) * 4
        return [Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2])]
    }

    /// Most frequent color in `rect` (points).
    func dominant(in rect: CGRect) -> [Int] {
        var counts: [[Int]: Int] = [:]
        let x0 = max(0, Int(rect.minX * scale)), x1 = min(width - 1, Int(rect.maxX * scale))
        let y0 = max(0, Int(rect.minY * scale)), y1 = min(height - 1, Int(rect.maxY * scale))
        guard x0 <= x1, y0 <= y1 else { return [] }
        for y in y0 ... y1 { for x in x0 ... x1 { counts[pixel(x, y), default: 0] += 1 } }
        return counts.max { $0.value < $1.value }?.key ?? []
    }
}
