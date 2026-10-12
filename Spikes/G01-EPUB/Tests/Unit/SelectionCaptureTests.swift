@testable import EPUBHarness
import Foundation
import G01EPUBCore
import XCTest

/// Deliverable 2: selection capture through Readium's own selection pipeline (simulator).
///
/// Automated: a DOM Range is created in the rendered resource and added to `window.getSelection()`. From there on
/// everything is Readium's: its `selectionchange` listener builds `{highlight, before, after}`, posts it to native
/// code, and `EPUBNavigatorViewController.currentSelection` returns the locator. Not automated: the finger gesture,
/// the selection handles and the edit menu (device checklist).
@MainActor final class SelectionCaptureTests: XCTestCase {
    static var samples: [[String: Any]] = []

    override func tearDown() async throws { TestHost.tearDown() }

    override class func tearDown() {
        MainActor.assumeIsolated {
            ReaderProbe.writeEvidence("selection-samples.json", json: ["environment": CompatibilityMatrixTests.environment, "samples": samples])
        }
        super.tearDown()
    }

    func select(_ session: ReadiumReaderSession, _ js: String) async throws -> (ReaderSelection, [String: Any]) {
        session.clearSelection()
        try await Task.sleep(for: .milliseconds(150))
        let result = try await ReaderProbe.call(session, js)
        XCTAssertEqual(result["ok"] as? Bool, true, "DOM selection failed: \(result)")
        guard let selection = await ReaderProbe.waitForSelection(session) else { throw TestFailure(description: "Readium reported no selection") }
        return (selection, result)
    }

    func record(_ name: String, _ s: ReaderSelection, extra: [String: Any] = [:]) {
        var row: [String: Any] = [
            "case": name, "exact_text": s.exactText, "prefix": s.prefix, "suffix": s.suffix,
            "exact_utf16_length": (s.exactText as NSString).length, "exact_scalar_length": s.exactText.unicodeScalars.count,
            "locator_json": s.locator.json, "href": s.locator.href,
        ]
        for (k, v) in extra { row[k] = v }
        Self.samples.append(row)
    }

    static func collapse(_ s: String) -> String { s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }

    func testKnownPassageWithCurlyApostrophe() async throws {
        let screen = try await TestHost.open("se-meditations.epub")
        let s = screen.session
        let quote = ScenarioRunner.anchorQuote
        let moved1 = await ReaderProbe.goToText(s, href: ScenarioRunner.anchorHref, exact: quote)
        XCTAssertTrue(moved1)
        let (sel, _) = try await select(s, "selectText(\(ReaderProbe.jsString(quote)), null)")
        XCTAssertEqual(sel.exactText, quote)
        XCTAssertTrue(sel.exactText.contains("\u{2019}"))
        XCTAssertEqual(sel.locator.href, ScenarioRunner.anchorHref)
        XCTAssertTrue(Self.collapse(sel.prefix).hasSuffix("a man should spend liberally."), sel.prefix)
        XCTAssertTrue(Self.collapse(sel.suffix).hasPrefix("; from him too I learned endurance"), sel.suffix)
        // Readium's selection locator is the page location plus the text: no CSS selector, no DOM range, no CFI.
        XCTAssertEqual(sel.locator.otherLocationKeys, [])
        record("known-passage-u2019", sel)
    }

    func testSelectionAcrossAnElementBoundary() async throws {
        let screen = try await TestHost.open("se-meditations.epub")
        let s = screen.session
        // "From my mother,<a …>3</a> piety and beneficence": the selection crosses the noteref element.
        let moved2 = await ReaderProbe.goToText(s, href: ScenarioRunner.anchorHref, exact: "piety and beneficence")
        XCTAssertTrue(moved2)
        let (sel, _) = try await select(s, "selectText(\(ReaderProbe.jsString("From my mother,3 piety and beneficence")), null)")
        XCTAssertEqual(sel.exactText, "From my mother,3 piety and beneficence", "the noteref number is part of the DOM text")
        record("cross-element-noteref", sel)

        // Across two paragraphs: the selected string carries the inter-paragraph whitespace verbatim.
        let (para, _) = try await select(s, "selectBetween(\(ReaderProbe.jsString("government of my temper.")), \(ReaderProbe.jsString("From the reputation")))")
        XCTAssertEqual(Self.collapse(para.exactText), "government of my temper. From the reputation")
        XCTAssertTrue(para.exactText.contains("\n"), "raw selection keeps the source whitespace: \(para.exactText.debugDescription)")
        record("cross-paragraph", para)
    }

    func testGreekSelection() async throws {
        let screen = try await TestHost.open("se-meditations.epub")
        let s = screen.session
        let quote = "that I am a member [μέλος] of the system of rational beings"
        let moved3 = await ReaderProbe.goToText(s, href: "epub/text/book-7.xhtml", exact: quote)
        XCTAssertTrue(moved3)
        let (sel, _) = try await select(s, "selectText(\(ReaderProbe.jsString(quote)), null)")
        XCTAssertEqual(sel.exactText, quote)
        XCTAssertEqual(sel.locator.href, "epub/text/book-7.xhtml")
        let extraction = await EPUBExtraction.extract(s.opened)
        let anchor = try CaptureBuilder.anchor(for: sel, assetID: "fixture", assetDigest: s.opened.sha256, extraction: extraction)
        let blocks = extraction.first { $0.href == "epub/text/book-7.xhtml" }?.blocks.filter { $0.text.contains("\u{3bc}\u{3ad}\u{3bb}\u{3bf}\u{3c2}") } ?? []
        record("greek-in-i-lang-el", sel, extra: [
            "text_offsets_mapped": anchor.textOffsets != nil,
            "extraction_blocks_containing_greek": blocks.map { b -> String in
                guard let r = b.text.range(of: "\u{3bc}\u{3ad}\u{3bb}\u{3bf}\u{3c2}") else { return b.text }
                let lo = b.text.index(r.lowerBound, offsetBy: -40, limitedBy: b.text.startIndex) ?? b.text.startIndex
                let hi = b.text.index(r.upperBound, offsetBy: 40, limitedBy: b.text.endIndex) ?? b.text.endIndex
                return String(b.text[lo ..< hi])
            },
        ])
    }

    /// Readium 3.11.0 copies the navigator's current location into the selection locator. Right after a jump into
    /// another resource that location can still be the previous resource. The adapter's `captureSelection()` must
    /// always name the resource that holds the text, and the corrected locator must reopen and decorate the passage.
    func testSelectionRightAfterAJumpNamesTheRightResource() async throws {
        let quote = "that I am a member [μέλος] of the system of rational beings"
        var runs: [[String: Any]] = []
        var readiumWrong = 0
        for attempt in 0 ..< 3 {
            let screen = try await TestHost.open("se-meditations.epub")
            let s = screen.session
            let first = await ReaderProbe.goToText(s, href: ScenarioRunner.anchorHref, exact: ScenarioRunner.anchorQuote)
            XCTAssertTrue(first)
            try await Task.sleep(for: .milliseconds(800))
            // A jump into book 7 (the adapter's go, with its settle-and-repeat) and an immediate selection, as in
            // AnchorSamplesTests, where Readium's selection locator first showed the previous resource.
            let second = await ReaderProbe.goToText(s, href: "epub/text/book-7.xhtml", exact: quote)
            XCTAssertTrue(second)
            let selected = try await ReaderProbe.call(s, "selectText(\(ReaderProbe.jsString(quote)), null)")
            XCTAssertEqual(selected["ok"] as? Bool, true, "\(selected)")
            var raw: ReaderSelection?
            _ = await ReaderProbe.wait(timeout: .seconds(5)) {
                raw = s.currentSelection
                return raw?.exactText == quote
            }
            let readium = try XCTUnwrap(raw, "Readium reported no selection")
            let confirmed = await s.captureSelection()
            let sel = try XCTUnwrap(confirmed, "the adapter could not confirm the selection")
            XCTAssertEqual(sel.exactText, quote)
            XCTAssertEqual(sel.locator.href, "epub/text/book-7.xhtml", "captured anchor names the wrong resource")
            if readium.locator.href != "epub/text/book-7.xhtml" {
                readiumWrong += 1
                XCTAssertGreaterThan(s.selectionHrefCorrections, 0)
                XCTAssertNil(sel.locator.progression, "a corrected locator must not carry the other resource's progression")
            }
            // The captured locator reopens and decorates the passage from elsewhere in the book.
            s.clearSelection()
            s.apply(highlights: [HighlightPresentation(id: "jump-\(attempt)", locator: sel.locator)])
            let away = await s.followLink(href: ScenarioRunner.anchorHref)
            XCTAssertTrue(away)
            let back = await s.navigate(to: sel.locator)
            XCTAssertTrue(back)
            var inspection: ReaderProbe.Inspection?
            let drawn = await ReaderProbe.wait(timeout: .seconds(8)) {
                inspection = try? await ReaderProbe.inspect(s, exact: quote, prefix: sel.prefix, highlightID: "jump-\(attempt)")
                return inspection?.covered == true && inspection?.visible == true
            }
            XCTAssertTrue(drawn, "corrected locator did not reopen and decorate the passage: \(inspection?.raw ?? [:])")
            runs.append(["attempt": attempt, "readium_selection_href": readium.locator.href,
                         "readium_selection_progression": readium.locator.progression ?? NSNull(),
                         "confirmed_href": sel.locator.href, "confirmed_locator": sel.locator.json,
                         "corrections": s.selectionHrefCorrections, "reopened_and_drawn": drawn])
            TestHost.tearDown()
        }
        ReaderProbe.writeEvidence("selection-after-jump.json", json: [
            "environment": CompatibilityMatrixTests.environment,
            "what": "se-meditations.epub: at 'From my governor' in book-1, the adapter's jump into book-7, an immediate DOM selection of the Greek passage, then Readium's currentSelection versus the adapter's captureSelection().",
            "readium_named_the_wrong_resource": readiumWrong, "attempts": runs.count, "runs": runs,
        ])
    }

    /// Non-BMP text: Readium and the DOM count UTF-16 code units; Sylvia's portable offsets count scalars.
    func testNonBMPSelectionAndOffsetConversion() async throws {
        let screen = try await TestHost.open("g01-unicode.epub")
        let s = screen.session
        let fraktur = "\u{1D509}\u{1D52F}\u{1D51E}\u{1D528}\u{1D531}\u{1D532}\u{1D52F}"
        let quote = "\(fraktur) letters beside the river"
        let moved4 = await ReaderProbe.goToText(s, href: "OEBPS/c1.xhtml", exact: quote)
        XCTAssertTrue(moved4)
        let (sel, _) = try await select(s, "selectText(\(ReaderProbe.jsString(quote)), null)")
        XCTAssertEqual(sel.exactText, quote)
        XCTAssertEqual((sel.exactText as NSString).length, sel.exactText.unicodeScalars.count + 7)

        // Map the selection onto Sylvia's extraction (scalars) and back to UTF-16; compare with the DOM's own index.
        let extraction = await EPUBExtraction.extract(s.publication)
        let anchor = try CaptureBuilder.anchor(for: sel, assetID: "fixture", assetDigest: s.opened.sha256, extraction: extraction)
        let offsets = try XCTUnwrap(anchor.textOffsets, "selection not mapped onto the extraction")
        XCTAssertEqual(offsets.unit, "unicode_scalar")
        let block = try XCTUnwrap(extraction.first { $0.href == "OEBPS/c1.xhtml" }?.blocks[offsets.blockIndex])
        XCTAssertEqual(TextOffsets.substring(block.text, scalarRange: offsets.start ..< offsets.end), quote)
        let utf16Start = try XCTUnwrap(TextOffsets.utf16Offset(fromScalarOffset: offsets.start, in: block.text))
        let domIndex = try await ReaderProbe.evaluate(s, "document.getElementById('p-nonbmp').textContent.indexOf(\(ReaderProbe.jsString(quote)))")
        XCTAssertEqual(Int(domIndex), utf16Start, "adapter UTF-16 offset must equal the DOM's indexOf")
        // An offset after the Fraktur word: scalars and UTF-16 differ by 7.
        let after = try XCTUnwrap(block.text.range(of: "letters"))
        let scalarAfter = TextOffsets.scalarRange(of: after, in: block.text).lowerBound
        let domAfter = try await ReaderProbe.evaluate(s, "document.getElementById('p-nonbmp').textContent.indexOf('letters')")
        XCTAssertEqual(Int(domAfter), scalarAfter + 7)
        XCTAssertEqual(TextOffsets.utf16Offset(fromScalarOffset: scalarAfter, in: block.text), Int(domAfter))
        record("non-bmp-fraktur", sel, extra: [
            "sylvia_block_index": offsets.blockIndex, "sylvia_scalar_start": offsets.start, "sylvia_scalar_end": offsets.end,
            "dom_utf16_start_in_paragraph": Int(domIndex) ?? -1,
        ])

        // Combining sequence (e + U+0301) and CJK.
        let (comb, _) = try await select(s, "selectText(\(ReaderProbe.jsString("signed it Ame\u{0301}lie")), null)")
        XCTAssertEqual(comb.exactText, "signed it Ame\u{0301}lie")
        XCTAssertEqual(comb.exactText.unicodeScalars.count, "signed it Amelie".count + 1)
        record("combining-acute", comb)
        let (cjk, _) = try await select(s, "selectText(\(ReaderProbe.jsString("\u{6f22}\u{5b57} for \u{201c}Han characters\u{201d}")), null)")
        XCTAssertEqual(cjk.exactText, "\u{6f22}\u{5b57} for \u{201c}Han characters\u{201d}")
        record("cjk-and-quotes", cjk)
    }

    /// The selected string is never truncated: a whole long resource comes back complete.
    func testLongSelectionIsNotTruncated() async throws {
        let screen = try await TestHost.open("se-middlemarch.epub")
        let s = screen.session
        // The longest chapter in Middlemarch by bytes.
        let entries = ZIPPreflight.inspect(fileAt: try TestHost.fixtureURL("se-middlemarch.epub")).entries
        let biggest = try XCTUnwrap(entries.filter { $0.name.hasSuffix(".xhtml") }.max { $0.uncompressedSize < $1.uncompressedSize })
        let longest = (href: String(biggest.name), bytes: Int(biggest.uncompressedSize))
        let moved5 = await s.followLink(href: longest.href)
        XCTAssertTrue(moved5)
        try await Task.sleep(for: .seconds(1))
        let (sel, raw) = try await select(s, "selectAll()")
        let jsLength = (raw["selectionText"] as? String).map { ($0 as NSString).length } ?? -1
        XCTAssertEqual((sel.exactText as NSString).length, jsLength, "Readium's highlight must equal window.getSelection().toString()")
        XCTAssertGreaterThan(jsLength, 20_000)
        Self.samples.append([
            "case": "long-whole-resource", "href": sel.locator.href, "resource_bytes": longest.bytes,
            "exact_utf16_length": (sel.exactText as NSString).length, "dom_selection_utf16_length": jsLength,
            "prefix_length": sel.prefix.count, "suffix_length": sel.suffix.count,
        ])
    }

    /// A quotation continuing into the next resource becomes ordered anchors, one per resource, nothing dropped.
    func testQuotationAcrossResourcesBecomesOrderedAnchors() async throws {
        let screen = try await TestHost.open("g01-unicode.epub")
        let s = screen.session
        let endOfC1 = "The first chapter closes on this sentence, which a reader might keep together with the opening of the next."
        let startOfC2 = "The second chapter opens here, continuing the thought across the resource boundary."
        let moved6 = await ReaderProbe.goToText(s, href: "OEBPS/c1.xhtml", exact: endOfC1)
        XCTAssertTrue(moved6)
        let (a, _) = try await select(s, "selectText(\(ReaderProbe.jsString(endOfC1)), null)")
        // Each resource is its own document: the end text of c2 is not reachable from c1's DOM.
        let reachable = try await ReaderProbe.evaluate(s, "document.body.textContent.indexOf(\(ReaderProbe.jsString(startOfC2)))")
        XCTAssertEqual(reachable, "-1")
        let moved7 = await ReaderProbe.goToText(s, href: "OEBPS/c2.xhtml", exact: startOfC2)
        XCTAssertTrue(moved7)
        try await Task.sleep(for: .milliseconds(500))
        let (b, _) = try await select(s, "selectText(\(ReaderProbe.jsString(startOfC2)), null)")

        let extraction = await EPUBExtraction.extract(s.publication)
        let q = try CaptureBuilder.quotation(from: [a, b], assetID: "fixture", assetDigest: s.opened.sha256, extraction: extraction)
        XCTAssertEqual(q.anchors.count, 2)
        XCTAssertEqual(q.anchors.map(\.resourceHref), ["OEBPS/c1.xhtml", "OEBPS/c2.xhtml"])
        XCTAssertEqual(q.anchors.compactMap(\.segment).map(\.index), [0, 1])
        XCTAssertEqual(q.quotedText, endOfC1 + CaptureBuilder.segmentSeparator + startOfC2)
        XCTAssertNotNil(q.anchors[0].textOffsets)
        XCTAssertNotNil(q.anchors[1].textOffsets)

        // Both segments draw as highlights in their own resource.
        s.apply(highlights: [HighlightPresentation(id: "seg-0", locator: a.locator), HighlightPresentation(id: "seg-1", locator: b.locator)])
        let ok1 = await ReaderProbe.wait { (try? await ReaderProbe.inspect(s, exact: startOfC2, prefix: "", highlightID: "seg-1"))?.covered == true }
        XCTAssertTrue(ok1, "segment 1 not drawn in c2")
        let moved8 = await ReaderProbe.goToText(s, href: "OEBPS/c1.xhtml", exact: endOfC1)
        XCTAssertTrue(moved8)
        let ok0 = await ReaderProbe.wait { (try? await ReaderProbe.inspect(s, exact: endOfC1, prefix: "", highlightID: "seg-0"))?.covered == true }
        XCTAssertTrue(ok0, "segment 0 not drawn in c1")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        Self.samples.append([
            "case": "quotation-across-resources", "quoted_text": q.quotedText,
            "anchors": try JSONSerialization.jsonObject(with: encoder.encode(q.anchors)),
        ])
    }
}
