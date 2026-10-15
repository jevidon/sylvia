import PDFAnchorKit
import PDFKit
import XCTest

/// Brief item 4 (plan 7.5): PDFKit's UTF-16 ranges are converted to Unicode scalar offsets and back at the adapter
/// boundary, exactly, with non-BMP scalars and combining marks.
@MainActor
final class UnicodeOffsetTests: XCTestCase {
    func testConversionOnKnownStrings() throws {
        let text = "a\u{1D400}b cafe\u{301} \u{1F469}\u{200D}\u{1F52C}!"
        // Scalars: a 𝐀 b ␠ c a f e ◌́ ␠ 👩 ZWJ 🔬 !   (14 scalars; 𝐀, 👩 and 🔬 are 2 UTF-16 units each)
        XCTAssertEqual(UnicodeOffsets.scalarCount(text), 14)
        XCTAssertEqual(text.utf16.count, 17)
        // "b" is UTF-16 [3, 4) but scalar [2, 3).
        XCTAssertEqual(try UnicodeOffsets.scalarRange(fromUTF16: NSRange(location: 3, length: 1), in: text), ScalarRange(start: 2, end: 3))
        // The combining acute alone is one scalar.
        XCTAssertEqual(try UnicodeOffsets.substring(text, scalars: ScalarRange(start: 8, end: 9)), "\u{301}")
        // The ZWJ sequence is three scalars and five UTF-16 units.
        let zwj = try UnicodeOffsets.utf16Range(fromScalar: ScalarRange(start: 10, end: 13), in: text)
        XCTAssertEqual(zwj, NSRange(location: 11, length: 5))
        // A boundary inside a surrogate pair is rejected, never rounded.
        XCTAssertThrowsError(try UnicodeOffsets.scalarRange(fromUTF16: NSRange(location: 2, length: 1), in: text)) {
            XCTAssertEqual($0 as? OffsetConversionError, .splitsSurrogatePair)
        }
        XCTAssertThrowsError(try UnicodeOffsets.scalarRange(fromUTF16: NSRange(location: 0, length: 99), in: text)) {
            XCTAssertEqual($0 as? OffsetConversionError, .outOfBounds)
        }
        XCTAssertThrowsError(try UnicodeOffsets.utf16Range(fromScalar: ScalarRange(start: 3, end: 15), in: text)) {
            XCTAssertEqual($0 as? OffsetConversionError, .outOfBounds)
        }
        // Scalar-exact comparison is not Swift's canonical equivalence.
        XCTAssertTrue("caf\u{E9}" == "cafe\u{301}")
        XCTAssertFalse(UnicodeOffsets.scalarsEqual("caf\u{E9}", "cafe\u{301}"))
    }

    func testEveryScalarRangeRoundTrips() throws {
        let text = "x\u{1D401}\u{301}y\u{20BB7}A\u{30A}\u{1F600}\u{1F469}\u{200D}\u{1F52C}z"
        let n = UnicodeOffsets.scalarCount(text)
        for start in 0...n {
            for end in start...n {
                let r = ScalarRange(start: start, end: end)
                let u = try UnicodeOffsets.utf16Range(fromScalar: r, in: text)
                XCTAssertEqual(try UnicodeOffsets.scalarRange(fromUTF16: u, in: text), r)
                XCTAssertEqual((text as NSString).substring(with: u), try UnicodeOffsets.substring(text, scalars: r))
            }
        }
    }

    /// The same conversions on text PDFKit extracted from the Unicode fixture, through capture and restore.
    func testPDFKitRangesOnNonBMPAndCombiningText() throws {
        let source = try Fixture.open("unicode.pdf")
        let extraction = PageTextExtractor.extract(source)
        let page = try XCTUnwrap(source.page(at: 0))
        let pageText = try XCTUnwrap(extraction.pages[0].text)
        let ns = pageText as NSString
        let targets = [
            "\u{1D400}\u{1D401} end",
            "cafe\u{301}",
            "caf\u{E9}",
            "\u{20BB7}",
            "\u{1F600} then sequence \u{1F469}\u{200D}\u{1F52C} done",
            "A\u{30A}ngstrom",
            "Bold math: \u{1D400}\u{1D401} end of the math line.\nDecomposed: cafe\u{301}",
        ]
        var report = ["Unicode offsets on PDFKit text (unicode.pdf page 0), \(Evidence.environmentLabel)",
                      "target | PDFKit UTF-16 range | scalar range | restored"]
        for target in targets {
            let utf16 = ns.range(of: target, options: .literal)
            XCTAssertNotEqual(utf16.location, NSNotFound, "PDFKit text lacks \(esc(target))")
            let selection = try XCTUnwrap(page.selection(for: utf16))
            XCTAssertTrue(UnicodeOffsets.scalarsEqual(try XCTUnwrap(selection.string), target), "selection text for \(esc(target)): \(esc(selection.string))")
            let anchor = try PDFAnchorBuilder.capture(selection: selection, in: source, extraction: extraction)
            let segment = try XCTUnwrap(anchor.segments.first)
            XCTAssertEqual(anchor.segments.count, 1)
            XCTAssertEqual(segment.textRange.end - segment.textRange.start, UnicodeOffsets.scalarCount(target))
            XCTAssertEqual(try UnicodeOffsets.utf16Range(fromScalar: segment.textRange.scalarRange, in: pageText), utf16)
            XCTAssertEqual(anchor.readerLocator.utf16Ranges.first?.location, utf16.location)
            guard case .exact(let resolved) = PDFAnchorResolver.resolve(anchor, in: source, extraction: extraction) else {
                XCTFail("not restored: \(esc(target))")
                continue
            }
            XCTAssertTrue(UnicodeOffsets.scalarsEqual(try XCTUnwrap(resolved.selection.string), target))
            report.append("\(esc(target)) | {\(utf16.location), \(utf16.length)} | [\(segment.textRange.start), \(segment.textRange.end)) | exact")
        }
        // Precomposed and decomposed "café" are different quotations; re-anchoring by text never confuses them.
        let decomposed = try PDFAnchorBuilder.capture(selection: try XCTUnwrap(page.selection(for: ns.range(of: "cafe\u{301}", options: .literal))),
                                                      in: source, extraction: extraction)
        var drifted = decomposed
        drifted.segments[0].pageTextSHA256 = String(repeating: "0", count: 64)
        guard case .relocated(let relocated) = PDFAnchorResolver.resolve(drifted, in: source, extraction: extraction) else {
            return XCTFail("expected relocation")
        }
        XCTAssertEqual(relocated.segments[0].scalarRange, decomposed.segments[0].textRange.scalarRange)
        XCTAssertEqual(PDFAnchorResolver.occurrences(of: "cafe\u{301}", prefix: "", suffix: "", in: pageText).count, 1)
        XCTAssertEqual(PDFAnchorResolver.occurrences(of: "caf\u{E9}", prefix: "", suffix: "", in: pageText).count, 1)
        Evidence.write("unicode-offsets.txt", report.joined(separator: "\n") + "\n")
    }
}
