import PDFAnchorKit
import PDFKit
import XCTest

/// Plan 9.4 "survives an extraction-cache rebuild" and ADR-0005 (the extraction version includes the OS build):
/// the ten anchors captured on iOS 26.5 (23F77) and committed in `Tests/Resources` are restored through the reader's
/// restore path (`HighlightRestorer`) on whichever iOS runtime runs this test. The drop-in runs it on iOS 26.5 (the
/// same extractor) and again on the iOS 27.0 simulator runtime, whose PDFKit is that release's own build. On each
/// runtime the page text of every page of every bundled fixture is also recorded, and the drop-in compares the two
/// lists, so a statement about the runtimes' extraction covers every page and not only the pages the anchors use.
@MainActor
final class CrossOSRestoreTests: XCTestCase {
    /// "iOS 26.5 (23F77)" -> "iOS-26.5-23F77", for evidence file names.
    static var runtimeFileLabel: String {
        ExtractionVersion.platformDescription().replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
    }

    struct Sample: Decodable {
        var name: String
        var fixture: String
        var fixtureSHA256: String
        var anchor: PDFAnchor

        enum CodingKeys: String, CodingKey {
            case name, fixture, anchor
            case fixtureSHA256 = "fixture_sha256"
        }
    }

    struct Captured: Decodable {
        var capturedOn: String
        var samples: [Sample]

        enum CodingKeys: String, CodingKey {
            case samples
            case capturedOn = "captured_on"
        }
    }

    func testAnchorsCapturedOnIOS26_5RestoreOnThisRuntime() throws {
        let url = try XCTUnwrap(Bundle(for: CrossOSRestoreTests.self).url(
            forResource: "anchors-captured-ios-26.5-23F77.json", withExtension: nil, subdirectory: "Resources"))
        let captured = try AnchorJSON.decoder().decode(Captured.self, from: Data(contentsOf: url))
        XCTAssertEqual(captured.samples.count, 10)
        let platform = ExtractionVersion.platformDescription()
        var lines = ["Anchors captured on \(captured.capturedOn), restored with HighlightRestorer on \(Evidence.environmentLabel)",
                     "extraction platform now: \(platform)"]
        var sameExtraction = 0
        for sample in captured.samples {
            let fixture = (sample.fixture as NSString).lastPathComponent
            let source = try Fixture.open(fixture)
            XCTAssertEqual(source.sha256, sample.fixtureSHA256, "\(sample.name): the fixture is the one the anchor was captured from")
            let extraction = PageTextExtractor.extract(source)
            let digestsMatch = sample.anchor.segments.allSatisfy { extraction.page($0.pageIndex)?.textSHA256 == $0.pageTextSHA256 }
            if digestsMatch { sameExtraction += 1 }
            let outcome = HighlightRestorer.restore([HighlightRecord(anchor: sample.anchor)], in: source, extraction: extraction)
            let result = outcome.exact == 1 ? "exact"
                : outcome.relocated == 1 ? "relocated"
                : outcome.needsReview == 1 ? "location needs review"
                : outcome.relocationNotRebuilt == 1 ? "relocated, not rebuilt" : "not found"
            var line = "\(sample.name) (\(fixture), stored platform \(sample.anchor.extraction.platform)): "
                + "page text digests \(digestsMatch ? "match" : "differ"); \(result)"
            if outcome.relocated == 1, let rebuilt = outcome.drawable.first {
                let moved = zip(rebuilt.segments, sample.anchor.segments).map { new, old in
                    "page \(old.pageIndex) range \(old.textRange.start)..<\(old.textRange.end) -> \(new.textRange.start)..<\(new.textRange.end), "
                        + "line rects \(new.lineRects == old.lineRects ? "unchanged" : "changed")"
                }
                line += " (\(moved.joined(separator: "; ")))"
            }
            lines.append(line)
            // Survives: drawn with the identical quotation, exactly or after relocation by text plus context.
            XCTAssertEqual(outcome.drawable.count, 1, "\(sample.name): \(result)")
            if let drawn = outcome.drawable.first {
                XCTAssertTrue(UnicodeOffsets.scalarsEqual(drawn.exactText, sample.anchor.exactText), sample.name)
            }
            // With the same page text the stored locator must restore exactly.
            if digestsMatch {
                XCTAssertEqual(outcome.exact, 1, "\(sample.name): same page text, so the stored range must restore exactly")
            }
        }
        lines.append("\(sameExtraction) of \(captured.samples.count) anchors found every page text digest unchanged")
        if platform == captured.samples.first?.anchor.extraction.platform {
            XCTAssertEqual(sameExtraction, captured.samples.count, "same OS build, same extractor: every page text digest must match")
        }
        Evidence.write("cross-os-restore-\(Self.runtimeFileLabel).txt", lines.joined(separator: "\n") + "\n")
    }

    /// Every page of every bundled fixture: the scalar count and SHA-256 of PDFKit's page text (`PDFPage.string`),
    /// or why the file does not open. Written as `page-text-digests-<runtime>.txt`; `Scripts/ci.d/32-g01-pdf.sh`
    /// compares the iOS 26.5 and iOS 27.0 lists line by line. The no-copy file's text is read too: this records what
    /// the extractor returns, not what Sylvia offers for that file.
    func testRecordPageTextOfEveryFixturePage() throws {
        // The same lookup `Fixture.url` uses (the bundle's `resourceURL` is its `Resources` folder, not where `Fixtures` is).
        let urls = try XCTUnwrap(Bundle(for: CrossOSRestoreTests.self).urls(forResourcesWithExtension: "pdf", subdirectory: "Fixtures"))
        let names = urls.map(\.lastPathComponent).sorted()
        XCTAssertEqual(names.count, 12, "every committed fixture is in the test bundle: \(names)")
        var lines = ["Page text (PDFPage.string) of every page of the \(names.count) bundled fixtures: scalar count and SHA-256 of its UTF-8 bytes, "
                     + "\(Evidence.environmentLabel)"]
        var notOpened: [String: String] = [:]
        var pages = 0
        for name in names {
            let source: PDFSourceDocument
            do {
                source = try Fixture.open(name)
            } catch {
                notOpened[name] = "\(error)"
                lines.append("\(name): does not open (\(error))")
                continue
            }
            for index in 0..<source.document.pageCount {
                pages += 1
                guard let text = source.page(at: index)?.string else {
                    lines.append("\(name) page \(index): no text (nil)")
                    continue
                }
                lines.append("\(name) page \(index): \(UnicodeOffsets.scalarCount(text)) scalars, sha256 \(PageTextExtractor.sha256Hex(text))")
            }
        }
        // The two files that must not open (OpenErrorTests); every other fixture contributes its pages.
        XCTAssertEqual(notOpened, ["encrypted-user-password.pdf": "passwordProtected", "truncated.pdf": "truncated"])
        XCTAssertGreaterThan(pages, names.count - notOpened.count)
        lines.append("\(pages) pages of \(names.count - notOpened.count) fixtures; \(notOpened.count) fixtures do not open")
        Evidence.write("page-text-digests-\(Self.runtimeFileLabel).txt", lines.joined(separator: "\n") + "\n")
    }
}
