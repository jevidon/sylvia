import SwiftUI

/// The three primary areas (Section 4.1).
public enum SylviaArea: String, CaseIterable, Sendable, Hashable, Identifiable {
    case library
    case thoughts
    case inbox

    public var id: String { rawValue }

    public var labelKey: LabelKey {
        switch self {
        case .library: .areaLibrary
        case .thoughts: .areaThoughts
        case .inbox: .areaInbox
        }
    }

    public var label: String { labelKey.localized }

    /// SF Symbol of the area (Library: books, Thoughts: quotation mark, Inbox: tray, as the boards).
    public var systemSymbol: String {
        switch self {
        case .library: ControlSymbol.areaLibrary.systemName
        case .thoughts: ControlSymbol.areaThoughts.systemName
        case .inbox: ControlSymbol.areaInbox.systemName
        }
    }

    /// Hardware keyboard shortcut: Command-1, -2, -3, listed in the iPad shortcut overlay.
    public var keyboardShortcut: KeyEquivalent {
        switch self {
        case .library: "1"
        case .thoughts: "2"
        case .inbox: "3"
        }
    }
}

extension DynamicTypeSize {
    /// Bars stop growing here, as system bars do (``ComponentMetrics/barMaximumTextSize``); the
    /// large content viewer shows each item enlarged at accessibility sizes.
    public static let sylviaBarMaximum: DynamicTypeSize = .xxxLarge
}

/// The tab bar (Section 4.4.7): Sylvia's own opaque component, not the system tab bar. `surface`
/// with a hairline top rule; Library, Thoughts, Inbox; active in Pine, inactive in `muted`; an
/// `attention` dot on Inbox when an item needs the user.
///
/// Each item is a button with the selected trait when active, its area name as label ("Needs
/// attention" as value when the dot shows), the large content viewer (it does not grow past
/// xxxLarge, like the system bar; lifting the finger opens the item under it, as on a system tab
/// bar), and Command-1/2/3 on a hardware keyboard. The bar is a tab-bar container for VoiceOver.
public struct SylviaTabBar: View {
    @Binding var selection: SylviaArea
    let inboxNeedsAttention: Bool
    @State private var gate = LiftActivationGate()
    @State private var itemFrames: [SylviaArea: CGRect] = [:]

    public init(selection: Binding<SylviaArea>, inboxNeedsAttention: Bool) {
        self._selection = selection
        self.inboxNeedsAttention = inboxNeedsAttention
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(SylviaArea.allCases) { area in
                AreaButton(area: area, isSelected: selection == area,
                           needsAttention: area == .inbox && inboxNeedsAttention, layout: .tab) {
                    gate.run { selection = area }
                }
                .areaFrame(area, in: Self.space) { itemFrames[area] = $0 }
            }
        }
        .padding(.vertical, ComponentMetrics.barVerticalPadding)
        .sylviaBarLiftActivation(space: Self.space, gate: gate) { point in
            SylviaArea.item(at: point, in: itemFrames).map { area in { selection = area } }
        }
        .dynamicTypeSize(...DynamicTypeSize.sylviaBarMaximum)
        .background {
            ColorToken.surface.color.ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(ColorToken.hairline.color).frame(height: Hairline.width)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
    }

    private static let space = "sylvia.tabBar"
}

/// The iPad sidebar (Section 4.4.7: in regular width the three areas move to a sidebar built from
/// the same tokens). Rows grow with Dynamic Type; the active row has the Pine tint and Pine text.
public struct SylviaSidebar: View {
    @Binding var selection: SylviaArea
    let inboxNeedsAttention: Bool
    @State private var gate = LiftActivationGate()
    @State private var itemFrames: [SylviaArea: CGRect] = [:]

    public init(selection: Binding<SylviaArea>, inboxNeedsAttention: Bool) {
        self._selection = selection
        self.inboxNeedsAttention = inboxNeedsAttention
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            ForEach(SylviaArea.allCases) { area in
                AreaButton(area: area, isSelected: selection == area,
                           needsAttention: area == .inbox && inboxNeedsAttention, layout: .row) {
                    gate.run { selection = area }
                }
                .areaFrame(area, in: Self.space) { itemFrames[area] = $0 }
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.s)
        .sylviaBarLiftActivation(space: Self.space, gate: gate) { point in
            SylviaArea.item(at: point, in: itemFrames).map { area in { selection = area } }
        }
        .frame(width: ComponentMetrics.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ColorToken.surface.color.ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle().fill(ColorToken.hairline.color).frame(width: Hairline.width).ignoresSafeArea()
        }
        .accessibilityElement(children: .contain)
    }

    private static let space = "sylvia.sidebar"
}

extension SylviaArea {
    /// The area whose item frame contains `point` (the large content viewer's lift activation).
    static func item(at point: CGPoint, in frames: [SylviaArea: CGRect]) -> SylviaArea? {
        allCases.first { frames[$0]?.contains(point) == true }
    }
}

private extension View {
    /// Reports this item's frame in the bar's coordinate space.
    func areaFrame(_ area: SylviaArea, in space: String, _ report: @escaping (CGRect) -> Void) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { report($0) }
    }
}

/// Picks the tab bar in compact width and the sidebar in regular width (Section 4.4.7).
public struct SylviaAreaNavigation<Content: View>: View {
    @Binding var selection: SylviaArea
    let inboxNeedsAttention: Bool
    let content: Content
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(selection: Binding<SylviaArea>, inboxNeedsAttention: Bool, @ViewBuilder content: () -> Content) {
        self._selection = selection
        self.inboxNeedsAttention = inboxNeedsAttention
        self.content = content()
    }

    public var body: some View {
        if sizeClass == .regular {
            HStack(spacing: 0) {
                SylviaSidebar(selection: $selection, inboxNeedsAttention: inboxNeedsAttention)
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 0) {
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
                SylviaTabBar(selection: $selection, inboxNeedsAttention: inboxNeedsAttention)
            }
        }
    }
}

struct AreaButton: View {
    enum Layout { case tab, row }

    let area: SylviaArea
    let isSelected: Bool
    let needsAttention: Bool
    let layout: Layout
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            content
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(area.keyboardShortcut, modifiers: .command)
        .accessibilityLabel(Text(area.label))
        .accessibilityValue(Text(needsAttention ? Status.needsAttention.text() : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Label { Text(area.label) } icon: { Image(systemName: area.systemSymbol) }
        }
        .sylviaAuditRegion("area.\(area.rawValue)")
    }

    private var tint: ColorToken {
        switch layout {
        case .tab: isSelected ? .pine : .muted
        case .row: isSelected ? .pine : .ink
        }
    }

    @ViewBuilder private var content: some View {
        switch layout {
        case .tab:
            VStack(spacing: Spacing.xxs) {
                icon.sylviaFont(.heading)
                Text(area.label)
                    .sylviaFont(.caption, weight: isSelected ? ComponentMetrics.labelWeight : nil)
            }
            .foregroundStyle(tint.color)
            .frame(maxWidth: .infinity, minHeight: ComponentMetrics.minimumTarget)
        case .row:
            // At accessibility sizes the glyph sits above the label, so the label keeps the row's
            // full width and never breaks inside a word ("Thoughts" did at AX5 in 320 pt; found on
            // the iPad simulator by the design catalog, G0.6 part 3).
            let rowLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xxs))
                : AnyLayout(HStackLayout(spacing: Spacing.s))
            rowLayout {
                icon.sylviaFont(.body)
                    .frame(minWidth: ComponentMetrics.minimumTarget / 2)
                Text(area.label)
                    .sylviaFont(.body, weight: isSelected ? ComponentMetrics.labelWeight : nil)
                    .fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(tint.color)
            .padding(.horizontal, Spacing.s)
            .frame(minHeight: ComponentMetrics.minimumTarget)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Radius.control.value, style: .continuous)
                        .fill(ColorToken.pineTint.color)
                }
            }
        }
    }

    private var icon: some View {
        Image(systemName: area.systemSymbol)
            .overlay(alignment: .topTrailing) {
                if needsAttention {
                    Circle()
                        .fill(ColorToken.markerAttentionText.color)
                        .frame(width: ComponentMetrics.attentionDot, height: ComponentMetrics.attentionDot)
                        .offset(x: ComponentMetrics.attentionDot / 2, y: -ComponentMetrics.attentionDot / 4)
                        .sylviaAuditRegion("area.attentionDot")
                }
            }
    }
}

/// A navigation bar button (Section 4.4.7: Search and Settings live in the navigation bar).
public struct SylviaBarItem: Identifiable {
    public let id: String
    let image: Image
    let label: String
    let isSelected: Bool
    let action: () -> Void

    public init(systemImage: String, label: String, isSelected: Bool = false, action: @escaping () -> Void) {
        self.id = label
        self.image = Image(systemName: systemImage)
        self.label = label
        self.isSelected = isSelected
        self.action = action
    }

    public static func search(_ action: @escaping () -> Void) -> SylviaBarItem {
        SylviaBarItem(systemImage: ControlSymbol.search.systemName, label: LabelKey.navSearch.localized, action: action)
    }

    public static func settings(_ action: @escaping () -> Void) -> SylviaBarItem {
        SylviaBarItem(systemImage: ControlSymbol.settings.systemName, label: LabelKey.navSettings.localized, action: action)
    }
}

/// The navigation bar (Section 4.4.7): opaque `ground`, plain icon buttons, no system glass. An
/// optional back button (chevron and the previous screen's name in Pine), an optional title in the
/// Micro role, trailing icon buttons. Like the tab bar it stops growing at xxxLarge; its buttons
/// show the large content viewer.
public struct SylviaNavigationBar: View {
    let title: String?
    let backTitle: String?
    let onBack: (() -> Void)?
    let trailing: [SylviaBarItem]
    @State private var backGate = LiftActivationGate()

    public init(title: String? = nil, backTitle: String? = nil, onBack: (() -> Void)? = nil,
                trailing: [SylviaBarItem] = []) {
        self.title = title
        self.backTitle = backTitle
        self.onBack = onBack
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: Spacing.xxs) {
            if let onBack {
                Button {
                    backGate.run(onBack)
                } label: {
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: ControlSymbol.back.systemName).sylviaFont(.body, weight: ComponentMetrics.labelWeight)
                        if let backTitle {
                            Text(backTitle).sylviaFont(.body)
                        }
                    }
                    .foregroundStyle(ColorToken.pine.color)
                    .frame(minWidth: ComponentMetrics.minimumTarget, minHeight: ComponentMetrics.minimumTarget,
                           alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(backTitle ?? LabelKey.navBack.localized))
                .accessibilityShowsLargeContentViewer {
                    Label { Text(backTitle ?? LabelKey.navBack.localized) } icon: { Image(systemName: ControlSymbol.back.systemName) }
                }
                .sylviaLiftActivation(gate: backGate, action: onBack)
            }
            if let title {
                Text(title)
                    .sylviaFont(.micro)
                    .foregroundStyle(ColorToken.muted.color)
                    .frame(maxWidth: .infinity, alignment: onBack == nil ? .leading : .center)
                    .accessibilityAddTraits(.isHeader)
            } else {
                Spacer(minLength: 0)
            }
            ForEach(trailing) { item in
                SylviaIconButton(image: item.image, label: item.label, isSelected: item.isSelected, action: item.action)
            }
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, ComponentMetrics.barVerticalPadding)
        .dynamicTypeSize(...DynamicTypeSize.sylviaBarMaximum)
        .background(ColorToken.ground.color.ignoresSafeArea(edges: .top))
        .accessibilityElement(children: .contain)
    }
}
