import Foundation
import Testing
@testable import SylviaDesignTokens

/// Section 4.4.2 values, re-typed from the plan so a transcription error in the token source fails.
private let planLiterals: [(ColorToken, light: String, dark: String)] = [
    (.ground, "#F4F2ED", "#161512"),
    (.surface, "#FBFAF7", "#1E1C19"),
    (.ink, "#1C1B18", "#ECE7DD"),
    (.muted, "#6B6760", "#A8A298"),
    (.pine, "#2F5D50", "#7FB5A3"),
    (.pineOn, "#F4F2ED", "#161512"),
    (.ochre, "#8A5410", "#D9A24A"),
    (.markerQuoteText, "#8A5410", "#D9A24A"),
    (.markerNoteText, "#2F5D50", "#7FB5A3"),
    (.markerAudioText, "#3F5A78", "#8FB0D4"),
    (.markerGeneratedText, "#6B4E8E", "#B49BD6"),
    (.markerWordText, "#8A5410", "#D9A24A"),
    (.markerAttentionText, "#A63D2F", "#E0837A"),
    (.markerPendingText, "#6B6760", "#A8A298"),
]

/// Light tints from the plan (dark tints are derived).
private let planLightTints: [(ColorToken, String)] = [
    (.pineTint, "#DCE8E2"), (.ochreTint, "#F1E4C8"), (.markerQuoteTint, "#F1E4C8"),
    (.markerWordTint, "#F1E4C8"), (.markerAudioTint, "#DCE4EE"), (.markerGeneratedTint, "#E7DFF0"),
    (.markerAttentionTint, "#F3DCD7"), (.markerPendingTint, "#ECE9E2"),
]

/// Exact derived and Increase Contrast values recorded in ADR-0013.
private let recordedTints: [(ColorToken, dark: String, lightIC: String, darkIC: String)] = [
    (.pineTint, "#252B26", "#CBDAD3", "#2E3933"),
    (.ochreTint, "#31291A", "#E7D6B6", "#42351F"),
    (.markerAudioTint, "#272B2D", "#CCD6E2", "#31383E"),
    (.markerGeneratedTint, "#2C282D", "#DBD1E6", "#3A343E"),
    (.markerAttentionTint, "#322421", "#EBCCC6", "#432E2A"),
    (.markerPendingTint, "#2A2925", "#DFDCD5", "#373531"),
]

/// Independent integer implementation of "x% of `top` over `bottom`", rounded half up.
private func composite(_ top: String, over bottom: String, opacity: Double) -> String {
    let t = SRGBColor(hex: top), b = SRGBColor(hex: bottom)
    func mix(_ x: UInt8, _ y: UInt8) -> Int { Int((opacity * Double(x) + (1 - opacity) * Double(y) + 0.5).rounded(.down)) }
    return String(format: "#%02X%02X%02X", mix(t.red, b.red), mix(t.green, b.green), mix(t.blue, b.blue))
}

@Suite("Color tokens (plan 4.4.2)")
struct ColorTokenTests {
    @Test("Plan literals are carried exactly, in light and dark", arguments: planLiterals.map { $0.0 })
    func planLiteral(token: ColorToken) {
        let row = planLiterals.first { $0.0 == token }!
        #expect(token.value(in: .light).hex == row.light)
        #expect(token.value(in: .dark).hex == row.dark)
    }

    @Test("Light tints are the plan's values")
    func lightTints() {
        for (token, hex) in planLightTints {
            #expect(token.value(in: .light).hex == hex, "\(token)")
        }
    }

    @Test("Dark tints are the marker's dark text at exactly 14% over Night")
    func derivedDarkTints() {
        for (token, dark, _, _) in recordedTints {
            let source = token.tintSource!.value(in: .dark).hexRGB
            #expect(composite(source, over: "#161512", opacity: 0.14) == dark, "\(token) independent derivation")
            #expect(token.value(in: .dark).hex == dark, "\(token) catalog value")
        }
        // Aliases of the quote tint follow the ochre tint.
        #expect(ColorToken.markerQuoteTint.value(in: .dark) == ColorToken.ochreTint.value(in: .dark))
        #expect(ColorToken.markerWordTint.value(in: .dark) == ColorToken.ochreTint.value(in: .dark))
    }

    @Test("Increase Contrast moves each tint 10% toward its marker text (one step)")
    func increasedContrastTints() {
        for (token, dark, lightIC, darkIC) in recordedTints {
            let lightBase = token.value(in: .light).hexRGB
            let lightText = token.tintSource!.value(in: .light).hexRGB
            let darkText = token.tintSource!.value(in: .dark).hexRGB
            #expect(composite(lightText, over: lightBase, opacity: 0.10) == lightIC, "\(token) light IC")
            #expect(composite(darkText, over: dark, opacity: 0.10) == darkIC, "\(token) dark IC")
            #expect(token.value(in: .lightIncreasedContrast).hex == lightIC)
            #expect(token.value(in: .darkIncreasedContrast).hex == darkIC)
            // In Paper the step darkens the tint.
            #expect(token.value(in: .lightIncreasedContrast).relativeLuminance < token.value(in: .light).relativeLuminance)
            // In Night it moves the tint away from the ground.
            let night = Palette.night
            #expect(SRGBColor.contrastRatio(token.value(in: .darkIncreasedContrast), night)
                > SRGBColor.contrastRatio(token.value(in: .dark), night))
        }
    }

    @Test("Hairline is ink at 12% / 14%, and 24% under Increase Contrast")
    func hairline() {
        let h = ColorToken.hairline
        #expect(h.value(in: .light) == Palette.inkLight.withAlpha(0.12))
        #expect(h.value(in: .dark) == Palette.inkDark.withAlpha(0.14))
        #expect(h.value(in: .lightIncreasedContrast) == Palette.inkLight.withAlpha(0.24))
        #expect(h.value(in: .darkIncreasedContrast) == Palette.inkDark.withAlpha(0.24))
    }

    @Test("Aliases always equal their root token, in every appearance")
    func aliases() {
        for token in ColorToken.allCases {
            guard let root = token.aliasOf else { continue }
            for appearance in Appearance.allCases {
                #expect(token.value(in: appearance) == root.value(in: appearance), "\(token) \(appearance)")
            }
        }
        #expect(ColorToken.markerWordText.aliasOf == .ochre, "Word uses the quote color family")
        #expect(ColorToken.markerPendingText.aliasOf == .muted)
    }

    @Test("Increase Contrast changes only tints, hairline and recorded overrides")
    func increasedContrastScope() {
        let overridden = Set(ContrastOverrides.all.map(\.token))
        for token in ColorToken.allCases where !token.isTint && token != .hairline
            && !overridden.contains(token.aliasRoot) {
            #expect(token.value(in: .lightIncreasedContrast) == token.value(in: .light), "\(token)")
            #expect(token.value(in: .darkIncreasedContrast) == token.value(in: .dark), "\(token)")
        }
    }

    @Test("Covers: five fields and a Paper title in every appearance")
    func covers() {
        let fields = ["#2F5D50", "#5A6B4A", "#7A4B3A", "#3F5A78", "#4A4A58"]
        for (token, hex) in zip(ColorToken.coverFields, fields) {
            for appearance in Appearance.allCases { #expect(token.value(in: appearance).hex == hex) }
        }
        for appearance in Appearance.allCases {
            #expect(ColorToken.coverTitle.value(in: appearance).hex == "#F4F2ED")
        }
    }

    @Test("Shadow is Paper ink at 10% in every appearance")
    func shadow() {
        for appearance in Appearance.allCases {
            #expect(ColorToken.shadow.value(in: appearance) == SRGBColor(hex: "#1C1B18").withAlpha(0.10))
        }
    }

    @Test("Hex parsing accepts only #RRGGBB")
    func hexParsing() {
        #expect(SRGBColor.parse("#f4f2ed") == SRGBColor(red: 0xF4, green: 0xF2, blue: 0xED))
        for bad in ["F4F2ED", "#F4F2E", "#F4F2EDA", "#G4F2ED", "", "#"] {
            #expect(SRGBColor.parse(bad) == nil, "\(bad)")
        }
    }

    @Test("Plan-listed dark tints differ from the 14% rule (recorded for design review)")
    func planListedDarkTintsDiffer() {
        // The plan's printed dark tints are approximations; the catalog uses the exact rule.
        var differing = 0
        for (token, listed) in Palette.planListedDarkTints where token.value(in: .dark) != listed {
            differing += 1
        }
        #expect(differing == 6, "all six printed dark tints differ from the exact 14% derivation")
    }
}

@Suite("Contrast (plan 4.4.2, 22.2)")
struct ContrastTests {
    @Test("WCAG reference ratios")
    func referenceRatios() {
        let white = SRGBColor(hex: "#FFFFFF"), black = SRGBColor(hex: "#000000")
        #expect(abs(SRGBColor.contrastRatio(white, black) - 21) < 1e-9)
        #expect(SRGBColor.contrastRatio(white, white) == 1)
        // #777777 on white is the textbook near-miss: 4.48:1.
        #expect(abs(SRGBColor.contrastRatio(SRGBColor(hex: "#777777"), white) - 4.478) < 0.001)
    }

    @Test("Every permitted pair passes in light, dark and both Increase Contrast appearances")
    func allPairsPass() {
        let results = ContrastReport.evaluate { token, appearance in token.value(in: appearance) }
        #expect(results.count == ContrastPairs.all.count * 4)
        for r in results where !r.passes {
            Issue.record("\(r.pair.id) in \(r.appearance): \(r.ratio)")
        }
        #expect(results.allSatisfy { $0.passes })
    }

    @Test("Every component pair passes from the token values; only disabled states are exempt")
    func componentPairsPass() {
        let results = ContrastReport.evaluateComponents { token, appearance in token.value(in: appearance) }
        #expect(results.count == ComponentContrastPairs.all.count * 4)
        for r in results where r.isFailure {
            Issue.record("\(r.pair.id) in \(r.appearance): \(r.ratio)")
        }
        #expect(results.filter(\.isFailure).isEmpty)
        let onlyDisabledExempt = ComponentContrastPairs.all.allSatisfy { $0.requirement == .required || $0.state == "disabled" }
        #expect(onlyDisabledExempt)
        // Every button role is measured pressed and disabled.
        for role in ["primary", "secondary", "quiet", "destructive"] {
            #expect(ComponentContrastPairs.all.contains { $0.component == "button_\(role)" && $0.state == "pressed" })
            #expect(ComponentContrastPairs.all.contains { $0.component == "button_\(role)" && $0.state == "disabled" })
        }
        // The selection menu's contents come from the opposite appearance.
        #expect(Appearance.light.opposite == .dark && Appearance.lightIncreasedContrast.opposite == .darkIncreasedContrast)
    }

    @Test("The pressed opacity is the smallest multiple of 0.05 that keeps every pressed label at 4.5:1")
    func pressedOpacityIsMinimal() {
        let pressed = ComponentContrastPairs.all.filter { $0.state == "pressed" }
        func allPass(_ opacity: Double) -> Bool {
            pressed.allSatisfy { pair in
                let faded = ComponentContrastPair(component: pair.component, state: pair.state, foreground: pair.foreground,
                                                  background: pair.background, opacity: opacity, use: pair.use)
                return Appearance.allCases.allSatisfy { appearance in
                    let (fg, bg) = faded.colors(in: appearance) { token, a in token.value(in: a) }
                    return SRGBColor.contrastRatio(fg, bg) >= ColorRules.minimumTextContrast
                }
            }
        }
        #expect(ComponentMetrics.pressedOpacity == 0.9)
        #expect(allPass(ComponentMetrics.pressedOpacity))
        #expect(!allPass(ComponentMetrics.pressedOpacity - 0.05), "a lighter press would fail, so 0.9 is minimal")
        #expect(!allPass(0.7), "the earlier 0.7 failed (review round 1)")
    }

    @Test("Thresholds are never weakened: 4.5:1, or 3:1 only for 24 pt and larger")
    func thresholds() {
        #expect(ColorRules.minimumTextContrast == 4.5)
        #expect(ColorRules.minimumLargeTextContrast == 3.0)
        #expect(ColorRules.largeTextMinimumPointSize == 24)
        #expect(ColorRules.minimumNonTextContrast == 3.0)
        #expect(ContrastPairs.all.allSatisfy { $0.textSize == .any }, "no pair currently relies on the large-text threshold")
    }

    @Test("Each recorded override was needed and is exactly the minimal darkening")
    func overridesAreMinimal() {
        #expect(ContrastOverrides.all.count == 3)
        for o in ContrastOverrides.all {
            let unadjusted = o.token.unadjustedValue(in: o.appearance)
            #expect(unadjusted == o.before)
            let failing = ContrastPairs.all.filter { pair in
                pair.foreground.aliasRoot == o.token
                    && SRGBColor.contrastRatio(unadjusted, pair.background.value(in: o.appearance)) < pair.threshold
            }
            #expect(!failing.isEmpty, "\(o.token) override must be justified by a failing pair")
            let search = ContrastAdjustment.minimalDarkening(of: o.token, in: o.appearance)
            #expect(search?.step == o.darkeningStep)
            #expect(search?.color == o.after)
        }
    }

    @Test("Muted text is not permitted on tints (it fails there in Paper)")
    func mutedNotOnTints() {
        #expect(!ContrastPairs.all.contains { $0.foreground == .muted && $0.background.isTint })
        let failing = ContrastPairs.tints.filter { tint, _, _ in
            SRGBColor.contrastRatio(ColorToken.muted.value(in: .light), tint.value(in: .light)) < 4.5
        }
        #expect(!failing.isEmpty)
    }

    @Test("Every tint and every ground has a permitted ink pair; every marker text has a ground pair")
    func pairCoverage() {
        for (tint, ownText, _) in ContrastPairs.tints {
            #expect(ContrastPairs.all.contains { $0.foreground == .ink && $0.background == tint })
            #expect(ContrastPairs.all.contains { $0.foreground == ownText && $0.background == tint })
        }
        for marker in Marker.allCases {
            for ground in [ColorToken.ground, .surface] {
                #expect(ContrastPairs.all.contains { $0.foreground == marker.textColor && $0.background == ground })
            }
        }
    }
}
