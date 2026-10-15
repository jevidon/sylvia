import SwiftUI
import SylviaDesign

/// The screen gutter: 20 pt on iPhone (compact width), 32 pt on iPad in regular width (Section 4.4.4).
struct ScreenGutter: ViewModifier {
    var isOn = true
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content.padding(.horizontal, isOn ? (sizeClass == .regular ? Spacing.gutterPad : Spacing.gutterPhone) : 0)
    }
}

extension View {
    func screenGutter(_ isOn: Bool = true) -> some View { modifier(ScreenGutter(isOn: isOn)) }

    /// A pushed screen: Sylvia's own navigation bar replaces the system bar (Section 4.4.7).
    func sylviaScreenChrome() -> some View {
        toolbar(.hidden, for: .navigationBar)
            .background(ColorToken.ground.color.ignoresSafeArea())
    }

    /// An opaque `ground` strip behind the status bar for screens whose title scrolls with the
    /// content (the area roots and onboarding), so scrolled text never runs under the status bar
    /// (Section 4.4.2: Sylvia's chrome is opaque).
    func statusBarGround() -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            Color.clear
                .frame(height: 0)
                .background(ColorToken.ground.color.ignoresSafeArea(edges: .top))
                .accessibilityHidden(true)
        }
    }
}

/// A scrolling page under a Sylvia navigation bar with a back button.
struct SubPage<Content: View>: View {
    let name: String
    let title: String?
    let backTitle: String
    let trailing: [SylviaBarItem]
    let gutter: Bool
    let content: Content
    @Environment(\.dismiss) private var dismiss

    /// `gutter: false` lays the content edge to edge (component samples bring their own gutter).
    init(_ name: String, title: String?, backTitle: String, trailing: [SylviaBarItem] = [], gutter: Bool = true,
         @ViewBuilder content: () -> Content) {
        self.name = name
        self.title = title
        self.backTitle = backTitle
        self.trailing = trailing
        self.gutter = gutter
        self.content = content()
    }

    var body: some View {
        AuditedScreen(name) {
            VStack(spacing: 0) {
                SylviaNavigationBar(title: title, backTitle: backTitle, onBack: { dismiss() }, trailing: trailing)
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.m) { content }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .screenGutter(gutter)
                        .padding(.vertical, Spacing.m)
                }
            }
            .sylviaScreenChrome()
        }
    }
}

/// A row of a cover and text: side by side, top-aligned; stacked at accessibility text sizes so
/// the text has the full width and the row never grows wider than the screen.
struct AdaptiveRow<Content: View>: View {
    let spacing: CGFloat
    let content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(spacing: CGFloat = Spacing.s, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: .top, spacing: spacing))
        layout { content }
    }
}

/// The content of a presented sheet: scrolls (at accessibility sizes a capture sheet is taller
/// than the screen) and starts at the top, so the package's sheet container, which draws its own
/// 22 pt top corners and grabber, lines up with the presented sheet's edge.
struct SheetPage<Content: View>: View {
    let name: String
    let content: Content

    init(_ name: String, @ViewBuilder content: () -> Content) {
        self.name = name
        self.content = content()
    }

    var body: some View {
        AuditedScreen(name) {
            ScrollView {
                content.frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(ColorToken.surface.color.ignoresSafeArea())
        }
    }
}

/// A list row inside a card: a title, an optional caption and a disclosure chevron; the whole row
/// is one button.
struct CardRow: View {
    let title: String
    let caption: String?
    let action: () -> Void

    init(_ title: String, caption: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.caption = caption
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .sylviaFont(.body)
                        .foregroundStyle(ColorToken.ink.color)
                        .fixedSize(horizontal: false, vertical: true)
                    if let caption {
                        Text(caption)
                            .sylviaFont(.caption)
                            .foregroundStyle(ColorToken.muted.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: ControlSymbol.disclosure.systemName)
                    .sylviaFont(.body)
                    .foregroundStyle(ColorToken.muted.color)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, ComponentMetrics.cardPadding)
            .padding(.vertical, Spacing.s)
            .frame(minHeight: ComponentMetrics.minimumTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Body text in ink or muted, wrapping.
struct BodyText: View {
    let text: String
    let role: TypeRole
    let muted: Bool

    init(_ text: String, role: TypeRole = .body, muted: Bool = false) {
        self.text = text
        self.role = role
        self.muted = muted
    }

    var body: some View {
        Text(text)
            .sylviaFont(role)
            .foregroundStyle((muted ? ColorToken.muted : ColorToken.ink).color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
