import SwiftUI

/// The rating (Section 4.4.7, 12): five stars in Ochre, half-star steps, stored as an integer 1-10.
/// Filled, half and outline stars are different shapes, so the value reads in grayscale.
///
/// Interactive when `value` is a binding: each star is one 44 pt target (a tap sets that star full;
/// tapping a full star sets it to half), VoiceOver adjusts by half steps, and clearing is the
/// separate "Clear rating" action, never a zero.
public struct RatingView: View {
    let value: RatingValue?
    let binding: Binding<RatingValue?>?

    /// Read-only rating.
    public init(_ value: RatingValue?) {
        self.value = value
        self.binding = nil
    }

    /// Editable rating.
    public init(value: Binding<RatingValue?>) {
        self.value = value.wrappedValue
        self.binding = value
    }

    /// The fills drawn, star by star (tests read them).
    public var fills: [RatingValue.StarFill] {
        (0..<RatingValue.starCount).map { RatingValue.fill(star: $0, value: value) }
    }

    /// The spoken value: "3.5 of 5 stars" or "No rating".
    public static func accessibilityValue(_ value: RatingValue?, locale: Locale = .current) -> String {
        guard let value else { return LabelKey.ratingNone.localized }
        let stars = value.stars.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        return VocabularyCatalog.render(FormatKey.ratingValue.rawValue, arguments: [.string(stars)], locale: locale)
    }

    public var body: some View {
        // "Clear rating" follows the stars, or moves below them when the row does not fit.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.xs) { stars; clearButton }
            VStack(alignment: .leading, spacing: 0) { stars; clearButton }
        }
    }

    @ViewBuilder private var clearButton: some View {
        if let binding, binding.wrappedValue != nil {
            Button(LabelKey.ratingClear.localized) { binding.wrappedValue = nil }
                .buttonStyle(.sylvia(.quiet))
        }
    }

    private var stars: some View {
        HStack(spacing: binding == nil ? Spacing.xxs : 0) {
            ForEach(0..<RatingValue.starCount, id: \.self) { index in
                let image = Image(systemName: fills[index].systemSymbol)
                    .sylviaFont(.body)
                    .foregroundStyle(ColorToken.ochre.color)
                    .sylviaAuditRegion("rating.star\(index)")
                if let binding {
                    Button {
                        binding.wrappedValue = RatingValue.tapping(star: index, current: binding.wrappedValue)
                    } label: {
                        image.frame(minWidth: ComponentMetrics.minimumTarget, minHeight: ComponentMetrics.minimumTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    image
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LabelKey.ratingLabel.localized))
        .accessibilityValue(Text(Self.accessibilityValue(value)))
        .modifier(RatingAdjustable(binding: binding))
    }
}

private struct RatingAdjustable: ViewModifier {
    let binding: Binding<RatingValue?>?

    func body(content: Content) -> some View {
        if let binding {
            content.accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: binding.wrappedValue = RatingValue.incremented(binding.wrappedValue)
                case .decrement: binding.wrappedValue = RatingValue.decremented(binding.wrappedValue)
                @unknown default: break
                }
            }
        } else {
            content
        }
    }
}

/// The progress rule (Section 4.4.7): a 3 pt track in `hairline` with a Pine fill; the caption gives
/// chapter or part and percent, with time remaining in Monospace. The fill animates (200 ms
/// ease-out) except under Reduce Motion.
public struct ProgressRule: View {
    public enum Position: Sendable, Hashable {
        case chapter(Int, of: Int)
        case part(Int, of: Int)

        public var text: String {
            switch self {
            case .chapter(let n, let m):
                VocabularyCatalog.render(FormatKey.positionChapter.rawValue, arguments: [.integer(Int64(n)), .integer(Int64(m))], locale: .current)
            case .part(let n, let m):
                VocabularyCatalog.render(FormatKey.positionPart.rawValue, arguments: [.integer(Int64(n)), .integer(Int64(m))], locale: .current)
            }
        }
    }

    let fraction: Double
    let position: Position?
    let secondsRemaining: Int?

    /// `fraction` is clamped to 0...1. Without a position and time, only the rule is drawn (Inbox
    /// rows).
    public init(fraction: Double, position: Position? = nil, secondsRemaining: Int? = nil) {
        self.fraction = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        self.position = position
        self.secondsRemaining = secondsRemaining
    }

    public var percentText: String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            rule
            if position != nil || secondsRemaining != nil {
                caption
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(position?.text ?? percentText))
        .accessibilityValue(Text(Microcopy.joined([position == nil ? "" : percentText,
                                                   secondsRemaining.map { Durations.left(seconds: $0) } ?? ""])))
    }

    private var rule: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(ColorToken.hairline.color)
                Rectangle().fill(ColorToken.pine.color)
                    .frame(width: proxy.size.width * fraction)
                    .sylviaAnimation(Motion.progressRule, value: fraction)
                    .sylviaAuditRegion("progress.fill")
            }
        }
        .frame(height: ComponentMetrics.progressRuleThickness)
        .sylviaAuditRegion("progress.track")
    }

    @ViewBuilder private var caption: some View {
        let parts = ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.xs) { captionTexts }
            VStack(alignment: .leading, spacing: Spacing.xxs) { captionTexts }
        }
        parts
    }

    @ViewBuilder private var captionTexts: some View {
        if let position {
            Text(Microcopy.joined([position.text, percentText]))
                .sylviaFont(.caption)
                .foregroundStyle(ColorToken.muted.color)
        }
        if let secondsRemaining {
            Text(Durations.left(seconds: secondsRemaining))
                .sylviaFont(.caption, monospaced: true)
                .foregroundStyle(ColorToken.muted.color)
        }
    }
}
