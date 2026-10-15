import Foundation

/// Shape, space, elevation and motion (plan Section 4.4.4).
public enum Spacing {
    public static let grid: Double = 4
    /// The only spacing steps.
    public static let steps: [Double] = [4, 8, 12, 16, 20, 24, 32]
    /// The steps by name, for components (each is one of ``steps``).
    public static let xxs: Double = 4
    public static let xs: Double = 8
    public static let s: Double = 12
    public static let m: Double = 16
    public static let l: Double = 20
    public static let xl: Double = 24
    public static let xxl: Double = 32
    public static let gutterPhone: Double = 20
    public static let gutterPad: Double = 32
}

public enum Radius: String, CaseIterable, Sendable, Codable {
    /// Blocks inset in a card (quote and audio blocks); cover thumbnails 56 pt or smaller.
    case block
    /// Small controls: icon buttons, fields, segmented controls.
    case control
    /// Buttons.
    case button
    /// Cards and covers.
    case card
    /// Sheets (top corners).
    case sheet
    /// Pills and chips: half the height.
    case pill

    /// Points, or nil for ``pill`` (fully rounded).
    public var points: Double? {
        switch self {
        case .block: 8
        case .control: 10
        case .button: 12
        case .card: 14
        case .sheet: 22
        case .pill: nil
        }
    }

    public var use: String {
        switch self {
        case .block: "Blocks inset in a card (quote and audio blocks) and cover thumbnails 56pt or smaller"
        case .control: "Small controls: icon buttons, fields, segmented controls"
        case .button: "Buttons"
        case .card: "Cards and covers"
        case .sheet: "Sheets"
        case .pill: "Pills and chips (fully rounded)"
        }
    }
}

public enum Hairline {
    /// Width of rules and borders in points. Section 4.4.4 says "1px"; the boards draw 1 CSS px,
    /// which is 1 pt. Flagged for design review in ADR-0013 (one device pixel would be 1/3 pt).
    public static let width: Double = 1
}

public enum Elevation {
    /// The one shadow: x 0, y 8, blur 24, ``ColorToken/shadow``. Only sheets and the mini-player.
    public static let shadowX: Double = 0
    public static let shadowY: Double = 8
    public static let shadowBlur: Double = 24
    public static let shadowedComponents = ["sheet", "mini_player"]
}

public enum MotionCurve: String, Sendable, Codable {
    case easeOut = "ease_out"
}

public struct MotionSpec: Sendable, Hashable {
    public let durationMilliseconds: Int
    public let curve: MotionCurve
    /// False where the value is a proposal not stated in the plan (ADR-0013).
    public let statedInPlan: Bool

    public var duration: TimeInterval { Double(durationMilliseconds) / 1000 }
}

public enum Motion {
    /// Sheets: 200 ms ease-out.
    public static let sheet = MotionSpec(durationMilliseconds: 200, curve: .easeOut, statedInPlan: true)
    /// A highlight appearing: 120 ms. The plan gives no curve; ease-out is proposed.
    public static let highlight = MotionSpec(durationMilliseconds: 120, curve: .easeOut, statedInPlan: false)
    /// Progress rules animate; the plan gives no duration. 200 ms ease-out is proposed.
    public static let progressRule = MotionSpec(durationMilliseconds: 200, curve: .easeOut, statedInPlan: false)
    /// Under Reduce Motion all motion is removed except opacity changes.
    public static let reduceMotionRule = "Remove all motion except opacity changes"
    /// Nothing else animates while reading; no bounces, no parallax.
    public static let readingRule = "Only highlight appearance and progress rules animate while reading; no bounces, no parallax"
}
