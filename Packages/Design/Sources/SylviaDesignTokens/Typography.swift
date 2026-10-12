import Foundation

/// The three faces of Section 4.4.3.
public enum Face: String, CaseIterable, Sendable, Codable {
    /// Everything that belongs to a book. Bundled variable font, axes `wght` and `opsz`.
    case literata
    /// Everything that belongs to the interface (SF Pro on Apple platforms).
    case system
    /// Values compared character by character (SF Mono), tabular figures.
    case monospace
}

/// Apple text styles the roles map to. Raw values follow the A.5 sketch (`largeTitle`, `body`).
public enum TextStyle: String, CaseIterable, Sendable, Codable {
    case largeTitle
    case title1
    case title2
    case body
    case subheadline
    case footnote
    case caption2

    /// The style's size at the default Dynamic Type setting on iOS (Large).
    public var iOSDefaultPointSize: Double {
        switch self {
        case .largeTitle: 34
        case .title1: 28
        case .title2: 22
        case .body: 17
        case .subheadline: 15
        case .footnote: 13
        case .caption2: 11
        }
    }
}

/// The eight type roles of Section 4.4.3.
public enum TypeRole: String, CaseIterable, Sendable, Codable {
    case display
    case title
    case heading
    case reading
    case body
    case callout
    case caption
    case micro

    public var spec: TypeRoleSpec {
        switch self {
        case .display:
            TypeRoleSpec(face: .literata, weight: 600, size: 34, lineHeight: 40, tracking: -0.015,
                         textStyle: .largeTitle, uppercase: false, usage: "Top of each primary area")
        case .title:
            TypeRoleSpec(face: .literata, weight: 600, size: 28, lineHeight: 34, tracking: -0.01,
                         textStyle: .title1, uppercase: false, usage: "Work titles, sheet titles")
        case .heading:
            TypeRoleSpec(face: .literata, weight: 500, size: 22, lineHeight: 28, tracking: 0,
                         textStyle: .title2, uppercase: false, usage: "Section and dialog heads")
        case .reading:
            TypeRoleSpec(face: .literata, weight: 400, size: ReadingSize.defaultPoints, lineHeight: 30, tracking: 0,
                         textStyle: .body, uppercase: false, usage: "Reader body, quotations")
        case .body:
            TypeRoleSpec(face: .system, weight: 400, size: 17, lineHeight: 23, tracking: 0,
                         textStyle: .body, uppercase: false, usage: "All interface text, notes")
        case .callout:
            TypeRoleSpec(face: .system, weight: 500, size: 15, lineHeight: 20, tracking: 0,
                         textStyle: .subheadline, uppercase: false, usage: "Explanations beside an action")
        case .caption:
            TypeRoleSpec(face: .system, weight: 400, size: 13, lineHeight: 18, tracking: 0,
                         textStyle: .footnote, uppercase: false, usage: "Metadata, timestamps")
        case .micro:
            TypeRoleSpec(face: .system, weight: 600, size: 11, lineHeight: 14, tracking: 0.08,
                         textStyle: .caption2, uppercase: true,
                         usage: "Marker labels and section eyebrows only; never body copy")
        }
    }
}

/// A role at the default Dynamic Type size.
public struct TypeRoleSpec: Sendable, Hashable {
    public let face: Face
    /// CSS-style weight (400 regular, 500 medium, 600 semibold).
    public let weight: Int
    /// Point size at the default Dynamic Type setting.
    public let size: Double
    /// Line height in points at that size; scales in proportion to the size.
    public let lineHeight: Double
    /// Tracking as a fraction of the point size (-0.015 is -1.5%).
    public let tracking: Double
    public let textStyle: TextStyle
    public let uppercase: Bool
    public let usage: String

    /// Line height divided by size.
    public var lineHeightRatio: Double { lineHeight / size }
}

/// The reader's text size setting (Section 4.4.3, 9.1). The user picks a size within 14...28 at the
/// default Dynamic Type setting; the chosen size then scales with Dynamic Type like every other
/// role (the role table's sizes are "at the default Dynamic Type setting").
public struct ReadingSize: Sendable, Hashable {
    public static let range: ClosedRange<Double> = 14...28
    public static let defaultPoints: Double = 19

    public let points: Double

    /// Clamps to ``range``.
    public init(points: Double) {
        self.points = min(max(points, Self.range.lowerBound), Self.range.upperBound)
    }

    public static let `default` = ReadingSize(points: defaultPoints)
}

/// Bold Text (Section 4.4.8: "Bold Text is honored by all roles").
public enum BoldText {
    /// Under Bold Text every role's weight rises by 200, capped at 900 (400 -> 600, 500 -> 700,
    /// 600 -> 800). Literata's `wght` axis covers 200...900; system weights map to the nearest
    /// system weight.
    public static let weightIncrease = 200
    public static let maximumWeight = 900

    public static func weight(_ base: Int, boldText: Bool) -> Int {
        boldText ? min(base + weightIncrease, maximumWeight) : base
    }
}

/// Literata as bundled (Fixtures/LICENSES.md).
public enum LiterataFont {
    public static let family = "Literata"
    /// PostScript name of the upright default instance.
    public static let postScriptName = "Literata-Regular"
    public static let italicPostScriptName = "Literata-Italic"
    public static let files = ["Literata-Variable.ttf", "Literata-Italic-Variable.ttf"]
    public static let version = "3.103"
    public static let license = "OFL-1.1"
    public static let weightAxis: ClosedRange<Double> = 200...900
    public static let opticalSizeAxis: ClosedRange<Double> = 7...72
    /// OpenType axis tags as Core Text identifiers.
    public static let weightAxisTag: UInt32 = 0x7767_6874 // 'wght'
    public static let opticalSizeAxisTag: UInt32 = 0x6F70_737A // 'opsz'
    /// Weight of the typeset Quote mark (the boards set it bold so it reads at marker size).
    public static let markWeight = 700

    /// The optical size used for text at `pointSize`: the point size, clamped to the axis.
    public static func opticalSize(forPointSize pointSize: Double) -> Double {
        min(max(pointSize, opticalSizeAxis.lowerBound), opticalSizeAxis.upperBound)
    }
}
