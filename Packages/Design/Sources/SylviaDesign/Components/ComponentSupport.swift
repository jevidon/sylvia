import SwiftUI

// Shared pieces of the component library (plan Section 4.4.4, 4.4.7): borders, elevation, motion
// and the layout audit used by the snapshot tests.

extension Radius {
    /// The radius in points; pills use half their height through ``Capsule`` instead.
    var value: CGFloat { CGFloat(points ?? 0) }
}

extension View {
    /// A 1 pt border inside the shape: solid in `color` (the hairline token by default) or dashed.
    func sylviaBorder(_ radius: Radius, color: ColorToken = .hairline, dashed: Bool = false) -> some View {
        overlay {
            if radius == .pill {
                Capsule().strokeBorder(color.color, style: SylviaStroke.style(dashed: dashed))
            } else {
                RoundedRectangle(cornerRadius: radius.value, style: .continuous)
                    .strokeBorder(color.color, style: SylviaStroke.style(dashed: dashed))
            }
        }
    }

    /// The single shadow (Section 4.4.4: 0 8 24 at 10% ink), for sheets and the mini-player only.
    /// CSS blur 24 corresponds to a Core Animation shadow radius of 12 (blur = 2 x radius).
    public func sylviaElevation() -> some View {
        shadow(color: ColorToken.shadow.color, radius: Elevation.shadowBlur / 2,
               x: Elevation.shadowX, y: Elevation.shadowY)
    }

    /// Fills the shape's background with a token.
    func sylviaFill(_ token: ColorToken, _ radius: Radius) -> some View {
        background {
            if radius == .pill {
                Capsule().fill(token.color)
            } else {
                RoundedRectangle(cornerRadius: radius.value, style: .continuous).fill(token.color)
            }
        }
    }
}

enum SylviaStroke {
    static func style(dashed: Bool) -> StrokeStyle {
        StrokeStyle(lineWidth: Hairline.width,
                    dash: dashed ? [ComponentMetrics.dashLength, ComponentMetrics.dashGap] : [])
    }
}

// MARK: Motion

/// Motion per Section 4.4.4: sheets 200 ms ease-out, highlights 120 ms, progress rules animate,
/// nothing bounces. Under Reduce Motion every animation that moves something is removed; only
/// opacity changes may remain.
public enum SylviaMotion {
    /// The animation for `spec`, or nil (no animation) under Reduce Motion.
    public static func animation(_ spec: MotionSpec, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        switch spec.curve {
        case .easeOut: return .easeOut(duration: spec.duration)
        }
    }
}

struct SylviaAnimationModifier<Value: Equatable>: ViewModifier {
    let spec: MotionSpec
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(SylviaMotion.animation(spec, reduceMotion: reduceMotion), value: value)
    }
}

extension View {
    /// Animates changes of `value` with `spec`, or not at all under Reduce Motion.
    public func sylviaAnimation(_ spec: MotionSpec, value: some Equatable) -> some View {
        modifier(SylviaAnimationModifier(spec: spec, value: value))
    }
}

// MARK: Layout audit

/// Collects layout facts while components render: each styled text's laid-out frame and the
/// height it would need without a line limit, and named regions. The snapshot tests use it to
/// detect truncated or clipped labels at the largest accessibility size (T51) and to find the
/// regions they measure in grayscale (T53). Absent (nil) in the app, where it costs nothing.
@MainActor
public final class LayoutAudit {
    public struct TextReport: Sendable, Hashable {
        public let role: TypeRole
        /// The text's frame in the window.
        public let frame: CGRect
        /// The height the text needs at its laid-out width with no line limit.
        public let neededHeight: CGFloat

        /// True when the text was given less height than it needs (truncated or cut off).
        public var isTruncated: Bool { neededHeight > frame.height + 0.5 }
    }

    private var actual: [UUID: (TypeRole, CGRect)] = [:]
    private var needed: [UUID: CGFloat] = [:]
    private var order: [UUID] = []
    /// Texts currently on screen (between `onAppear` and `onDisappear`).
    private var onScreen: Set<UUID> = []
    /// Whether only texts on screen count (see ``init(countsOnlyAppearedTexts:)``).
    public let countsOnlyAppearedTexts: Bool
    public private(set) var regions: [String: CGRect] = [:]

    /// `countsOnlyAppearedTexts`: in a live window (the design catalog), a layout that measures
    /// alternatives (`ViewThatFits`) reports geometry for the candidates it does not show, at
    /// positions off the screen, and removed views leave their last frame behind; only texts
    /// between `onAppear` and `onDisappear` are then counted. The offscreen renderer of the
    /// snapshot tests never runs `onAppear`, so it uses the default (every text that reported).
    public init(countsOnlyAppearedTexts: Bool = false) {
        self.countsOnlyAppearedTexts = countsOnlyAppearedTexts
    }

    private func counts(_ id: UUID) -> Bool {
        !countsOnlyAppearedTexts || onScreen.contains(id)
    }

    func recordFrame(_ id: UUID, role: TypeRole, frame: CGRect) {
        if actual[id] == nil && needed[id] == nil { order.append(id) }
        actual[id] = (role, frame)
    }

    func recordNeededHeight(_ id: UUID, height: CGFloat) {
        if actual[id] == nil && needed[id] == nil { order.append(id) }
        needed[id] = height
    }

    func setOnScreen(_ id: UUID, _ isOnScreen: Bool) {
        if isOnScreen { onScreen.insert(id) } else { onScreen.remove(id) }
    }

    func recordRegion(_ name: String, frame: CGRect) {
        regions[name] = frame
    }

    /// Every counted styled text that reported both its frame and its needed height, in report
    /// order.
    public var texts: [TextReport] {
        order.compactMap { id in
            guard counts(id), let (role, frame) = actual[id], let height = needed[id] else { return nil }
            return TextReport(role: role, frame: frame, neededHeight: height)
        }
    }

    /// Counted texts that reported only one of the two facts (should be zero once layout settles).
    public var incompleteReports: Int {
        order.filter { counts($0) && (actual[$0] == nil) != (needed[$0] == nil) }.count
    }

    /// With `countsOnlyAppearedTexts`, the texts left out because they are not on screen (unchosen
    /// `ViewThatFits` candidates, removed views); zero otherwise.
    public var notCountedReports: Int {
        order.filter { !counts($0) }.count
    }
}

extension EnvironmentValues {
    /// Set by tests and the design catalog to collect layout facts; nil in the app.
    @Entry public var sylviaLayoutAudit: LayoutAudit? = nil
    /// Prefix for region names reported under this view (tests set one per sample).
    @Entry public var sylviaAuditScope: String = ""
}

/// Identity of one audited text, kept in view state so re-renders report under the same key.
final class AuditKey: Sendable {
    let id = UUID()
}

/// Reports a styled text's frame and needed height to the layout audit, when one is installed.
struct TextAuditModifier: ViewModifier {
    let role: TypeRole
    @Environment(\.sylviaLayoutAudit) private var audit
    @State private var key = AuditKey()

    func body(content: Content) -> some View {
        if let audit {
            let id = key.id
            let role = self.role
            content
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                    audit.recordFrame(id, role: role, frame: frame)
                }
                .onAppear { audit.setOnScreen(id, true) }
                .onDisappear { audit.setOnScreen(id, false) }
                .background(alignment: .topLeading) {
                    content
                        .environment(\.sylviaLayoutAudit, nil)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .accessibilityHidden(true)
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                            audit.recordNeededHeight(id, height: height)
                        }
                }
        } else {
            content
        }
    }
}

struct RegionAuditModifier: ViewModifier {
    let name: String
    @Environment(\.sylviaLayoutAudit) private var audit
    @Environment(\.sylviaAuditScope) private var scope

    func body(content: Content) -> some View {
        if let audit {
            let key = scope.isEmpty ? name : "\(scope).\(name)"
            content.onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                audit.recordRegion(key, frame: frame)
            }
        } else {
            content
        }
    }
}

extension View {
    /// Names this view's frame in the layout audit (tests measure these regions in grayscale).
    public func sylviaAuditRegion(_ name: String) -> some View {
        modifier(RegionAuditModifier(name: name))
    }
}
