import Foundation

/// The four appearances every color token defines (plan 4.4.2, 4.4.8).
public enum Appearance: String, CaseIterable, Sendable, Codable {
    case light
    case dark
    case lightIncreasedContrast = "light_increased_contrast"
    case darkIncreasedContrast = "dark_increased_contrast"

    public var isDark: Bool { self == .dark || self == .darkIncreasedContrast }
    public var isIncreasedContrast: Bool { self == .lightIncreasedContrast || self == .darkIncreasedContrast }
    /// The appearance without Increase Contrast.
    public var base: Appearance { isDark ? .dark : .light }
    /// The Increase Contrast counterpart.
    public var increasedContrast: Appearance { isDark ? .darkIncreasedContrast : .lightIncreasedContrast }
    /// The other appearance with the same contrast setting (light <-> dark).
    public var opposite: Appearance {
        switch self {
        case .light: .dark
        case .dark: .light
        case .lightIncreasedContrast: .darkIncreasedContrast
        case .darkIncreasedContrast: .lightIncreasedContrast
        }
    }
}

/// One value per appearance.
public struct AppearanceValues<Value: Sendable & Hashable>: Sendable, Hashable {
    public let light: Value
    public let dark: Value
    public let lightIncreasedContrast: Value
    public let darkIncreasedContrast: Value

    public init(light: Value, dark: Value, lightIncreasedContrast: Value, darkIncreasedContrast: Value) {
        self.light = light
        self.dark = dark
        self.lightIncreasedContrast = lightIncreasedContrast
        self.darkIncreasedContrast = darkIncreasedContrast
    }

    /// The same value in all four appearances.
    public init(all value: Value) {
        self.init(light: value, dark: value, lightIncreasedContrast: value, darkIncreasedContrast: value)
    }

    /// Light/dark values that Increase Contrast leaves unchanged.
    public init(light: Value, dark: Value) {
        self.init(light: light, dark: dark, lightIncreasedContrast: light, darkIncreasedContrast: dark)
    }

    public subscript(_ appearance: Appearance) -> Value {
        switch appearance {
        case .light: light
        case .dark: dark
        case .lightIncreasedContrast: lightIncreasedContrast
        case .darkIncreasedContrast: darkIncreasedContrast
        }
    }
}

/// The rules that turn the plan's tables into exact values. Each is defined once, here, and
/// recorded in ADR-0013.
public enum ColorRules {
    /// Section 4.4.2: dark tints marked "derived" are the marker's dark text color at about 14% over
    /// Night. Applied exactly: source-over in gamma-encoded sRGB at 0.14, rounded to 8 bits.
    public static let derivedDarkTintOpacity = 0.14

    /// Section 4.4.8: "tints darken one step under Increase Contrast". One step is defined as moving
    /// the tint 10% of the way toward its own marker text color (the color of the same appearance
    /// without Increase Contrast), in gamma-encoded sRGB, rounded to 8 bits. In Paper this darkens
    /// the tint; in Night the marker color is lighter than the tint, so the same step strengthens the
    /// tint away from the ground instead of darkening it toward Night (which would erase it). Flagged
    /// for design review in ADR-0013.
    public static let increasedContrastTintStep = 0.10

    /// Section 4.4.2: hairline is ink at 12% (light) and 14% (dark); 24% under Increase Contrast.
    public static let hairlineOpacity = AppearanceValues(
        light: 0.12, dark: 0.14, lightIncreasedContrast: 0.24, darkIncreasedContrast: 0.24
    )

    /// Section 4.4.4: the single shadow is "0 8 24 at 10% ink". Its color is Paper's ink in every
    /// appearance (a light-colored shadow on Night would be a glow, which "no colored shadows"
    /// rules out). Flagged for design review.
    public static let shadowOpacity = 0.10

    /// Minimum contrast for text under 24 pt, and for text at 24 pt and larger (Section 4.4.2).
    public static let minimumTextContrast = 4.5
    public static let minimumLargeTextContrast = 3.0
    public static let largeTextMinimumPointSize = 24.0
    /// Glyphs that carry meaning (icons, not text) inside components: WCAG 2.x 1.4.11.
    public static let minimumNonTextContrast = 3.0
}

/// The literal values from plan Section 4.4.2. Everything else is derived from these by
/// ``ColorRules`` or set as a recorded override.
public enum Palette {
    public static let paper = SRGBColor(hex: "#F4F2ED")
    public static let night = SRGBColor(hex: "#161512")
    public static let surfaceLight = SRGBColor(hex: "#FBFAF7")
    public static let surfaceDark = SRGBColor(hex: "#1E1C19")
    public static let inkLight = SRGBColor(hex: "#1C1B18")
    public static let inkDark = SRGBColor(hex: "#ECE7DD")
    public static let mutedLight = SRGBColor(hex: "#6B6760")
    public static let mutedDark = SRGBColor(hex: "#A8A298")
    public static let pineLight = SRGBColor(hex: "#2F5D50")
    public static let pineDark = SRGBColor(hex: "#7FB5A3")
    public static let pineTintLight = SRGBColor(hex: "#DCE8E2")
    public static let ochreLight = SRGBColor(hex: "#8A5410")
    public static let ochreDark = SRGBColor(hex: "#D9A24A")
    public static let ochreTintLight = SRGBColor(hex: "#F1E4C8")
    public static let audioLight = SRGBColor(hex: "#3F5A78")
    public static let audioDark = SRGBColor(hex: "#8FB0D4")
    public static let audioTintLight = SRGBColor(hex: "#DCE4EE")
    public static let generatedLight = SRGBColor(hex: "#6B4E8E")
    public static let generatedDark = SRGBColor(hex: "#B49BD6")
    public static let generatedTintLight = SRGBColor(hex: "#E7DFF0")
    public static let attentionLight = SRGBColor(hex: "#A63D2F")
    public static let attentionDark = SRGBColor(hex: "#E0837A")
    public static let attentionTintLight = SRGBColor(hex: "#F3DCD7")
    public static let pendingTintLight = SRGBColor(hex: "#ECE9E2")

    /// Typographic cover fields, appearance-invariant (a cover is an object, not chrome).
    public static let coverFields: [SRGBColor] = [
        SRGBColor(hex: "#2F5D50"), SRGBColor(hex: "#5A6B4A"), SRGBColor(hex: "#7A4B3A"),
        SRGBColor(hex: "#3F5A78"), SRGBColor(hex: "#4A4A58"),
    ]

    /// Dark tints as printed in the plan's tables. Not used for rendering: the catalog uses the
    /// exact derivation (``ColorRules/derivedDarkTintOpacity``). Kept so tests and ADR-0013 can
    /// show the difference.
    public static let planListedDarkTints: [ColorToken: SRGBColor] = [
        .pineTint: SRGBColor(hex: "#233A33"),
        .ochreTint: SRGBColor(hex: "#3A2E17"),
        .markerAudioTint: SRGBColor(hex: "#26323E"),
        .markerGeneratedTint: SRGBColor(hex: "#2E2838"),
        .markerAttentionTint: SRGBColor(hex: "#3A2522"),
        .markerPendingTint: SRGBColor(hex: "#2A2824"),
    ]
}

/// A recorded token change made because a contrast pair failed (ADR-0013, "Contrast adjustments").
public struct ContrastOverride: Sendable, Hashable {
    public let token: ColorToken
    public let appearance: Appearance
    public let before: SRGBColor
    public let after: SRGBColor
    /// Darkening step `k`: each channel multiplied by `1 - k/100` (see ``ContrastAdjustment``).
    public let darkeningStep: Int
    public let reason: String
}

/// Increase Contrast overrides. Each was found with ``ContrastAdjustment/minimalDarkening`` and is
/// asserted by tests to be exactly that procedure's result, so the values cannot drift silently.
public enum ContrastOverrides {
    public static let all: [ContrastOverride] = [
        ContrastOverride(
            token: .ochre, appearance: .lightIncreasedContrast,
            before: Palette.ochreLight, after: SRGBColor(hex: "#875210"), darkeningStep: 2,
            reason: "Quote and Word text on the Increase Contrast quote tint measured 4.38:1"
        ),
        ContrastOverride(
            token: .markerAttentionText, appearance: .lightIncreasedContrast,
            before: Palette.attentionLight, after: SRGBColor(hex: "#9E3A2D"), darkeningStep: 5,
            reason: "Attention text on the Increase Contrast attention tint measured 4.20:1"
        ),
        ContrastOverride(
            token: .muted, appearance: .lightIncreasedContrast,
            before: Palette.mutedLight, after: SRGBColor(hex: "#646059"), darkeningStep: 7,
            reason: "Pending text (muted) on the Increase Contrast pending tint measured 4.11:1"
        ),
    ]

    public static func value(for token: ColorToken, in appearance: Appearance) -> SRGBColor? {
        let root = token.aliasRoot
        return all.first { $0.token == root && $0.appearance == appearance }?.after
    }
}

/// Every color token. The raw value is the asset-catalog color name.
public enum ColorToken: String, CaseIterable, Sendable, Codable {
    case ground
    case surface
    case ink
    case muted
    case hairline
    case pine
    case pineOn
    case pineTint
    case ochre
    case ochreTint
    case markerQuoteText
    case markerQuoteTint
    case markerNoteText
    case markerAudioText
    case markerAudioTint
    case markerGeneratedText
    case markerGeneratedTint
    case markerWordText
    case markerWordTint
    case markerAttentionText
    case markerAttentionTint
    case markerPendingText
    case markerPendingTint
    case coverField1
    case coverField2
    case coverField3
    case coverField4
    case coverField5
    case coverTitle
    case shadow

    /// Path of the value in the JSON export (`color.<name>` or `marker.<kind>.text|tint`).
    public var reference: String {
        switch self {
        case .ground: "color.ground"
        case .surface: "color.surface"
        case .ink: "color.ink"
        case .muted: "color.muted"
        case .hairline: "color.hairline"
        case .pine: "color.pine"
        case .pineOn: "color.pine_on"
        case .pineTint: "color.pine_tint"
        case .ochre: "color.ochre"
        case .ochreTint: "color.ochre_tint"
        case .markerQuoteText: "marker.quote.text"
        case .markerQuoteTint: "marker.quote.tint"
        case .markerNoteText: "marker.note.text"
        case .markerAudioText: "marker.audio.text"
        case .markerAudioTint: "marker.audio.tint"
        case .markerGeneratedText: "marker.generated.text"
        case .markerGeneratedTint: "marker.generated.tint"
        case .markerWordText: "marker.word.text"
        case .markerWordTint: "marker.word.tint"
        case .markerAttentionText: "marker.attention.text"
        case .markerAttentionTint: "marker.attention.tint"
        case .markerPendingText: "marker.pending.text"
        case .markerPendingTint: "marker.pending.tint"
        case .coverField1: "color.cover_field_1"
        case .coverField2: "color.cover_field_2"
        case .coverField3: "color.cover_field_3"
        case .coverField4: "color.cover_field_4"
        case .coverField5: "color.cover_field_5"
        case .coverTitle: "color.cover_title"
        case .shadow: "color.shadow"
        }
    }

    /// Tokens that are the same color as another token by definition (Section 4.4.2, 4.4.5).
    /// They exist so views can ask for a marker's color by name; their values always equal the
    /// root token's, including overrides.
    public var aliasOf: ColorToken? {
        switch self {
        case .markerQuoteText, .markerWordText: .ochre
        case .markerQuoteTint, .markerWordTint: .ochreTint
        case .markerNoteText: .pine
        case .markerPendingText: .muted
        default: nil
        }
    }

    public var aliasRoot: ColorToken { aliasOf ?? self }

    /// The marker text color whose tint this is, for tint tokens.
    public var tintSource: ColorToken? {
        switch self {
        case .pineTint: .pine
        case .ochreTint, .markerQuoteTint, .markerWordTint: .ochre
        case .markerAudioTint: .markerAudioText
        case .markerGeneratedTint: .markerGeneratedText
        case .markerAttentionTint: .markerAttentionText
        case .markerPendingTint: .muted
        default: nil
        }
    }

    public var isTint: Bool { tintSource != nil }

    public static let coverFields: [ColorToken] = [.coverField1, .coverField2, .coverField3, .coverField4, .coverField5]

    /// What the token is for (exported, and shown in the design catalog).
    public var use: String {
        switch self {
        case .ground: "Screen background (Paper, Night)"
        case .surface: "Cards, bars, sheets"
        case .ink: "Primary text, icons"
        case .muted: "Captions, metadata, inactive tabs"
        case .hairline: "1pt rules and borders"
        case .pine: "Primary action, links, progress, active tab, Note marker"
        case .pineOn: "Text on a Pine fill"
        case .pineTint: "Ready pill, Note-related fills"
        case .ochre: "Quote marker, highlight underline, rating stars"
        case .ochreTint: "Highlight fill, Quote block fill"
        case .markerQuoteText: "Quote marker glyph and label"
        case .markerQuoteTint: "Quote block fill"
        case .markerNoteText: "Note marker glyph and label"
        case .markerAudioText: "Audio marker glyph, label and waveform"
        case .markerAudioTint: "Audio block fill"
        case .markerGeneratedText: "Generated marker glyph, label and dashed frame"
        case .markerGeneratedTint: "Generated fills"
        case .markerWordText: "Word marker glyph and label (quote color family)"
        case .markerWordTint: "Word fills (quote color family)"
        case .markerAttentionText: "Attention marker, destructive actions"
        case .markerAttentionTint: "Needs attention rows and pills"
        case .markerPendingText: "Pending marker, queued and waiting states"
        case .markerPendingTint: "Queued, receiving, verifying and preparing pills"
        case .coverField1, .coverField2, .coverField3, .coverField4, .coverField5:
            "Typographic cover field (assigned by a stable hash of the work title)"
        case .coverTitle: "Title on a typographic cover field"
        case .shadow: "The single shadow, on sheets and the mini-player only"
        }
    }

    /// How a non-literal value is produced (exported for other platforms; nil for literals).
    public var derivation: String? {
        switch self {
        case .hairline:
            return "ink at 12% (light) and 14% (dark); 24% under Increase Contrast"
        case .pineTint, .ochreTint, .markerQuoteTint, .markerWordTint, .markerAudioTint,
             .markerGeneratedTint, .markerAttentionTint, .markerPendingTint:
            return "dark: marker text at 14% over Night; Increase Contrast: 10% of the way toward the marker text"
        case .coverTitle:
            return "Paper (light ground) in every appearance"
        case .shadow:
            return "Paper ink at 10% in every appearance"
        default:
            return nil
        }
    }

    /// The token's value in all four appearances.
    public var values: AppearanceValues<SRGBColor> {
        AppearanceValues(
            light: value(in: .light), dark: value(in: .dark),
            lightIncreasedContrast: value(in: .lightIncreasedContrast),
            darkIncreasedContrast: value(in: .darkIncreasedContrast)
        )
    }

    /// The value before any recorded contrast override.
    public func unadjustedValue(in appearance: Appearance) -> SRGBColor {
        if let root = aliasOf { return root.unadjustedValue(in: appearance) }
        if let source = tintSource {
            let base = baseTint(dark: appearance.isDark)
            guard appearance.isIncreasedContrast else { return base }
            let text = source.value(in: appearance.base)
            return base.mixed(toward: text, fraction: ColorRules.increasedContrastTintStep)
        }
        let isDark = appearance.isDark
        switch self {
        case .ground: return isDark ? Palette.night : Palette.paper
        case .surface: return isDark ? Palette.surfaceDark : Palette.surfaceLight
        case .ink: return isDark ? Palette.inkDark : Palette.inkLight
        case .muted: return isDark ? Palette.mutedDark : Palette.mutedLight
        case .hairline:
            let ink = isDark ? Palette.inkDark : Palette.inkLight
            return ink.withAlpha(ColorRules.hairlineOpacity[appearance])
        case .pine: return isDark ? Palette.pineDark : Palette.pineLight
        case .pineOn: return isDark ? Palette.night : Palette.paper
        case .ochre: return isDark ? Palette.ochreDark : Palette.ochreLight
        case .markerAudioText: return isDark ? Palette.audioDark : Palette.audioLight
        case .markerGeneratedText: return isDark ? Palette.generatedDark : Palette.generatedLight
        case .markerAttentionText: return isDark ? Palette.attentionDark : Palette.attentionLight
        case .coverField1: return Palette.coverFields[0]
        case .coverField2: return Palette.coverFields[1]
        case .coverField3: return Palette.coverFields[2]
        case .coverField4: return Palette.coverFields[3]
        case .coverField5: return Palette.coverFields[4]
        case .coverTitle: return Palette.paper
        case .shadow: return Palette.inkLight.withAlpha(ColorRules.shadowOpacity)
        default:
            preconditionFailure("unhandled token \(self)")
        }
    }

    /// The rendered value in `appearance`, including recorded overrides.
    public func value(in appearance: Appearance) -> SRGBColor {
        ContrastOverrides.value(for: self, in: appearance) ?? unadjustedValue(in: appearance)
    }

    /// Light tints are the plan's literals; dark tints are derived from the dark marker text.
    private func baseTint(dark: Bool) -> SRGBColor {
        guard let source = tintSource else { preconditionFailure("\(self) is not a tint") }
        if dark {
            return source.value(in: .dark).composited(
                over: Palette.night, opacity: ColorRules.derivedDarkTintOpacity
            )
        }
        switch aliasRoot {
        case .pineTint: return Palette.pineTintLight
        case .ochreTint: return Palette.ochreTintLight
        case .markerAudioTint: return Palette.audioTintLight
        case .markerGeneratedTint: return Palette.generatedTintLight
        case .markerAttentionTint: return Palette.attentionTintLight
        case .markerPendingTint: return Palette.pendingTintLight
        default: preconditionFailure("no light tint for \(self)")
        }
    }
}
