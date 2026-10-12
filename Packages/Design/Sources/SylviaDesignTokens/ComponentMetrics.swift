import Foundation

/// Component dimensions (plan Section 4.4.7, on the 4.4.4 grid). Components take every size from
/// here, from ``Spacing``, ``Radius``, ``Hairline`` and ``Elevation``, or from a type role, so no
/// component declares a literal. Values the plan states are marked; the rest are proposals recorded
/// in ADR-0013 Section 10 and exported under `components` in `marginalia.v1.json`.
public enum ComponentMetrics {
    /// A metric and whether the plan states it.
    public struct Metric: Sendable, Hashable {
        public let name: String
        public let points: Double
        public let statedInPlan: Bool
        public let use: String
    }

    /// Primary, secondary and destructive buttons: 50 pt tall (stated for primary; secondary and
    /// destructive match it so a pair lines up).
    public static let buttonHeight: Double = 50
    /// The smallest touch target (principle 5; quiet buttons, icon buttons): 44 pt.
    public static let minimumTarget: Double = 44
    /// Button content inset from the leading and trailing edge.
    public static let buttonHorizontalPadding: Double = 16
    /// Status pills and availability badges: 22-26 pt tall at the default text size. The Caption
    /// label's 18 pt line plus 4 pt above and below gives 26 pt; the minimum is 22 pt.
    public static let pillMinimumHeight: Double = 22
    public static let pillVerticalPadding: Double = 4
    public static let pillHorizontalPadding: Double = 8
    /// Gap between a glyph and its label (pills, marker rows, menu items).
    public static let glyphGap: Double = 4
    /// Progress rule track: 2-3 pt (stated); 3 pt chosen so it reads at a glance and in grayscale.
    public static let progressRuleThickness: Double = 3
    /// Capture card padding: 12-14 pt (stated); 12 pt keeps it on the 4 pt grid.
    public static let cardPadding: Double = 12
    /// Mini-player floats 12 pt above the tab bar (stated).
    public static let miniPlayerGap: Double = 12
    /// Mini-player cover thumbnail (square).
    public static let miniPlayerCover: Double = 40
    /// Attention dot on the Inbox tab and sidebar row.
    public static let attentionDot: Double = 8
    /// Vertical padding inside the tab bar and navigation bar.
    public static let barVerticalPadding: Double = 4
    /// Round play control inside the audio block.
    public static let playControl: Double = 44
    /// Waveform bars inside the audio block.
    public static let waveformBarWidth: Double = 2
    public static let waveformBarGap: Double = 4
    public static let waveformHeight: Double = 32
    /// Waveform bar heights as a fraction of ``waveformHeight``: from this minimum up to 1.
    public static let waveformMinimumLevel: Double = 0.2
    /// The Generated frame and dashed availability badges: dash and gap lengths of the 1 pt stroke.
    public static let dashLength: Double = 4
    public static let dashGap: Double = 3
    /// Sheet grabber.
    public static let grabberWidth: Double = 36
    public static let grabberHeight: Double = 5
    /// Citation chip inset around its label inside running text.
    public static let chipHorizontalInset: Double = 4
    public static let chipVerticalInset: Double = 1
    /// iPad sidebar width in regular width.
    public static let sidebarWidth: Double = 320
    /// Strikethrough on unresolved citation chips, in points.
    public static let strikethroughWidth: Double = 1
    /// Filter chips (Library, Thoughts, Ask scope): the visible capsule is 36 pt tall inside a
    /// 44 pt touch target (G0.6 part 3 proposal).
    public static let chipHeight: Double = 36
    /// The square icon tile of an action card (onboarding, settings rows).
    public static let actionTile: Double = 44
    /// Square cover in the full player.
    public static let playerCover: Double = 228
    /// The round play/pause control of the full player.
    public static let playerPlayControl: Double = 76
    /// Covers in list rows and the Library "continue" card.
    public static let listCover: Double = 64
    /// Cover on the work detail screen.
    public static let detailCover: Double = 112
    /// Width of the reader's Thoughts pane on iPad in regular width.
    public static let readerPaneWidth: Double = 360

    /// Label weights: buttons, pills, tab labels and menu items are semibold; quiet buttons medium.
    public static let labelWeight = 600
    public static let quietLabelWeight = 500
    /// Opacity of a pressed control's content and of a disabled control (opacity is the only
    /// state change, so it survives Reduce Motion; disabled controls are exempt from WCAG 1.4.3).
    /// Pressed was 0.7 until review round 1: the component contrast check measured the destructive
    /// label at 3.23:1 and the primary label at 3.38:1 while pressed (Paper). 0.9 is the smallest
    /// multiple of 0.05 at which every role's pressed label keeps 4.5:1 in every appearance
    /// (lowest 4.70, destructive in Paper). Flagged for design review (ADR-0013 Section 10).
    public static let pressedOpacity: Double = 0.9
    public static let disabledOpacity: Double = 0.45
    /// Text sizes at which bars stop growing (tab bar, navigation bar, reader chrome), as the
    /// system bars do; beyond it the large content viewer shows each item enlarged.
    /// The largest non-accessibility size (the content size category "XXXL").
    public static let barMaximumTextSize = "xxxLarge"

    public static let all: [Metric] = [
        Metric(name: "button_height", points: buttonHeight, statedInPlan: true, use: "Primary, secondary and destructive buttons"),
        Metric(name: "minimum_target", points: minimumTarget, statedInPlan: true, use: "Smallest touch target; quiet and icon buttons"),
        Metric(name: "button_horizontal_padding", points: buttonHorizontalPadding, statedInPlan: false, use: "Button label inset"),
        Metric(name: "pill_minimum_height", points: pillMinimumHeight, statedInPlan: true, use: "Status pills and availability badges"),
        Metric(name: "pill_vertical_padding", points: pillVerticalPadding, statedInPlan: false, use: "Pill label inset (Caption line 18 + 2 x 4 = 26 pt)"),
        Metric(name: "pill_horizontal_padding", points: pillHorizontalPadding, statedInPlan: false, use: "Pill label inset"),
        Metric(name: "glyph_gap", points: glyphGap, statedInPlan: false, use: "Gap between a glyph and its label"),
        Metric(name: "progress_rule_thickness", points: progressRuleThickness, statedInPlan: true, use: "Progress rule track (plan: 2-3 pt)"),
        Metric(name: "card_padding", points: cardPadding, statedInPlan: true, use: "Capture card padding (plan: 12-14 pt)"),
        Metric(name: "mini_player_gap", points: miniPlayerGap, statedInPlan: true, use: "Mini-player gap above the tab bar"),
        Metric(name: "mini_player_cover", points: miniPlayerCover, statedInPlan: false, use: "Mini-player cover thumbnail"),
        Metric(name: "attention_dot", points: attentionDot, statedInPlan: false, use: "Inbox attention dot"),
        Metric(name: "bar_vertical_padding", points: barVerticalPadding, statedInPlan: false, use: "Tab bar and navigation bar vertical padding"),
        Metric(name: "play_control", points: playControl, statedInPlan: false, use: "Round play control in the audio block"),
        Metric(name: "waveform_bar_width", points: waveformBarWidth, statedInPlan: false, use: "Audio block waveform bars"),
        Metric(name: "waveform_bar_gap", points: waveformBarGap, statedInPlan: false, use: "Audio block waveform bars"),
        Metric(name: "waveform_height", points: waveformHeight, statedInPlan: false, use: "Audio block waveform"),
        Metric(name: "dash_length", points: dashLength, statedInPlan: false, use: "Dashed 1 pt frames (Generated, dashed availability badges)"),
        Metric(name: "dash_gap", points: dashGap, statedInPlan: false, use: "Dashed 1 pt frames"),
        Metric(name: "grabber_width", points: grabberWidth, statedInPlan: false, use: "Sheet grabber"),
        Metric(name: "grabber_height", points: grabberHeight, statedInPlan: false, use: "Sheet grabber"),
        Metric(name: "chip_horizontal_inset", points: chipHorizontalInset, statedInPlan: false, use: "Citation chip inset in running text"),
        Metric(name: "chip_vertical_inset", points: chipVerticalInset, statedInPlan: false, use: "Citation chip inset in running text"),
        Metric(name: "sidebar_width", points: sidebarWidth, statedInPlan: false, use: "iPad sidebar in regular width"),
        Metric(name: "strikethrough_width", points: strikethroughWidth, statedInPlan: false, use: "Strike on unresolved citation chips"),
        Metric(name: "chip_height", points: chipHeight, statedInPlan: false, use: "Filter chip capsule inside a 44 pt target"),
        Metric(name: "action_tile", points: actionTile, statedInPlan: false, use: "Icon tile of an action card"),
        Metric(name: "player_cover", points: playerCover, statedInPlan: false, use: "Square cover in the full player"),
        Metric(name: "player_play_control", points: playerPlayControl, statedInPlan: false, use: "Round play/pause control in the full player"),
        Metric(name: "list_cover", points: listCover, statedInPlan: false, use: "2:3 cover in list rows"),
        Metric(name: "detail_cover", points: detailCover, statedInPlan: false, use: "2:3 cover on the work detail screen"),
        Metric(name: "reader_pane_width", points: readerPaneWidth, statedInPlan: false, use: "Reader Thoughts pane on iPad in regular width"),
    ]
}

/// Platform-neutral description of the button roles (Section 4.4.7), for the export. The SwiftUI
/// style in SylviaDesign reads the same tokens.
public enum ComponentRoles {
    public struct Button: Sendable, Hashable {
        public let name: String
        public let text: ColorToken
        public let fill: ColorToken?
        public let border: ColorToken?
        public let minimumHeight: Double
    }

    public static let buttons: [Button] = [
        Button(name: "primary", text: .pineOn, fill: .pine, border: nil, minimumHeight: ComponentMetrics.buttonHeight),
        Button(name: "secondary", text: .ink, fill: nil, border: .hairline, minimumHeight: ComponentMetrics.buttonHeight),
        Button(name: "quiet", text: .pine, fill: nil, border: nil, minimumHeight: ComponentMetrics.minimumTarget),
        Button(name: "destructive", text: .markerAttentionText, fill: nil, border: .markerAttentionText,
               minimumHeight: ComponentMetrics.buttonHeight),
    ]
}

/// Joining microcopy: the middle-dot separator of marker rows, captions and pills
/// ("QUOTE · Middlemarch · Book II", Section 4.4.5, 4.4.6).
public enum Microcopy {
    public static let separator = " · "

    /// Joins non-empty parts with the separator.
    public static func joined(_ parts: [String]) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: separator)
    }
}

/// Typographic covers (Section 4.4.2, 4.4.7). A cover is an object, not text: its type scales
/// with the cover, not with Dynamic Type, and its accessibility label carries the full title.
public enum CoverLayout {
    /// Width / height in lists.
    public static let listAspectRatio: Double = 2.0 / 3.0
    /// Width / height in the player.
    public static let playerAspectRatio: Double = 1
    /// Covers this wide or narrower use the block radius and show only the title's first letter.
    public static let thumbnailMaximumWidth: Double = 56
    /// Title size as a fraction of the cover width.
    public static let titleScale: Double = 0.15
    /// Author size as a fraction of the cover width.
    public static let authorScale: Double = 0.075
    /// Initial size (thumbnails) as a fraction of the cover width.
    public static let initialScale: Double = 0.5
    /// Inset as a fraction of the cover width.
    public static let insetScale: Double = 0.1
    /// Long single words shrink to this fraction before they would be cut.
    public static let minimumTitleScaleFactor: Double = 0.6
    /// Literata weights.
    public static let titleWeight = 600
    public static let authorWeight = 400
}

/// Rating (Section 4.4.7, 12): five stars in half steps, stored as an integer 1-10. A cleared rating
/// is nil, never zero.
public struct RatingValue: Sendable, Hashable, Comparable, Codable {
    public static let range: ClosedRange<Int> = 1...10
    public static let starCount = 5

    /// Half-stars, 1...10.
    public let storedValue: Int

    /// Nil outside 1...10, so zero cannot be a rating.
    public init?(storedValue: Int) {
        guard Self.range.contains(storedValue) else { return nil }
        self.storedValue = storedValue
    }

    /// Stars in half steps (0.5...5).
    public var stars: Double { Double(storedValue) / 2 }

    public enum StarFill: String, Sendable, Hashable, CaseIterable {
        case full
        case half
        case empty

        /// SF Symbol for the star: filled, leading half filled, outline. The three shapes differ, so
        /// the rating reads without color (Section 4.4.8).
        public var systemSymbol: String {
            switch self {
            case .full: ControlSymbol.starFull.systemName
            case .half: ControlSymbol.starHalf.systemName
            case .empty: ControlSymbol.starEmpty.systemName
            }
        }
    }

    /// Fill of star `index` (0-based) for `value`; all empty when nil.
    public static func fill(star index: Int, value: RatingValue?) -> StarFill {
        guard let value else { return .empty }
        let full = (index + 1) * 2
        if value.storedValue >= full { return .full }
        if value.storedValue == full - 1 { return .half }
        return .empty
    }

    /// The value after tapping star `index` (0-based): a full star, or its half when that star is
    /// already exactly full. Each star is one 44 pt target, so half steps need no small target.
    public static func tapping(star index: Int, current: RatingValue?) -> RatingValue {
        let full = (index + 1) * 2
        if current?.storedValue == full { return RatingValue(storedValue: full - 1)! }
        return RatingValue(storedValue: full)!
    }

    /// One half step up (VoiceOver increment); nil (no rating) goes to half a star.
    public static func incremented(_ value: RatingValue?) -> RatingValue {
        RatingValue(storedValue: min((value?.storedValue ?? 0) + 1, range.upperBound))!
    }

    /// One half step down (VoiceOver decrement); stops at half a star. Clearing is separate.
    public static func decremented(_ value: RatingValue?) -> RatingValue? {
        guard let value else { return nil }
        return RatingValue(storedValue: max(value.storedValue - 1, range.lowerBound))
    }

    public static func < (lhs: RatingValue, rhs: RatingValue) -> Bool { lhs.storedValue < rhs.storedValue }
}

/// An audio capture range with numeric start and end (Section 10.2): integer milliseconds
/// (Contracts/README.md units), at most 120 s long, inside the source, start before end.
public struct AudioRange: Sendable, Hashable {
    /// The default capture: the preceding 30 seconds.
    public static let defaultLengthMilliseconds: Int64 = 30_000
    /// Trimming and extension are permitted up to 120 seconds.
    public static let maximumLengthMilliseconds: Int64 = 120_000
    /// One press of a start or end control moves it by this much.
    public static let stepMilliseconds: Int64 = 1_000
    /// The shortest range the controls allow.
    public static let minimumLengthMilliseconds: Int64 = 1_000

    public let startMilliseconds: Int64
    public let endMilliseconds: Int64
    /// The playable bounds of the source (or the files the range may cross).
    public let sourceDurationMilliseconds: Int64

    public var lengthMilliseconds: Int64 { endMilliseconds - startMilliseconds }

    /// A range clamped into the rules: inside 0...duration, at least the minimum, at most 120 s.
    public init(start: Int64, end: Int64, sourceDuration: Int64) {
        let duration = max(sourceDuration, Self.minimumLengthMilliseconds)
        var s = min(max(start, 0), duration - Self.minimumLengthMilliseconds)
        var e = min(max(end, s + Self.minimumLengthMilliseconds), duration)
        if e - s > Self.maximumLengthMilliseconds { s = e - Self.maximumLengthMilliseconds }
        s = max(s, 0)
        e = max(e, s + Self.minimumLengthMilliseconds)
        startMilliseconds = s
        endMilliseconds = e
        sourceDurationMilliseconds = duration
    }

    /// The default capture ending at `position`: the preceding 30 seconds, clamped to the source.
    public static func preceding(position: Int64, sourceDuration: Int64) -> AudioRange {
        let end = min(max(position, 0), sourceDuration)
        return AudioRange(start: end - defaultLengthMilliseconds, end: end, sourceDuration: sourceDuration)
    }

    public enum Edge: Sendable { case start, end }

    /// Moves one edge by `steps` steps (negative is earlier) and re-applies the rules; the other edge
    /// stays put unless the 120 s limit or the minimum length forces it.
    public func moving(_ edge: Edge, by steps: Int) -> AudioRange {
        let delta = Int64(steps) * Self.stepMilliseconds
        switch edge {
        case .start:
            let start = min(max(startMilliseconds + delta, max(0, endMilliseconds - Self.maximumLengthMilliseconds)),
                            endMilliseconds - Self.minimumLengthMilliseconds)
            return AudioRange(start: start, end: endMilliseconds, sourceDuration: sourceDurationMilliseconds)
        case .end:
            let end = max(min(endMilliseconds + delta,
                              min(sourceDurationMilliseconds, startMilliseconds + Self.maximumLengthMilliseconds)),
                          startMilliseconds + Self.minimumLengthMilliseconds)
            return AudioRange(start: startMilliseconds, end: end, sourceDuration: sourceDurationMilliseconds)
        }
    }

    public func canMove(_ edge: Edge, by steps: Int) -> Bool { moving(edge, by: steps) != self }
}

/// Timecodes in the Monospace face (Section 4.4.6): "11:12.0", "1:02:03.5". Tenths, truncated.
public enum Timecode {
    public static func text(milliseconds: Int64, tenths: Bool = true) -> String {
        let ms = max(milliseconds, 0)
        let totalSeconds = ms / 1000
        let h = totalSeconds / 3600, m = (totalSeconds % 3600) / 60, s = totalSeconds % 60
        let tenth = (ms % 1000) / 100
        let seconds = s < 10 ? "0\(s)" : "\(s)"
        let base: String
        if h > 0 {
            base = "\(h):" + (m < 10 ? "0\(m)" : "\(m)") + ":" + seconds
        } else {
            base = "\(m):" + seconds
        }
        return tenths ? base + ".\(tenth)" : base
    }
}
