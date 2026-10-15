import Foundation
import Testing
@testable import SylviaDesign

@Suite("Asset catalog colors and contrast (G0.6)")
@MainActor
struct CatalogColorTests {
    @Test("Every token resolves from the asset catalog to its defined value in all four appearances")
    func catalogMatchesTokens() {
        var mismatches = 0
        for token in ColorToken.allCases {
            for appearance in Appearance.allCases {
                let shipped = token.catalogValue(in: appearance)
                let defined = token.value(in: appearance)
                let same = shipped.red == defined.red && shipped.green == defined.green
                    && shipped.blue == defined.blue && abs(shipped.alpha - defined.alpha) < 0.0015
                if !same {
                    mismatches += 1
                    Issue.record("\(token.rawValue) \(appearance.rawValue): catalog \(shipped), defined \(defined)")
                }
            }
        }
        #expect(mismatches == 0)
    }

    @Test("SwiftUI views resolve every token to its defined value (color scheme and contrast)")
    func swiftUIMatchesTokens() {
        var mismatches = 0
        for token in ColorToken.allCases {
            for appearance in Appearance.allCases {
                let shipped = token.swiftUIValue(in: appearance)
                let defined = token.value(in: appearance)
                if shipped.hexRGB != defined.hexRGB || abs(shipped.alpha - defined.alpha) >= 0.0015 {
                    mismatches += 1
                    Issue.record("\(token.rawValue) \(appearance.rawValue): SwiftUI \(shipped), defined \(defined)")
                }
            }
        }
        #expect(mismatches == 0)
    }

    @Test("Increase Contrast variants are actually selected by the platform (hairline 12% -> 24%)")
    func increasedContrastIsLive() {
        #expect(abs(ColorToken.hairline.catalogValue(in: .light).alpha - 0.12) < 0.0015)
        #expect(abs(ColorToken.hairline.catalogValue(in: .dark).alpha - 0.14) < 0.0015)
        #expect(abs(ColorToken.hairline.catalogValue(in: .lightIncreasedContrast).alpha - 0.24) < 0.0015)
        #expect(abs(ColorToken.hairline.catalogValue(in: .darkIncreasedContrast).alpha - 0.24) < 0.0015)
        #expect(ColorToken.ochreTint.catalogValue(in: .lightIncreasedContrast).hex == "#E7D6B6")
        #expect(ColorToken.ground.catalogValue(in: .dark).hex == "#161512")
    }

    @Test("Every text pair passes contrast with colors read back from the asset catalog")
    func catalogContrast() {
        let results = ContrastReport.evaluate { token, appearance in token.catalogValue(in: appearance) }
        let failures = results.filter { !$0.passes }
        for f in failures {
            Issue.record("\(f.pair.id) \(f.appearance.rawValue): \(String(format: "%.2f", f.ratio))")
        }
        #expect(results.count == ContrastPairs.all.count * Appearance.allCases.count)
        #expect(failures.isEmpty)
        let minimum = results.min { $0.ratio < $1.ratio }!
        var text = "# Contrast measured from the compiled asset catalog\n\n"
        text += "Environment: \(Evidence.environmentLabel)\n\n"
        #if canImport(UIKit)
        text += "Colors resolved with `ColorToken.catalogValue(in:)`: `UIColor(named:in:)` from the compiled Assets.car, "
        text += "resolved for each appearance's trait collection (user interface style and accessibility contrast), "
        #else
        text += "Colors resolved with `ColorToken.catalogValue(in:)`: SwiftUI `Color(_:bundle:)` from the compiled Assets.car, "
        text += "resolved for each appearance's color scheme and color scheme contrast, "
        #endif
        text += "then WCAG 2.x contrast. \(results.count) measurements, \(failures.count) failing; "
        text += "lowest \(String(format: "%.2f", minimum.ratio)) (\(minimum.pair.id), \(minimum.appearance.rawValue)).\n\n"
        text += ContrastReport.markdownTable(results)
        Evidence.write("contrast-catalog-\(Evidence.platformSuffix).md", text: text)
    }

    @Test("Component text and glyphs on their fills pass, with colors read back from the asset catalog (review round 1)")
    func catalogComponentContrast() {
        let results = ContrastReport.evaluateComponents { token, appearance in token.catalogValue(in: appearance) }
        let failures = results.filter(\.isFailure)
        for f in failures {
            Issue.record("\(f.pair.id) \(f.appearance.rawValue): \(String(format: "%.2f", f.ratio)) < \(f.pair.threshold)")
        }
        #expect(results.count == ComponentContrastPairs.all.count * Appearance.allCases.count)
        #expect(failures.isEmpty)
        // "Saving…" is on the busy primary button at full contrast; only disabled states are exempt.
        let busyPasses = results.filter { $0.pair.state == "busy" }.allSatisfy(\.passes)
        #expect(busyPasses)
        let onlyDisabledExempt = ComponentContrastPairs.all.allSatisfy { $0.requirement == .required || $0.state == "disabled" }
        #expect(onlyDisabledExempt)
        let exempt = results.filter { !$0.passes && !$0.isFailure }
        var text = "# Component contrast measured from the compiled asset catalog\n\n"
        text += "Environment: \(Evidence.environmentLabel)\n\n"
        text += "Text and glyphs as the components draw them where that differs from a token pair "
        text += "(`ComponentContrastPairs`: the selection menu's opposite-appearance contents on its ink fill, the "
        text += "selected filter chip, the round play controls, the busy \"Saving…\" button, and every button role "
        text += "pressed and disabled, composited over the ground at the state's opacity). Colors from "
        text += "`ColorToken.catalogValue(in:)`. \(results.count) measurements, \(failures.count) failing; "
        text += "\(exempt.count) disabled-state measurements below the minimum, reported and exempt (WCAG 1.4.3: "
        text += "inactive controls). Text needs 4.5:1, glyphs 3:1.\n\n"
        text += ContrastReport.componentMarkdownTable(results)
        Evidence.write("contrast-components-catalog-\(Evidence.platformSuffix).md", text: text)
    }
}
