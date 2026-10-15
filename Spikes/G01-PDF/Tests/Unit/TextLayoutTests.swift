import PDFAnchorKit
import PDFKit
import UIKit
import XCTest

/// The synthetic part of open question 5 (layouts of real-world PDFs), with text-layout.pdf: lines drawn with rotated
/// text matrices on an unrotated page, two columns whose content stream draws the lines in a scrambled order, and one
/// column drawn from its bottom line up. What PDFKit extracts, whether anchors restore exactly, and where the
/// highlight overlay falls. Real PDFs (embedded and CID fonts, right-to-left and vertical scripts) stay open question 5.
@MainActor
final class TextLayoutTests: XCTestCase {
    struct Line {
        var name: String
        var text: String
        /// The side of the glyphs where an underline belongs (below the baseline), from the text matrix that drew it.
        var baselineSide: String
    }

    /// Page 0's lines (text-layout.pdf generator: ROTATED_TEXT_LINES and the horizontal reference line).
    static let rotatedLines = [
        Line(name: "horizontal", text: "Horizontal reference line at the top.", baselineSide: "bottom"),
        Line(name: "upward one", text: "Upward line one reads from the bottom of the page.", baselineSide: "right"),
        Line(name: "upward two", text: "Upward line two sits to the right of line one.", baselineSide: "right"),
        Line(name: "downward one", text: "Downward line one reads from the top of the page.", baselineSide: "left"),
        Line(name: "downward two", text: "Downward line two sits to the left of line one.", baselineSide: "left"),
        Line(name: "upside-down one", text: "Upside-down line one runs right to left.", baselineSide: "top"),
        Line(name: "upside-down two", text: "Upside-down line two sits above line one.", baselineSide: "top"),
        Line(name: "diagonal one", text: "Diagonal line one climbs at thirty degrees.", baselineSide: "bottom-right"),
        Line(name: "diagonal two", text: "Diagonal line two climbs below it.", baselineSide: "bottom-right"),
    ]

    /// The side of a line's box on the baseline side of its glyphs, from the reading direction: the outward normal
    /// to the right of the direction of reading, (dy, -dx). Within 10 degrees of an axis it is one side of the box.
    static func side(ofNormalTo d: CGVector) -> String {
        let n = CGVector(dx: d.dy, dy: -d.dx)
        let angle = atan2(n.dy, n.dx) * 180 / .pi
        switch angle {
        case -100 ... -80: return "bottom"
        case 80 ... 100: return "top"
        case -10 ... 10: return "right"
        case let a where a >= 170 || a <= -170: return "left"
        default: return (n.dy < 0 ? "bottom" : "top") + "-" + (n.dx > 0 ? "right" : "left")
        }
    }

    /// Reading direction of a range of page text, from its first and last characters' selection boxes.
    static func readingDirection(on page: PDFPage, utf16 range: NSRange) -> CGVector? {
        guard range.length >= 2,
              let a = page.selection(for: NSRange(location: range.location, length: 1))?.bounds(for: page),
              let b = page.selection(for: NSRange(location: NSMaxRange(range) - 1, length: 1))?.bounds(for: page)
        else { return nil }
        let dx = b.midX - a.midX, dy = b.midY - a.midY
        let length = (dx * dx + dy * dy).squareRoot()
        return length > 0 ? CGVector(dx: dx / length, dy: dy / length) : nil
    }

    func testRotatedTextMatricesRestoreButTheUnderlineAssumesUprightText() throws {
        let source = try Fixture.open("text-layout.pdf")
        let extraction = PageTextExtractor.extract(source)
        let page = try XCTUnwrap(source.page(at: 0))
        let text = try XCTUnwrap(extraction.page(0)?.text)
        // Each rotated line is extracted as its own line of page text, ordered by PDFKit's layout analysis: the two
        // downward lines come out in the reverse of their reading order.
        XCTAssertEqual(text, ["Rotated text matrices", "Horizontal reference line at the top.",
                              "Diagonal line one climbs at thirty degrees.", "Diagonal line two climbs below it.",
                              "Upward line one reads from the bottom of the page.", "Upward line two sits to the right of line one.",
                              "Upside-down line one runs right to left.", "Upside-down line two sits above line one.",
                              "Downward line two sits to the left of line one.", "Downward line one reads from the top of the page."]
                       .joined(separator: "\n"))
        let box = page.bounds(for: PDFSourceDocument.anchorBox)
        var report = ["text-layout.pdf page 0 (lines drawn with rotated text matrices on an unrotated page), \(Evidence.environmentLabel)",
                      "page text: \(esc(text))"]
        var anchors: [PDFAnchor] = []
        var boxes: [String: CGRect] = [:]
        for line in Self.rotatedLines {
            let ranges = PDFAnchorResolver.occurrences(of: line.text, prefix: "", suffix: "", in: text)
            XCTAssertEqual(ranges.count, 1, line.name)
            let range = try XCTUnwrap(ranges.first)
            let anchor = try PDFAnchorBuilder.anchor(forScalarRange: range, onPage: 0, in: source, extraction: extraction)
            anchors.append(anchor)
            XCTAssertEqual(anchor.exactText, line.text, line.name)
            XCTAssertEqual(anchor.segments.count, 1, line.name)
            let rects = try XCTUnwrap(anchor.segments.first).lineRects
            XCTAssertEqual(rects.count, 1, "\(line.name): one line rectangle")
            // JSON round trip and a fresh open: the stored range restores exactly with identical text.
            let decoded = try AnchorJSON.decoder().decode(PDFAnchor.self, from: AnchorJSON.encoder().encode(anchor))
            let reopened = try Fixture.open("text-layout.pdf")
            var restored = "not exact"
            if case .exact(let resolved) = PDFAnchorResolver.resolve(decoded, in: reopened, extraction: PageTextExtractor.extract(reopened)),
               UnicodeOffsets.scalarsEqual(resolved.selection.string ?? "", line.text) {
                restored = "exact"
            }
            XCTAssertEqual(restored, "exact", line.name)

            // Geometry: PDFKit's line box (axis-aligned, in user space) and the side the underline is drawn on.
            let userBox = PageGeometry.denormalize(try XCTUnwrap(rects.first), in: box)
            boxes[line.name] = userBox
            let utf16 = try UnicodeOffsets.utf16Range(fromScalar: range, in: text)
            let direction = try XCTUnwrap(Self.readingDirection(on: page, utf16: utf16), line.name)
            let baselineSide = Self.side(ofNormalTo: direction)
            XCTAssertEqual(baselineSide, line.baselineSide, "\(line.name): reading direction \(direction)")
            let underline = HighlightStyle.underlineRect(for: userBox)
            // The overlay always draws the underline along the box's bottom edge (minimum y), as for upright text.
            XCTAssertEqual(underline.minY, userBox.minY, accuracy: 0.0001, line.name)
            XCTAssertEqual(underline.width, userBox.width, accuracy: 0.0001, line.name)
            report.append(String(format: "%@: restored %@; reading direction (%.3f, %.3f); line box x %.1f y %.1f w %.1f h %.1f pt; "
                                 + "baseline side %@; underline drawn along the bottom edge, %.1f x %.1f pt: %@",
                                 line.name, restored, direction.dx, direction.dy, userBox.minX, userBox.minY, userBox.width, userBox.height,
                                 baselineSide, underline.width, underline.height,
                                 baselineSide == "bottom" ? "on the baseline side" : "not on the baseline side"))
        }
        // Upright and upside-down lines: the box is one font size (11 pt) tall; vertical lines: one font size wide.
        for name in ["horizontal", "upside-down one", "upside-down two"] {
            XCTAssertEqual(try XCTUnwrap(boxes[name]).height, 11, accuracy: 0.5, name)
        }
        for name in ["upward one", "upward two", "downward one", "downward two"] {
            XCTAssertEqual(try XCTUnwrap(boxes[name]).width, 11, accuracy: 0.5, name)
        }
        // A diagonal line's box is its slanted line's bounding box: far taller than the text, and it overlaps the next
        // diagonal line's box, so its fill covers part of that line too.
        let d1 = try XCTUnwrap(boxes["diagonal one"]), d2 = try XCTUnwrap(boxes["diagonal two"])
        XCTAssertGreaterThan(d1.height, 5 * 11)
        let overlap = d1.intersection(d2)
        XCTAssertGreaterThan(overlap.width * overlap.height, 0.5 * d2.width * d2.height, "the diagonal boxes overlap")
        report.append(String(format: "diagonal one and two: boxes %.0f x %.0f and %.0f x %.0f pt for 11 pt text; their intersection is %.0f%% of line two's box",
                             d1.width, d1.height, d2.width, d2.height, 100 * overlap.width * overlap.height / (d2.width * d2.height)))

        // The overlay as drawn (offscreen, the same drawing path PDFView uses): every line highlighted.
        HighlightOverlay.apply(anchors, to: source.document)
        let image = try XCTUnwrap(PageRenderer.render(page, scale: 2))
        Evidence.writePNG("overlay-rotated-text.png", image)
        report.append("overlay-rotated-text.png: page 0 rendered with every line highlighted (2 px per pt)")
        Evidence.write("text-layout-rotated.txt", report.joined(separator: "\n") + "\n")
    }

    func testScrambledStreamOrderIsExtractedInReadingOrder() throws {
        let source = try Fixture.open("text-layout.pdf")
        let extraction = PageTextExtractor.extract(source)
        let page = try XCTUnwrap(source.page(at: 1))
        let text = try XCTUnwrap(extraction.page(1)?.text)
        // The stream draws right 2, left 1, right 4, left 3, right 1, left 2, right 3, left 4, then the heading.
        // PDFKit's text is in reading order: heading, the left column top to bottom, then the right column.
        let left = ["Left one: the first line of the left column.", "Left two: the second line of the left column.",
                    "Left three: the third line of the left column.", "Left four: the last line of the left column."]
        let right = ["Right one: the first line of the right column.", "Right two: the second line of the right column.",
                     "Right three: the third line of the right column.", "Right four: the last line of the right column."]
        XCTAssertEqual(text, (["Scrambled column order", "Scrambled order heading drawn last"] + left + right).joined(separator: "\n"))
        var report = ["text-layout.pdf page 1 (two columns drawn in a scrambled stream order), \(Evidence.environmentLabel)",
                      "page text: \(esc(text))"]
        // Drags as a finger makes them: down the left column, and from the left column's last line into the right
        // column's first line. Both follow reading order and restore exactly.
        for (name, from, to) in [("left column, lines one to three", CGPoint(x: 100, y: 702), CGPoint(x: 200, y: 672)),
                                 ("left column's last line into the right column", CGPoint(x: 150, y: 657), CGPoint(x: 400, y: 702))] {
            let selection = try XCTUnwrap(page.selection(from: from, to: to), name)
            let anchor = try PDFAnchorBuilder.capture(selection: selection, in: source, extraction: extraction)
            let decoded = try AnchorJSON.decoder().decode(PDFAnchor.self, from: AnchorJSON.encoder().encode(anchor))
            let reopened = try Fixture.open("text-layout.pdf")
            guard case .exact = PDFAnchorResolver.resolve(decoded, in: reopened, extraction: PageTextExtractor.extract(reopened)) else {
                XCTFail("\(name): not restored exactly")
                continue
            }
            let xs = anchor.segments.flatMap(\.lineRects).map { Int(($0.x * 612).rounded()) }
            report.append("\(name): \"\(esc(anchor.exactText))\"; \(anchor.segments.count) segment, lines starting at x \(xs); restored exact")
            if name.hasPrefix("left column's") {
                XCTAssertEqual(anchor.exactText, "line of the left column.\nRight one: the firs")
                XCTAssertEqual(Set(xs.map { $0 < 300 }), [true, false], "lines in both columns")
            } else {
                XCTAssertEqual(anchor.exactText.components(separatedBy: "\n").count, 3)
                XCTAssertTrue(anchor.exactText.contains("left column.\nLeft two: the second line of the left column.\nLeft three"))
            }
        }
        Evidence.write("text-layout-order.txt", report.joined(separator: "\n") + "\n" + (try bottomUpReport()))
    }

    /// One column drawn from its bottom line up: the text comes out in reading order, but PDFKit joins the first two
    /// lines with no separator ("order.Bottom-up two"), so a search across that line break with a space finds nothing.
    func bottomUpReport() throws -> String {
        let source = try Fixture.open("text-layout.pdf")
        let extraction = PageTextExtractor.extract(source)
        let page = try XCTUnwrap(source.page(at: 2))
        let text = try XCTUnwrap(extraction.page(2)?.text)
        XCTAssertEqual(text, "Bottom-up stream order\nBottom-up one: this is the first line in reading order."
                       + "Bottom-up two: this is the second line in reading order.\n"
                       + "Bottom-up three: this is the third line in reading order.\n"
                       + "Bottom-up four: this is the fourth line in reading order.")
        let spaced = LexicalSearch.find("reading order. Bottom-up two", in: extraction)
        let joined = LexicalSearch.find("reading order.Bottom-up two", in: extraction)
        XCTAssertEqual(spaced.count, 0)
        XCTAssertEqual(joined.count, 1)
        // A drag over lines one to three: still one contiguous range that restores exactly.
        let selection = try XCTUnwrap(page.selection(from: CGPoint(x: 150, y: 703), to: CGPoint(x: 150, y: 673)))
        let anchor = try PDFAnchorBuilder.capture(selection: selection, in: source, extraction: extraction)
        let reopened = try Fixture.open("text-layout.pdf")
        var restored = "not exact"
        if case .exact = PDFAnchorResolver.resolve(anchor, in: reopened, extraction: PageTextExtractor.extract(reopened)) { restored = "exact" }
        XCTAssertEqual(restored, "exact")
        XCTAssertEqual(selection.selectionsByLine().count, 3)
        XCTAssertTrue(anchor.exactText.contains("reading order.Bottom-up two"))
        return """
            text-layout.pdf page 2 (one column drawn from its bottom line up)
            page text: \(esc(text))
            search "reading order. Bottom-up two": \(spaced.count) hits; search "reading order.Bottom-up two": \(joined.count) hit
            drag over lines one to three: \(selection.selectionsByLine().count) lines, quotation "\(esc(anchor.exactText))"; restored \(restored)

            """
    }
}
