import SwiftUI

/// The marker row at the top of any capture (Section 4.4.5): glyph, then the uppercase Micro label
/// and the source details, in the marker's color, with an optional Monospace timestamp. Two
/// markers never share a row without their labels: the label is always shown.
public struct MarkerRow: View {
    public struct Configuration: Sendable, Hashable {
        public let marker: Marker
        /// The marker's label, or the raw kind for a capture kind this client does not recognize.
        public let label: String
        /// Source label and further details ("Middlemarch", "Book II, ch. 20", "0:30").
        public let details: [String]
        /// A time already formatted (shown in the Monospace face), or nil.
        public let timestamp: String?

        public init(marker: Marker, details: [String] = [], timestamp: String? = nil) {
            self.marker = marker
            self.label = marker.labelKey.localized
            self.details = details
            self.timestamp = timestamp
        }

        /// From a portable capture kind: an unrecognized kind shows the Pending marker with its raw
        /// kind as the label, never the Quote marker (Appendix A.1).
        public init(captureKind: String, details: [String] = [], timestamp: String? = nil) {
            self.init(resolution: Marker.resolve(captureKind: captureKind), details: details, timestamp: timestamp)
        }

        public init(resolution: MarkerResolution, details: [String], timestamp: String?) {
            self.marker = resolution.marker
            self.label = Marker.label(for: resolution)
            self.details = details
            self.timestamp = timestamp
        }

        /// The glyph identifier drawn for this row.
        public var glyph: String { marker.glyph.identifier }

        /// The visible text after the glyph (shown uppercase by the Micro role).
        public var text: String { Microcopy.joined([label] + details) }

        /// What VoiceOver reads: the label in sentence case, then the details and the time.
        public var accessibilityText: String {
            ([label] + details + (timestamp.map { [$0] } ?? [])).filter { !$0.isEmpty }.joined(separator: ", ")
        }
    }

    public let configuration: Configuration
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(_ configuration: Configuration) {
        self.configuration = configuration
    }

    public var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xxs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.xs))
        layout {
            // At accessibility sizes the glyph takes its own line so the label has the full width.
            let label = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xxs))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: ComponentMetrics.glyphGap))
            label {
                MarkerGlyph(configuration.marker, role: .caption)
                    .sylviaAuditRegion("marker.glyph")
                Text(configuration.text)
                    .sylviaFont(.micro)
                    .foregroundStyle(configuration.marker.textColor.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            if let timestamp = configuration.timestamp {
                Text(timestamp)
                    .sylviaFont(.caption, monospaced: true)
                    .foregroundStyle(ColorToken.muted.color)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(configuration.accessibilityText))
        .sylviaAuditRegion("marker")
    }
}

/// The Attention status row (Section 4.4.5): a tinted row with the triangle, "Needs attention",
/// the reason and the next step. It cannot be built without both (Section 4.4.6: never without a
/// reason and a next step).
public struct AttentionRow<Actions: View>: View {
    let reason: String
    let nextStep: String
    let actions: Actions

    public init(reason: String, nextStep: String, @ViewBuilder actions: () -> Actions) {
        precondition(!reason.isEmpty && !nextStep.isEmpty, "Needs attention requires a reason and a next step")
        self.reason = reason
        self.nextStep = nextStep
        self.actions = actions()
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public var body: some View {
        // At accessibility sizes the glyph sits above the text so the reason has the full width.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xxs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.s))
        layout {
            MarkerGlyph(.attention, role: .body)
                .accessibilityHidden(true)
                .sylviaAuditRegion("attention.glyph")
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(Marker.attention.labelKey.localized)
                    .sylviaFont(.micro)
                    .foregroundStyle(Marker.attention.textColor.color)
                Text(reason)
                    .sylviaFont(.body, weight: ComponentMetrics.labelWeight)
                    .foregroundStyle(ColorToken.ink.color)
                Text(nextStep)
                    .sylviaFont(.body)
                    .foregroundStyle(ColorToken.ink.color)
                actions
            }
            .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ComponentMetrics.cardPadding)
        .sylviaFill(.markerAttentionTint, .block)
        .accessibilityElement(children: .combine)
        .sylviaAuditRegion("attention")
    }
}

extension AttentionRow where Actions == EmptyView {
    public init(reason: String, nextStep: String) {
        self.init(reason: reason, nextStep: nextStep) { EmptyView() }
    }
}
