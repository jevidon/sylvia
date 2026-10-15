import Foundation
@preconcurrency import ReadiumNavigator
@preconcurrency import ReadiumShared

/// Reader presentation for the spike. Color values are the plan 4.4.2 tokens; in the product they come from
/// `Packages/Design` (plan 4.4.9). Harness code under `Spikes/` is exempt from the literal rule and never ships.
enum SylviaReaderStyle {
    struct Palette: Hashable {
        var ground: String
        var ink: String
        /// `ochre.tint`: highlight fill.
        var highlightFill: String
        /// `ochre`: highlight underline.
        var highlightUnderline: String
    }

    static func palette(_ theme: ReaderTheme) -> Palette {
        switch theme {
        case .paper: Palette(ground: "#F4F2ED", ink: "#1C1B18", highlightFill: "#F1E4C8", highlightUnderline: "#8A5410")
        case .night: Palette(ground: "#161512", ink: "#ECE7DD", highlightFill: "#3A2E17", highlightUnderline: "#D9A24A")
        }
    }

    // MARK: Highlight decoration (plan 4.4.8: Ochre fill plus an Ochre underline, so it survives grayscale)

    static let highlightStyleID: Decoration.Style.Id = "sylvia-highlight"
    static let highlightClass = "sylvia-highlight"
    static let underlinePixels = 2

    struct HighlightConfig: Hashable {
        var fill: String
        var underline: String
    }

    static func highlightStyle(theme: ReaderTheme) -> Decoration.Style {
        let p = palette(theme)
        return Decoration.Style(id: highlightStyleID, config: HighlightConfig(fill: p.highlightFill, underline: p.highlightUnderline))
    }

    /// One box per line of text, drawn behind the text (z-index -1) so glyphs keep the ink color: an opaque
    /// `ochre.tint` fill and a 2 px `ochre` bottom border.
    static var highlightTemplate: HTMLDecorationTemplate {
        HTMLDecorationTemplate(
            layout: .boxes,
            width: .wrap,
            element: { decoration in
                let config = decoration.style.config as? HighlightConfig
                let fill = config?.fill ?? "#F1E4C8"
                let underline = config?.underline ?? "#8A5410"
                let id = decoration.id.filter { $0.isLetter || $0.isNumber || $0 == "-" }
                return "<div class=\"\(highlightClass)\" data-sylvia-highlight-id=\"\(id)\" style=\"background-color: \(fill) !important; border-bottom-color: \(underline) !important;\"/>"
            },
            stylesheet: """
            .\(highlightClass) {
                box-sizing: border-box;
                border: 0 solid;
                border-bottom-width: \(underlinePixels)px;
                border-radius: 0;
                z-index: -1;
            }
            """
        )
    }

    static func decorationTemplates() -> [Decoration.Style.Id: HTMLDecorationTemplate] {
        var templates = HTMLDecorationTemplate.defaultTemplates()
        templates[highlightStyleID] = highlightTemplate
        return templates
    }

    // MARK: Fonts (plan 4.4.3)

    static let literata: FontFamily = "Literata"
    /// WebKit generic families for the platform faces: New York and SF Pro.
    static let systemSerif: FontFamily = "ui-serif"
    static let systemSans: FontFamily = "-apple-system"

    static func fontFamilyDeclarations(bundle: Bundle = .main) -> [AnyHTMLFontFamilyDeclaration] {
        guard let resources = bundle.resourceURL.flatMap({ FileURL(url: $0) }) else { return [] }
        return [
            CSSFontFamilyDeclaration(
                fontFamily: literata,
                alternates: [.serif],
                fontFaces: [
                    CSSFontFace(file: resources.appendingPath("Literata-Variable.ttf", isDirectory: false), preload: true, style: .normal, weight: .variable(200 ... 900)),
                    CSSFontFace(file: resources.appendingPath("Literata-Italic-Variable.ttf", isDirectory: false), preload: true, style: .italic, weight: .variable(200 ... 900)),
                ]
            ).eraseToAnyHTMLFontFamilyDeclaration(),
        ]
    }

    /// Readium's `fontSize` is a factor of the WebView's 16 px root size; one CSS px is one point on iOS.
    static let readiumRootPixels = 16.0

    static func preferences(for settings: ReaderSettings) -> EPUBPreferences {
        let p = palette(settings.theme)
        var prefs = EPUBPreferences()
        switch settings.typeface {
        case .literata: prefs.fontFamily = literata
        case .systemSerif: prefs.fontFamily = systemSerif
        case .systemSans: prefs.fontFamily = systemSans
        case .publisher: prefs.fontFamily = nil
        }
        prefs.fontSize = settings.fontSizePoints.clamped(to: ReaderSettings.fontSizeRange) / readiumRootPixels
        prefs.lineHeight = ReaderSettings.lineHeights[settings.lineSpacingStep.clamped(to: 0 ... ReaderSettings.lineHeights.count - 1)]
        prefs.pageMargins = ReaderSettings.marginFactors[settings.marginStep.clamped(to: 0 ... ReaderSettings.marginFactors.count - 1)]
        prefs.theme = settings.theme == .paper ? .light : .dark
        prefs.backgroundColor = ReadiumNavigator.Color(hex: p.ground)
        prefs.textColor = ReadiumNavigator.Color(hex: p.ink)
        prefs.scroll = settings.scroll
        prefs.publisherStyles = settings.publisherStyles
        return prefs
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
