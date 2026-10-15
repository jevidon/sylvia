import SwiftUI

/// A status pill (Section 4.4.7): radius full, a Caption label, always a glyph (dot, check or
/// triangle), filled with the state's tint. The glyph and the phrase carry the state, so pills stay
/// distinct in grayscale where their tints become similar greys (Section 4.4.8, T53).
public struct StatusPill: View {
    /// What a pill shows; tests read it to prove two pills differ by glyph and label.
    public struct Configuration: Sendable, Hashable {
        public let status: Status
        public let glyph: StatusGlyph
        public let textColor: ColorToken
        public let fill: ColorToken

        public init(status: Status, glyph: StatusGlyph, textColor: ColorToken, fill: ColorToken) {
            self.status = status
            self.glyph = glyph
            self.textColor = textColor
            self.fill = fill
        }

        /// The pill for an import state (Section 4.4.6 mapping), or nil for `cancelled`, which
        /// leaves the Inbox. `source` names the source for `waiting_for_source`.
        public init?(importState: ImportState, indexingContinues: Bool = false, source: String = "") {
            guard let p = importState.presentation(indexingContinues: indexingContinues) else { return nil }
            let status: Status
            switch p.phrase {
            case .importWaitingForSource: status = .waitingFor(source: source)
            default:
                guard let s = Status(key: p.phrase) else { return nil }
                status = s
            }
            self.init(status: status, glyph: p.glyph, textColor: p.textColor, fill: p.fill)
        }

        /// Pending treatment (dot, muted on the pending tint) for any status phrase.
        public static func pending(_ status: Status) -> Configuration {
            Configuration(status: status, glyph: .dot, textColor: .markerPendingText, fill: .markerPendingTint)
        }

        /// Ready treatment (check, Pine on the Pine tint).
        public static func ready(_ status: Status) -> Configuration {
            Configuration(status: status, glyph: .check, textColor: .pine, fill: .pineTint)
        }

        /// Attention treatment (triangle, attention on its tint).
        public static func attention(_ status: Status) -> Configuration {
            Configuration(status: status, glyph: .triangle, textColor: .markerAttentionText, fill: .markerAttentionTint)
        }

        /// The label as shown and as spoken.
        public var text: String { status.text() }
    }

    public let configuration: Configuration

    public init(_ configuration: Configuration) {
        self.configuration = configuration
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ComponentMetrics.glyphGap) {
            configuration.glyph.image
                .imageScale(configuration.glyph == .dot ? .small : .medium)
                .accessibilityHidden(true)
                .sylviaAuditRegion("pill.glyph")
            Text(configuration.text)
                .sylviaAuditRegion("pill.label")
        }
        .sylviaFont(.caption, weight: ComponentMetrics.labelWeight)
        .foregroundStyle(configuration.textColor.color)
        .padding(.horizontal, ComponentMetrics.pillHorizontalPadding)
        .padding(.vertical, ComponentMetrics.pillVerticalPadding)
        .frame(minHeight: ComponentMetrics.pillMinimumHeight)
        .sylviaFill(configuration.fill, .pill)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(configuration.text))
        .sylviaAuditRegion("pill")
    }
}

/// Where a work's file is (Section 4.4.6 "Where a file is"; Section 12).
public enum Availability: Sendable, Hashable {
    case onThisDevice
    case notOnThisDevice(source: String)
    case recordOnly

    public var status: Status {
        switch self {
        case .onThisDevice: .onThisDevice
        case .notOnThisDevice(let source): .notOnThisDevice(source: source)
        case .recordOnly: .recordOnly
        }
    }

    /// Solid hairline for a file on this device; dashed in muted when there is none here.
    public var isDashed: Bool { self != .onThisDevice }
}

/// An availability badge (Section 4.4.7): a hairline pill "On this device"; a dashed hairline pill
/// in `muted` for "Not on this device · from {source}" and "Record only". The frame (solid or
/// dashed) and the phrase carry the meaning; no fill.
public struct AvailabilityBadge: View {
    public let availability: Availability

    public init(_ availability: Availability) {
        self.availability = availability
    }

    public var body: some View {
        let text = availability.status.text()
        Text(text)
            .sylviaFont(.caption)
            .foregroundStyle((availability.isDashed ? ColorToken.muted : ColorToken.ink).color)
            .padding(.horizontal, ComponentMetrics.pillHorizontalPadding)
            .padding(.vertical, ComponentMetrics.pillVerticalPadding)
            .frame(minHeight: ComponentMetrics.pillMinimumHeight)
            .sylviaBorder(.pill, color: availability.isDashed ? .muted : .hairline, dashed: availability.isDashed)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(text))
            .sylviaAuditRegion("badge")
    }
}
