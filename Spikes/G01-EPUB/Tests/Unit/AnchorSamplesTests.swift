@testable import EPUBHarness
import Foundation
import G01EPUBCore
@preconcurrency import ReadiumShared
import XCTest

/// Deliverable 9: real locators captured through the adapter, written with the proposed portable EPUB anchor
/// envelope to `anchor-samples.json` for the later anchor schema (plan 7.5, Appendix A.1). Simulator.
@MainActor final class AnchorSamplesTests: XCTestCase {
    override func tearDown() async throws { TestHost.tearDown() }

    struct Sample { var name: String; var note: String; var anchors: [PortableEPUBAnchor]; var quotedText: String? }

    /// Which Readium locator fields a locator JSON actually carries.
    static func fields(_ json: String) -> [String] {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return [] }
        var out: [String] = obj.keys.filter { $0 != "locations" && $0 != "text" }.sorted()
        if let l = obj["locations"] as? [String: Any] { out += l.keys.sorted().map { "locations.\($0)" } }
        if let t = obj["text"] as? [String: Any] { out += t.keys.sorted().map { "text.\($0)" } }
        return out
    }

    func select(_ s: ReadiumReaderSession, _ js: String) async throws -> ReaderSelection {
        s.clearSelection()
        try await Task.sleep(for: .milliseconds(150))
        let r = try await ReaderProbe.call(s, js)
        XCTAssertEqual(r["ok"] as? Bool, true, "\(r)")
        // Wait for Readium to report this selection (not a stale one from the previous page).
        let expected = r["selectionText"] as? String
        var found: ReaderSelection?
        _ = await ReaderProbe.wait(timeout: .seconds(5)) {
            found = s.currentSelection
            return found != nil && found?.exactText == expected
        }
        guard let raw = found, raw.exactText == expected else { throw TestFailure(description: "Readium did not report the selection for \(js)") }
        guard let sel = await s.captureSelection() else { throw TestFailure(description: "the adapter could not confirm the selection for \(js)") }
        Self.rawSelectionHrefs.append(["exact_text_prefix": String(raw.exactText.prefix(40)), "readium_selection_href": raw.locator.href,
                                       "confirmed_href": sel.locator.href, "corrected": raw.locator.href != sel.locator.href])
        return sel
    }

    /// Readium's own selection href next to the adapter's confirmed one, for every capture (see `captureSelection()`).
    static var rawSelectionHrefs: [[String: Any]] = []

    func testCaptureAnchorSamples() async throws {
        var samples: [Sample] = []
        var pgHref = ""
        Self.rawSelectionHrefs = []

        // Standard Ebooks EPUB 3: known passage (U+2019), a selection across a noteref element, Greek.
        do {
            let screen = try await TestHost.open("se-meditations.epub")
            let s = screen.session
            let extraction = await EPUBExtraction.extract(s.opened)
            func anchor(_ sel: ReaderSelection) throws -> PortableEPUBAnchor {
                try CaptureBuilder.anchor(for: sel, assetID: "fixture:se-meditations.epub", assetDigest: s.opened.sha256, extraction: extraction)
            }
            let moved = await ReaderProbe.goToText(s, href: ScenarioRunner.anchorHref, exact: ScenarioRunner.anchorQuote)
            XCTAssertTrue(moved)
            let known = try await select(s, "selectText(\(ReaderProbe.jsString(ScenarioRunner.anchorQuote)), null)")
            let knownAnchor = try anchor(known)
            XCTAssertNotNil(knownAnchor.textOffsets, "known passage not mapped onto the extraction")
            samples.append(Sample(name: "se-epub3-known-passage", note: "Selection inside one paragraph; contains U+2019.", anchors: [knownAnchor], quotedText: known.exactText))
            let cross = try await select(s, "selectText(\(ReaderProbe.jsString("From my mother,3 piety and beneficence")), null)")
            samples.append(Sample(name: "se-epub3-across-noteref", note: "Selection crossing an <a epub:type=\"noteref\"> element; the note number is part of the selected text.", anchors: [try anchor(cross)], quotedText: cross.exactText))
            let greekQuote = "that I am a member [μέλος] of the system of rational beings"
            let movedGreek = await ReaderProbe.goToText(s, href: "epub/text/book-7.xhtml", exact: greekQuote)
            XCTAssertTrue(movedGreek)
            let greek = try await select(s, "selectText(\(ReaderProbe.jsString(greekQuote)), null)")
            samples.append(Sample(name: "se-epub3-greek", note: "Greek inside <i lang=\"el\">.", anchors: [try anchor(greek)], quotedText: greek.exactText))

            // A reading position (what "continue reading" stores) and a search hit (what "Search this book" reopens).
            let position = try XCTUnwrap(s.currentLocator)
            let hits = try await s.search("the perception of this will be more apparent to thee")
            let hit = try XCTUnwrap(hits.first)
            Self.positions.append(["name": "se-epub3-reading-position", "fields": Self.fields(position.json), "reader_locator": try G01EPUBCore.JSONValue(jsonString: position.json)])
            Self.positions.append(["name": "se-epub3-search-hit", "fields": Self.fields(hit.json), "reader_locator": try G01EPUBCore.JSONValue(jsonString: hit.json)])
            TestHost.tearDown()
        }

        // Project Gutenberg EPUB 2: href forms and line-wrapped source text.
        do {
            let screen = try await TestHost.open("pg-walden-epub2.epub")
            let s = screen.session
            let extraction = await EPUBExtraction.extract(s.opened)
            let phrase = "I wished to live deliberately"
            let resource = try XCTUnwrap(extraction.first { r in r.blocks.contains { $0.text.contains(phrase) } }, "phrase not in the EPUB 2 extraction")
            pgHref = resource.href
            let block = try XCTUnwrap(resource.blocks.first { $0.text.contains(phrase) })
            let went = await s.navigate(to: ReadiumReaderSession.readerLocator(try Locator(jsonString: block.locatorJSON)))
            XCTAssertTrue(went)
            try await Task.sleep(for: .milliseconds(500))
            let sel = try await select(s, "selectNormalized(\(ReaderProbe.jsString(phrase)))")
            XCTAssertEqual(CaptureBuilder.collapse(sel.exactText), phrase)
            let a = try CaptureBuilder.anchor(for: sel, assetID: "fixture:pg-walden-epub2.epub", assetDigest: s.opened.sha256, extraction: extraction)
            samples.append(Sample(name: "pg-epub2-walden", note: "EPUB 2 (OPF 2.0) from Project Gutenberg; the selected text keeps the source's whitespace.", anchors: [a], quotedText: sel.exactText))
            TestHost.tearDown()
        }

        // Generated fixture: non-BMP letters (UTF-16 vs scalar offsets) and a quotation continuing into the next resource.
        do {
            let screen = try await TestHost.open("g01-unicode.epub")
            let s = screen.session
            let extraction = await EPUBExtraction.extract(s.opened)
            let fraktur = "\u{1D509}\u{1D52F}\u{1D51E}\u{1D528}\u{1D531}\u{1D532}\u{1D52F}"
            let quote = "\(fraktur) letters beside the river"
            let moved = await ReaderProbe.goToText(s, href: "OEBPS/c1.xhtml", exact: quote)
            XCTAssertTrue(moved)
            let nonBMP = try await select(s, "selectText(\(ReaderProbe.jsString(quote)), null)")
            let nonBMPAnchor = try CaptureBuilder.anchor(for: nonBMP, assetID: "fixture:g01-unicode.epub", assetDigest: s.opened.sha256, extraction: extraction)
            XCTAssertEqual(nonBMPAnchor.textOffsets?.unit, "unicode_scalar")
            samples.append(Sample(name: "generated-non-bmp", note: "Seven non-BMP letters: text_offsets are Unicode scalars; the DOM index of the same point is 7 higher (UTF-16).", anchors: [nonBMPAnchor], quotedText: nonBMP.exactText))

            let endOfC1 = "The first chapter closes on this sentence, which a reader might keep together with the opening of the next."
            let startOfC2 = "The second chapter opens here, continuing the thought across the resource boundary."
            let m1 = await ReaderProbe.goToText(s, href: "OEBPS/c1.xhtml", exact: endOfC1)
            XCTAssertTrue(m1)
            let a = try await select(s, "selectText(\(ReaderProbe.jsString(endOfC1)), null)")
            let m2 = await ReaderProbe.goToText(s, href: "OEBPS/c2.xhtml", exact: startOfC2)
            XCTAssertTrue(m2)
            try await Task.sleep(for: .milliseconds(500))
            let b = try await select(s, "selectText(\(ReaderProbe.jsString(startOfC2)), null)")
            let q = try CaptureBuilder.quotation(from: [a, b], assetID: "fixture:g01-unicode.epub", assetDigest: s.opened.sha256, extraction: extraction)
            XCTAssertEqual(q.anchors.count, 2)
            samples.append(Sample(name: "generated-quotation-across-resources", note: "One quotation, two resources: two ordered anchors (segment 0 and 1); quoted_text joins the exact texts with a blank line.", anchors: q.anchors, quotedText: q.quotedText))
            TestHost.tearDown()
        }

        // Every captured anchor carries exact text, context, and the verbatim Readium locator; it round-trips.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var rows: [[String: Any]] = []
        // The resource each sample's text really is in (the jump target; for the EPUB 2 sample, the extraction's).
        let expectedHrefs: [String: [String]] = [
            "se-epub3-known-passage": [ScenarioRunner.anchorHref], "se-epub3-across-noteref": [ScenarioRunner.anchorHref],
            "se-epub3-greek": ["epub/text/book-7.xhtml"], "pg-epub2-walden": [pgHref],
            "generated-non-bmp": ["OEBPS/c1.xhtml"], "generated-quotation-across-resources": ["OEBPS/c1.xhtml", "OEBPS/c2.xhtml"],
        ]
        for sample in samples {
            XCTAssertEqual(sample.anchors.map(\.resourceHref), expectedHrefs[sample.name], "\(sample.name): anchor names the wrong resource")
            for anchor in sample.anchors {
                XCTAssertNotNil(anchor.textOffsets, "\(sample.name): selection not mapped onto the extraction")
                XCTAssertFalse(anchor.exactText.isEmpty, sample.name)
                XCTAssertEqual(anchor.reader.locator["text"]?["highlight"]?.stringValue, anchor.exactText, "\(sample.name): locator text differs from exact_text")
                XCTAssertEqual(anchor.reader.locator["href"]?.stringValue, anchor.resourceHref, sample.name)
                let data = try encoder.encode(anchor)
                XCTAssertEqual(try JSONDecoder().decode(PortableEPUBAnchor.self, from: data), anchor, "\(sample.name): anchor does not round-trip")
            }
            let anchorsJSON = try JSONSerialization.jsonObject(with: encoder.encode(sample.anchors))
            rows.append([
                "name": sample.name, "note": sample.note, "quoted_text": sample.quotedText ?? NSNull(),
                "readium_locator_fields": sample.anchors.map { Self.fields((try? String(decoding: encoder.encode($0.reader.locator), as: UTF8.self)) ?? "") },
                "anchors": anchorsJSON,
            ])
        }
        let positionsJSON = try JSONSerialization.jsonObject(with: encoder.encode(Self.positions.map { p in
            ["name": G01EPUBCore.JSONValue.string(p["name"] as? String ?? ""), "fields": .array((p["fields"] as? [String] ?? []).map(G01EPUBCore.JSONValue.string)),
             "reader_locator": p["reader_locator"] as? G01EPUBCore.JSONValue ?? .null]
        }))
        ReaderProbe.writeEvidence("anchor-samples.json", json: [
            "environment": CompatibilityMatrixTests.environment,
            "generated_by": "Spikes/G01-EPUB/Tests/Unit/AnchorSamplesTests.swift (Scripts/ci.d/31-g01-epub.sh)",
            "readium": "readium/swift-toolkit \(ReadiumReaderSession.adapterVersion)",
            "extraction_version": EPUBExtraction.extractionVersion,
            "envelope_proposal": Self.envelopeProposal,
            "capture_samples": rows,
            "other_locators": positionsJSON,
            "readium_selection_href_vs_confirmed": Self.rawSelectionHrefs,
        ])
    }

    static var positions: [[String: Any]] = []

    /// The proposed portable EPUB anchor (Swift type `PortableEPUBAnchor`), field by field, for the anchor schema.
    static let envelopeProposal: [String: Any] = [
        "summary": "Portable fields are Sylvia's own and readable on any platform; reader.locator is the reader's locator stored verbatim and interpreted only by the adapter named in reader.adapter. Reanchoring order (plan 7.5): reader.locator, then exact_text with prefix/suffix inside resource_href, then text_offsets when extraction_version matches.",
        "fields": [
            ["name": "version", "type": "integer", "portable": true, "meaning": "Anchor envelope version (1)."],
            ["name": "kind", "type": "string", "portable": true, "meaning": "\"epub\"."],
            ["name": "asset_id", "type": "uuid string", "portable": true, "meaning": "Sylvia asset (the EPUB file) the anchor belongs to."],
            ["name": "asset_digest", "type": "lowercase hex SHA-256", "portable": true, "meaning": "Digest of the EPUB bytes; a different digest means a different asset version (same-asset rules no longer apply)."],
            ["name": "resource_href", "type": "string (URL path relative to the publication root, as in the OPF manifest, normalized)", "portable": true, "meaning": "The spine resource the text is in."],
            ["name": "resource_media_type", "type": "string", "portable": true, "meaning": "Media type of the resource (application/xhtml+xml)."],
            ["name": "exact_text", "type": "string", "portable": true, "meaning": "The selected text exactly as the reader returned it (window.getSelection().toString()): never trimmed, collapsed or truncated. Immutable (plan 11.1)."],
            ["name": "prefix", "type": "string", "portable": true, "meaning": "Text before the selection as the reader returned it (Readium: up to about 200 UTF-16 code units, raw whitespace)."],
            ["name": "suffix", "type": "string", "portable": true, "meaning": "Text after the selection, same rules as prefix."],
            ["name": "text_offsets", "type": "object or null", "portable": true, "meaning": "Where exact_text sits in Sylvia's own extraction of resource_href: {unit: \"unicode_scalar\", basis: \"sylvia-extraction\", extraction_version, block_index, start, end}. Null when the selection spans blocks or is ambiguous. Units are Unicode scalars (Contracts/README.md); the adapter converts to UTF-16 for the DOM."],
            ["name": "progression", "type": "number 0..1 or null", "portable": true, "meaning": "Readium's progression within the resource of the page shown at capture time (Readium 3.11.0 copies the navigator's current location into the selection locator; it is not the selection's own position). Null when the adapter had to correct the resource. Display and coarse fallback only; changes with layout."],
            ["name": "total_progression", "type": "number 0..1 or null", "portable": true, "meaning": "Progression within the publication. Display only."],
            ["name": "position", "type": "integer or null", "portable": true, "meaning": "Readium position number (synthetic, about 1,024 characters per position). Never shown as a page number (plan 7.5)."],
            ["name": "segment", "type": "object or null", "portable": true, "meaning": "{index, count} when one quotation crosses resources and is stored as several ordered anchors; null for a single anchor."],
            ["name": "reader.adapter", "type": "string", "portable": true, "meaning": "\"readium-swift\"."],
            ["name": "reader.adapter_version", "type": "string", "portable": true, "meaning": "Reader release that produced the locator (3.11.0)."],
            ["name": "reader.locator", "type": "object", "portable": false, "meaning": "Readium Locator JSON verbatim (href, type, title, locations, text). Adapter-opaque: other clients must not interpret it; they use the portable fields."],
        ],
        "observed_readium_locator_contents": "Selection locators carry href, type, title, locations.{progression, totalProgression, position} and text.{before, highlight, after}; no CSS selector, partial CFI, DOM range or fragment. Content-iterator (extraction and search-hit) locators also carry locations.cssSelector. Reading-position locators carry no text.highlight. Readium 3.11.0 builds a selection locator from the navigator's current location (href, progression, position of the page shown) plus the selected text, so right after a jump its href can name the previous resource; the adapter's captureSelection() checks the href against the document holding the selection (readium_selection_href_vs_confirmed).",
    ]
}
