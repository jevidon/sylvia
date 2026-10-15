@testable import EPUBHarness
import Foundation
import XCTest

/// Deliverable 4: Literata as the default reading face through Readium's font-family mechanism, with the user's
/// size and line spacing; system serif and sans as the other two faces (plan 4.4.3, 9.1). Simulator.
@MainActor final class TypographyTests: XCTestCase {
    override func tearDown() async throws { TestHost.tearDown() }

    static let fontProbe = """
    (function () {
      const faces = Array.from(document.fonts).map(f => ({ family: f.family.replace(/"/g, ''), style: f.style, weight: f.weight, status: f.status }));
      const c = document.createElement('canvas').getContext('2d');
      function width(font) { c.font = font; return c.measureText('Hamburgefonstiv quick brown fox 0123').width; }
      const p = document.querySelector('p');
      const cs = getComputedStyle(p);
      return JSON.stringify({ faces, family: cs.fontFamily, size: cs.fontSize, lineHeight: cs.lineHeight,
        wLiterata: width('19px Literata'), wSerifGeneric: width('19px serif'), wUiSerif: width('19px ui-serif'),
        wSystem: width('19px -apple-system'), wFallback: width('19px "Sylvia No Such Face"'),
        literataStyleInjected: Array.from(document.querySelectorAll('style')).some(s => s.textContent.includes('Literata-Variable.ttf')),
        pWidthInUse: (function () { const r = document.createRange(); r.selectNodeContents(p); return r.getBoundingClientRect().width; })() });
    })()
    """

    func probe(_ s: ReadiumReaderSession) async throws -> [String: Any] {
        try await ReaderProbe.json(s, Self.fontProbe)
    }

    func px(_ v: Any?) -> Double { Double(((v as? String) ?? "").replacingOccurrences(of: "px", with: "")) ?? -1 }

    func testLiterataIsTheDefaultFaceAndActuallyLoads() async throws {
        let screen = try await TestHost.open("se-meditations.epub")
        let s = screen.session
        // Book I: body text (the title page is an image).
        let moved = await ReaderProbe.goToText(s, href: ScenarioRunner.anchorHref, exact: "From my grandfather Verus")
        XCTAssertTrue(moved)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(s.settings.typeface, .literata)
        // Wait for the preloaded face to finish loading.
        var r: [String: Any] = [:]
        let loaded = await ReaderProbe.wait(timeout: .seconds(8)) {
            r = (try? await self.probe(s)) ?? [:]
            let faces = r["faces"] as? [[String: Any]] ?? []
            return faces.contains { ($0["family"] as? String) == "Literata" && ($0["status"] as? String) == "loaded" }
        }
        XCTAssertTrue(loaded, "Literata face never reached status 'loaded': \(r)")
        XCTAssertTrue((r["family"] as? String ?? "").hasPrefix("Literata"), "computed font-family: \(r["family"] ?? "nil")")
        XCTAssertEqual(r["literataStyleInjected"] as? Bool, true)
        // Rendering proof: Literata's advance widths differ from the generic serif and from a missing face.
        let wL = r["wLiterata"] as? Double ?? 0, wS = r["wSerifGeneric"] as? Double ?? 0, wF = r["wFallback"] as? Double ?? 0
        XCTAssertNotEqual(wL, wS, accuracy: 0.5, "Literata measures like the generic serif: not loaded")
        XCTAssertNotEqual(wL, wF, accuracy: 0.5)
        let image = await ReaderProbe.snapshot(s)
        if let image { ReaderProbe.writePNG("typeface-literata.png", image) }
        XCTAssertNotNil(image)
        ReaderProbe.writeEvidence("typography-literata.json", json: r)
    }

    func testSizeAndLineSpacingTakeEffect() async throws {
        let screen = try await TestHost.open("se-meditations.epub")
        let s = screen.session
        // Book I: body text (the title page is an image).
        let moved = await ReaderProbe.goToText(s, href: ScenarioRunner.anchorHref, exact: "From my grandfather Verus")
        XCTAssertTrue(moved)
        try await Task.sleep(for: .milliseconds(300))
        var rows: [[String: Any]] = []
        var settings = s.settings
        var sizes: [Double: Double] = [:]
        for points in [14.0, 19.0, 28.0] {
            settings.fontSizePoints = points
            settings.lineSpacingStep = 1
            s.apply(settings: settings)
            await s.settle()
            let r = try await probe(s)
            sizes[points] = px(r["size"])
            rows.append(["points": points, "computed_font_size": r["size"] ?? "", "computed_line_height": r["lineHeight"] ?? "", "font_family": r["family"] ?? ""])
        }
        // Size follows the setting proportionally (Readium's fontSize factor scales the root size).
        XCTAssertGreaterThan(sizes[19]!, sizes[14]!)
        XCTAssertGreaterThan(sizes[28]!, sizes[19]!)
        XCTAssertEqual(sizes[28]! / sizes[14]!, 2.0, accuracy: 0.05)
        var spacing: [Int: Double] = [:]
        for step in 0 ..< ReaderSettings.lineHeights.count {
            settings.fontSizePoints = 19
            settings.lineSpacingStep = step
            s.apply(settings: settings)
            await s.settle()
            let r = try await probe(s)
            let ratio = px(r["lineHeight"]) / px(r["size"])
            spacing[step] = ratio
            rows.append(["points": 19, "line_spacing_step": step, "requested": ReaderSettings.lineHeights[step],
                         "computed_font_size": r["size"] ?? "", "computed_line_height": r["lineHeight"] ?? "", "ratio": ratio])
            XCTAssertEqual(ratio, ReaderSettings.lineHeights[step], accuracy: 0.03, "step \(step)")
        }
        ReaderProbe.writeEvidence("typography-size-spacing.json", json: ["environment": CompatibilityMatrixTests.environment, "rows": rows])
    }

    func testSystemSerifAndSystemSans() async throws {
        let screen = try await TestHost.open("se-meditations.epub")
        let s = screen.session
        // Book I: body text (the title page is an image).
        let moved = await ReaderProbe.goToText(s, href: ScenarioRunner.anchorHref, exact: "From my grandfather Verus")
        XCTAssertTrue(moved)
        try await Task.sleep(for: .milliseconds(300))
        var results: [String: Any] = [:]
        var widths: [ReaderTypeface: Double] = [:]
        for face in [ReaderTypeface.literata, .systemSerif, .systemSans] {
            var settings = s.settings
            settings.typeface = face
            s.apply(settings: settings)
            await s.settle()
            let r = try await probe(s)
            results[face.rawValue] = ["family": r["family"] ?? "", "p_line_width": r["pWidthInUse"] ?? 0]
            widths[face] = r["pWidthInUse"] as? Double
            if let image = await ReaderProbe.snapshot(s) { ReaderProbe.writePNG("typeface-\(face.rawValue).png", image) }
            let family = r["family"] as? String ?? ""
            switch face {
            case .literata: XCTAssertTrue(family.hasPrefix("Literata"), family)
            case .systemSerif: XCTAssertTrue(family.hasPrefix("ui-serif"), family)
            case .systemSans: XCTAssertTrue(family.hasPrefix("-apple-system"), family)
            case .publisher: break
            }
        }
        // The three faces measure differently (canvas advance widths), so each really changed the rendering.
        let r = try await probe(s)
        let wL = r["wLiterata"] as? Double ?? 0, wU = r["wUiSerif"] as? Double ?? 0, wA = r["wSystem"] as? Double ?? 0
        XCTAssertNotEqual(wL, wU, accuracy: 0.5)
        XCTAssertNotEqual(wU, wA, accuracy: 0.5)
        XCTAssertNotEqual(wL, wA, accuracy: 0.5)
        results["canvas_widths_19px"] = ["literata": wL, "ui_serif": wU, "apple_system": wA, "generic_serif": r["wSerifGeneric"] ?? 0]
        ReaderProbe.writeEvidence("typography-faces.json", json: results)
    }
}
