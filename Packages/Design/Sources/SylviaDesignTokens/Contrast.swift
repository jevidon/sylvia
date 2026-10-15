import Foundation

/// A text color on a fill that the design language permits (plan 4.4.2: "Every text color must
/// meet 4.5:1 against its ground (3:1 at 24pt and above)"; "Tint fills carry no text of their own
/// except the marker's own color; body text on a tint remains ink").
public struct ContrastPair: Sendable, Hashable, Identifiable {
    public enum TextSize: String, Sendable, Hashable {
        /// Any size, so the 4.5:1 threshold applies.
        case any
        /// Used only at 24 pt and larger, so the 3:1 threshold applies.
        case large
    }

    public let foreground: ColorToken
    public let background: ColorToken
    public let textSize: TextSize
    public let use: String

    public var id: String { "\(foreground.rawValue)-on-\(background.rawValue)" }

    public var threshold: Double {
        textSize == .large ? ColorRules.minimumLargeTextContrast : ColorRules.minimumTextContrast
    }
}

public enum ContrastPairs {
    /// Text colors that may sit on `ground` and `surface`.
    public static let textOnGround: [ColorToken] = [
        .ink, .muted, .pine, .ochre,
        .markerQuoteText, .markerNoteText, .markerAudioText, .markerGeneratedText,
        .markerWordText, .markerAttentionText, .markerPendingText,
    ]

    /// Tints with the text colors allowed on them: ink, and the marker's own color.
    public static let tints: [(tint: ColorToken, ownText: ColorToken, use: String)] = [
        (.pineTint, .pine, "Ready pill, Note-related fills"),
        (.ochreTint, .ochre, "Highlight fill"),
        (.markerQuoteTint, .markerQuoteText, "Quote block"),
        (.markerWordTint, .markerWordText, "Word fills"),
        (.markerAudioTint, .markerAudioText, "Audio block"),
        (.markerGeneratedTint, .markerGeneratedText, "Generated fills"),
        (.markerAttentionTint, .markerAttentionText, "Needs attention row and pill"),
        (.markerPendingTint, .markerPendingText, "Queued, receiving, verifying, preparing pills"),
    ]

    /// Every permitted pair, in a stable order.
    public static let all: [ContrastPair] = {
        var pairs: [ContrastPair] = []
        for ground in [ColorToken.ground, .surface] {
            for text in textOnGround {
                pairs.append(ContrastPair(foreground: text, background: ground, textSize: .any,
                                          use: "\(text.use) on \(ground == .ground ? "the screen ground" : "a surface")"))
            }
        }
        pairs.append(ContrastPair(foreground: .pineOn, background: .pine, textSize: .any,
                                  use: "Primary button label on the Pine fill"))
        for (tint, ownText, use) in tints {
            pairs.append(ContrastPair(foreground: .ink, background: tint, textSize: .any, use: "Body text on: \(use)"))
            pairs.append(ContrastPair(foreground: ownText, background: tint, textSize: .any, use: "Marker text on: \(use)"))
        }
        for field in ColorToken.coverFields {
            pairs.append(ContrastPair(foreground: .coverTitle, background: field, textSize: .any,
                                      use: "Title on a typographic cover"))
        }
        return pairs
    }()
}

/// Text or a glyph on a fill as a component draws it, where that differs from a token pair: a
/// color taken from the opposite appearance (the selection menu on its ink fill), a fill other than
/// a ground or tint (a filter chip, a play control), or a control faded by its state (pressed,
/// disabled) over the ground. Review round 1: the token pairs alone did not cover these.
public struct ComponentContrastPair: Sendable, Hashable, Identifiable {
    public enum Content: String, Sendable, Hashable {
        /// Text: 4.5:1 (Section 4.4.2).
        case text
        /// A glyph that carries meaning (an icon, not text): 3:1 (WCAG 2.x 1.4.11 non-text contrast).
        /// The table also says whether it reaches 4.5:1.
        case glyph
    }

    public enum Requirement: String, Sendable, Hashable {
        /// Must pass; a failure fails the check.
        case required
        /// Measured and reported only: a disabled control is inactive, and WCAG 1.4.3 exempts its
        /// text. No vocabulary status may be shown on a disabled control (use the busy state).
        case exemptDisabled = "exempt_disabled"
    }

    public let component: String
    public let state: String
    public let foreground: ColorToken
    /// True when the foreground is resolved in the opposite appearance (light <-> dark, keeping
    /// Increase Contrast), as the selection menu's contents are.
    public let foregroundFromOppositeAppearance: Bool
    public let background: ColorToken
    /// Opacity of the whole control (content and fill) over `ground`: 1 for an opaque control.
    public let opacity: Double
    public let content: Content
    public let requirement: Requirement
    public let use: String

    public init(component: String, state: String = "default", foreground: ColorToken,
                foregroundFromOppositeAppearance: Bool = false, background: ColorToken, opacity: Double = 1,
                content: Content = .text, requirement: Requirement = .required, use: String) {
        self.component = component
        self.state = state
        self.foreground = foreground
        self.foregroundFromOppositeAppearance = foregroundFromOppositeAppearance
        self.background = background
        self.opacity = opacity
        self.content = content
        self.requirement = requirement
        self.use = use
    }

    public var id: String { "\(component).\(state)" }

    public var threshold: Double {
        content == .glyph ? ColorRules.minimumNonTextContrast : ColorRules.minimumTextContrast
    }

    /// The colors as drawn in `appearance`, given a resolver for token values.
    public func colors(in appearance: Appearance,
                       resolve: (ColorToken, Appearance) throws -> SRGBColor) rethrows -> (SRGBColor, SRGBColor) {
        let fgAppearance = foregroundFromOppositeAppearance ? appearance.opposite : appearance
        var fg = try resolve(foreground, fgAppearance)
        var bg = try resolve(background, appearance)
        if opacity < 1 {
            let ground = try resolve(.ground, appearance)
            fg = fg.composited(over: ground, opacity: opacity)
            bg = bg.composited(over: ground, opacity: opacity)
        }
        return (fg, bg)
    }
}

public enum ComponentContrastPairs {
    /// Every component pair, in a stable order. Pairs that equal a token pair (for example a status
    /// pill's text on its tint) are not repeated here; they are measured in ``ContrastPairs/all``.
    public static let all: [ComponentContrastPair] = {
        var pairs: [ComponentContrastPair] = [
            ComponentContrastPair(component: "selection_menu", state: "action", foreground: .ink,
                                  foregroundFromOppositeAppearance: true, background: .ink,
                                  use: "Selection menu action label (the other appearance's ink) on the ink fill"),
            ComponentContrastPair(component: "selection_menu", state: "highlight_glyph", foreground: .markerQuoteText,
                                  foregroundFromOppositeAppearance: true, background: .ink, content: .glyph,
                                  use: "Selection menu Highlight glyph (the other appearance's Ochre) on the ink fill"),
            ComponentContrastPair(component: "filter_chip", state: "selected", foreground: .ground, background: .ink,
                                  use: "Selected filter chip label (ground) on the ink fill"),
            ComponentContrastPair(component: "audio_block", state: "play_control", foreground: .surface,
                                  background: .markerAudioText, content: .glyph,
                                  use: "Play and pause glyph (surface) on the audio-colored round control"),
            ComponentContrastPair(component: "play_pause_button", state: "default", foreground: .pineOn,
                                  background: .pine, content: .glyph,
                                  use: "Player play and pause glyph (pine.on) on the Pine round control"),
            ComponentContrastPair(component: "capture_save_button", state: "busy", foreground: .pineOn,
                                  background: .pine,
                                  use: "\"Saving…\" on the primary button: disabled but drawn at full contrast (busy)"),
        ]
        let roles: [(String, ColorToken, ColorToken)] = [
            ("primary", .pineOn, .pine), ("secondary", .ink, .ground), ("quiet", .pine, .ground),
            ("destructive", .markerAttentionText, .ground),
        ]
        for (role, text, fill) in roles {
            pairs.append(ComponentContrastPair(
                component: "button_\(role)", state: "pressed", foreground: text, background: fill,
                opacity: ComponentMetrics.pressedOpacity,
                use: "\(role.capitalized) button label while pressed (the control at the pressed opacity over the ground)"))
        }
        for (role, text, fill) in roles {
            pairs.append(ComponentContrastPair(
                component: "button_\(role)", state: "disabled", foreground: text, background: fill,
                opacity: ComponentMetrics.disabledOpacity, requirement: .exemptDisabled,
                use: "\(role.capitalized) button label while disabled (inactive; exempt, reported only)"))
        }
        return pairs
    }()
}

/// One measured component pair in one appearance.
public struct ComponentContrastResult: Sendable, Hashable {
    public let pair: ComponentContrastPair
    public let appearance: Appearance
    public let foreground: SRGBColor
    public let background: SRGBColor
    public let ratio: Double

    public var passes: Bool { ratio >= pair.threshold }
    /// A failure that fails the check (exempt pairs are reported only).
    public var isFailure: Bool { !passes && pair.requirement == .required }
}

extension ContrastReport {
    public static func evaluateComponents(
        pairs: [ComponentContrastPair] = ComponentContrastPairs.all,
        appearances: [Appearance] = Appearance.allCases,
        resolve: (ColorToken, Appearance) throws -> SRGBColor
    ) rethrows -> [ComponentContrastResult] {
        var results: [ComponentContrastResult] = []
        for appearance in appearances {
            for pair in pairs {
                let (fg, bg) = try pair.colors(in: appearance, resolve: resolve)
                results.append(ComponentContrastResult(pair: pair, appearance: appearance, foreground: fg,
                                                       background: bg, ratio: SRGBColor.contrastRatio(fg, bg)))
            }
        }
        return results
    }

    /// A Markdown table of component results.
    public static func componentMarkdownTable(_ results: [ComponentContrastResult]) -> String {
        var lines = [
            "| Appearance | Component | State | Content | Text color | Fill color | Ratio | Needs | Result |",
            "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
        ]
        for r in results {
            let result: String
            switch (r.passes, r.pair.requirement) {
            case (true, _): result = r.pair.content == .glyph && r.ratio < ColorRules.minimumTextContrast
                ? "pass (glyph; below 4.5)" : "pass"
            case (false, .required): result = "FAIL"
            case (false, .exemptDisabled): result = "below (disabled, exempt)"
            }
            lines.append("| \(r.appearance.rawValue) | \(r.pair.component) | \(r.pair.state) | \(r.pair.content.rawValue) | "
                + "\(r.foreground.hexRGB) | \(r.background.hexRGB) | \(String(format: "%.2f", r.ratio)) | "
                + "\(String(format: "%.1f", r.pair.threshold)) | \(result) |")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// One measured pair in one appearance.
public struct ContrastResult: Sendable, Hashable {
    public let pair: ContrastPair
    public let appearance: Appearance
    public let foreground: SRGBColor
    public let background: SRGBColor
    public let ratio: Double

    public var passes: Bool { ratio >= pair.threshold }
}

public enum ContrastReport {
    /// Measures every pair in every appearance with colors from `resolve` (token values, the asset
    /// catalog, or the JSON export).
    public static func evaluate(
        pairs: [ContrastPair] = ContrastPairs.all,
        appearances: [Appearance] = Appearance.allCases,
        resolve: (ColorToken, Appearance) throws -> SRGBColor
    ) rethrows -> [ContrastResult] {
        var results: [ContrastResult] = []
        for appearance in appearances {
            for pair in pairs {
                let fg = try resolve(pair.foreground, appearance)
                let bg = try resolve(pair.background, appearance)
                results.append(ContrastResult(pair: pair, appearance: appearance, foreground: fg,
                                              background: bg, ratio: SRGBColor.contrastRatio(fg, bg)))
            }
        }
        return results
    }

    /// A Markdown table of `results`, two decimals, failures marked.
    public static func markdownTable(_ results: [ContrastResult]) -> String {
        var lines = [
            "| Appearance | Text | Fill | Text color | Fill color | Ratio | Needs | Result |",
            "| --- | --- | --- | --- | --- | --- | --- | --- |",
        ]
        for r in results {
            lines.append("| \(r.appearance.rawValue) | \(r.pair.foreground.reference) | \(r.pair.background.reference) | "
                + "\(r.foreground.hexRGB) | \(r.background.hexRGB) | \(String(format: "%.2f", r.ratio)) | "
                + "\(String(format: "%.1f", r.pair.threshold)) | \(r.passes ? "pass" : "FAIL") |")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// The documented procedure for a minimal token adjustment when a pair fails (ADR-0013): darken
/// the text color by multiplying each sRGB channel by `1 - k/100` for k = 1, 2, ... and take the
/// first k at which every pair that uses the token passes in that appearance.
public enum ContrastAdjustment {
    public static func minimalDarkening(
        of token: ColorToken, in appearance: Appearance, pairs: [ContrastPair] = ContrastPairs.all
    ) -> (step: Int, color: SRGBColor)? {
        let group = Set(ColorToken.allCases.filter { $0.aliasRoot == token.aliasRoot })
        let relevant = pairs.filter { group.contains($0.foreground) }
        let original = token.unadjustedValue(in: appearance)
        for step in 1...100 {
            let candidate = original.scaled(by: 1 - Double(step) / 100)
            let allPass = relevant.allSatisfy { pair in
                SRGBColor.contrastRatio(candidate, pair.background.value(in: appearance)) >= pair.threshold
            }
            if allPass { return (step, candidate) }
        }
        return nil
    }
}
