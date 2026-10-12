import SwiftUI

/// The four button roles of Section 4.4.7.
///
/// Usage rules (ADR-0013 Section 10):
/// - **One primary per screen.** A screen has at most one Pine primary button: the action the
///   screen exists for. Every primary button publishes ``PrimaryButtonCountKey`` so a screen test
///   can assert the count (`.onPreferenceChange(PrimaryButtonCountKey.self)`).
/// - **Destructive never beside a primary.** A destructive button is never in the same row as a
///   primary and never directly next to it in a stack; put the safe choice first, then a secondary
///   or quiet option, then the destructive one.
/// - Secondary for alternatives of equal standing; quiet for inline and low-emphasis actions.
public enum SylviaButtonRole: String, CaseIterable, Sendable {
    /// Pine fill, `pine.on` text, 50 pt, radius 12. One per screen.
    case primary
    /// Hairline border, ink text, 50 pt, radius 12.
    case secondary
    /// Pine text, no border, at least 44 pt.
    case quiet
    /// Attention text and 1 pt attention border, 50 pt, radius 12.
    case destructive

    /// The token-level definition (exported as `components.button_roles`).
    public var definition: ComponentRoles.Button {
        guard let match = ComponentRoles.buttons.first(where: { $0.name == rawValue }) else {
            preconditionFailure("no button role \(rawValue) in ComponentRoles")
        }
        return match
    }

    /// Text and glyph color.
    public var foreground: ColorToken { definition.text }

    /// Fill, or nil for none (the ground shows through).
    public var fill: ColorToken? { definition.fill }

    /// Border, or nil for none.
    public var border: ColorToken? { definition.border }

    public var minimumHeight: Double { definition.minimumHeight }
}

/// Counts primary buttons under a view (the one-primary-per-screen rule).
public struct PrimaryButtonCountKey: PreferenceKey {
    public static let defaultValue = 0
    public static func reduce(value: inout Int, nextValue: () -> Int) { value += nextValue() }
}

/// The Marginalia button style. Labels wrap at large text sizes instead of truncating, and the
/// button grows with them; pressing dims the label (an opacity change, which Reduce Motion keeps).
public struct SylviaButtonStyle: ButtonStyle {
    public let role: SylviaButtonRole
    /// Stretch to the available width (default for every role but quiet).
    public let fillsWidth: Bool

    public init(_ role: SylviaButtonRole, fillsWidth: Bool? = nil) {
        self.role = role
        self.fillsWidth = fillsWidth ?? (role != .quiet)
    }

    public func makeBody(configuration: Configuration) -> some View {
        SylviaButtonBody(role: role, fillsWidth: fillsWidth, isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

struct SylviaButtonBody<Label: View>: View {
    let role: SylviaButtonRole
    let fillsWidth: Bool
    let isPressed: Bool
    @ViewBuilder let label: Label
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.sylviaButtonBusy) private var isBusy

    var body: some View {
        label
            .sylviaFont(.body, weight: role == .quiet ? ComponentMetrics.quietLabelWeight : ComponentMetrics.labelWeight)
            .multilineTextAlignment(.center)
            // The label always gets the height it needs, so it wraps instead of truncating (T51).
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(role.foreground.color)
            .padding(.horizontal, role == .quiet ? 0 : ComponentMetrics.buttonHorizontalPadding)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: role.minimumHeight)
            .contentShape(Rectangle())
            .background {
                if let fill = role.fill {
                    RoundedRectangle(cornerRadius: Radius.button.value, style: .continuous).fill(fill.color)
                        .sylviaAuditRegion("button.\(role.rawValue).fill")
                }
            }
            .overlay {
                if let border = role.border {
                    RoundedRectangle(cornerRadius: Radius.button.value, style: .continuous)
                        .strokeBorder(border.color, lineWidth: Hairline.width)
                }
            }
            .sylviaAuditRegion("button.\(role.rawValue)")
            // Pressed and disabled states change opacity only (kept under Reduce Motion). A disabled
            // button fades; a busy one (disabled while its label reports a state, such as
            // "Saving…") keeps full contrast, because its label is a status to read (R1-03).
            .opacity(isEnabled || isBusy ? (isPressed ? ComponentMetrics.pressedOpacity : 1) : ComponentMetrics.disabledOpacity)
            .preference(key: PrimaryButtonCountKey.self, value: role == .primary ? 1 : 0)
    }
}

extension EnvironmentValues {
    /// Set by ``SwiftUI/View/sylviaButtonBusy(_:)``.
    @Entry public var sylviaButtonBusy: Bool = false
}

extension View {
    /// Marks Sylvia buttons below as busy: combine with `.disabled(true)` while the button's label
    /// is a status of a running operation ("Saving…"). The button still cannot be pressed and
    /// VoiceOver still reports it as dimmed, but it is drawn at full contrast instead of the
    /// disabled fade, so its label meets 4.5:1 (Section 4.4.2).
    public func sylviaButtonBusy(_ busy: Bool) -> some View {
        environment(\.sylviaButtonBusy, busy)
    }
}

extension ButtonStyle where Self == SylviaButtonStyle {
    /// `Button("Read") { }.buttonStyle(.sylvia(.secondary))`
    public static func sylvia(_ role: SylviaButtonRole, fillsWidth: Bool? = nil) -> SylviaButtonStyle {
        SylviaButtonStyle(role, fillsWidth: fillsWidth)
    }
}

/// An icon-only button: a plain glyph in ink (or Pine when selected), a 44 pt target, an
/// accessibility label (required: every icon-only control has one, Section 4.4.8) and the large
/// content viewer, which shows the glyph and label enlarged on long press at accessibility sizes.
public struct SylviaIconButton: View {
    let image: Image
    let label: String
    let isSelected: Bool
    let action: () -> Void
    @State private var gate = LiftActivationGate()

    public init(systemImage: String, label: String, isSelected: Bool = false, action: @escaping () -> Void) {
        self.image = Image(systemName: systemImage)
        self.label = label
        self.isSelected = isSelected
        self.action = action
    }

    init(image: Image, label: String, isSelected: Bool, action: @escaping () -> Void) {
        self.image = image
        self.label = label
        self.isSelected = isSelected
        self.action = action
    }

    public init(symbol: CustomSymbol, label: String, isSelected: Bool = false, action: @escaping () -> Void) {
        self.image = symbol.image
        self.label = label
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button {
            gate.run(action)
        } label: {
            image
                .sylviaFont(.body)
                .foregroundStyle((isSelected ? ColorToken.pine : ColorToken.ink).color)
                .frame(minWidth: ComponentMetrics.minimumTarget, minHeight: ComponentMetrics.minimumTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Label { Text(label) } icon: { image }
        }
        .sylviaLiftActivation(gate: gate, action: action)
    }
}
