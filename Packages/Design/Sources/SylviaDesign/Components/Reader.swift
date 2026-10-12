import SwiftUI

/// Selection menu actions (Section 4.4.7).
public enum SelectionAction: String, CaseIterable, Sendable, Identifiable {
    case highlight
    case note
    case lookUp
    case ask

    public var id: String { rawValue }

    public var labelKey: LabelKey {
        switch self {
        case .highlight: .actionHighlight
        case .note: .actionNote
        case .lookUp: .actionLookUp
        case .ask: .actionAsk
        }
    }
}

/// The selection menu (Section 4.4.7): an ink pill over the selection with Highlight (with the
/// Ochre quotation glyph), Note, Look up and Ask. Its contents use the opposite appearance's
/// tokens (ink of the other appearance as text, Ochre of the other appearance as the glyph), which
/// keeps them legible on the ink fill in Paper and in Night. No shadow: only sheets and the
/// mini-player cast one. A pill (radius full) in one row; at large text sizes the actions wrap to
/// two rows on a card-radius block instead of running off.
public struct SelectionMenu: View {
    let onAction: (SelectionAction) -> Void
    @Environment(\.colorScheme) private var colorScheme

    public init(onAction: @escaping (SelectionAction) -> Void) {
        self.onAction = onAction
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                ForEach(Array(SelectionAction.allCases.enumerated()), id: \.element) { index, action in
                    if index > 0 { divider() }
                    item(action)
                }
            }
            .fixedSize()
            .environment(\.colorScheme, colorScheme == .dark ? .light : .dark)
            .background { fill(Capsule()) }
            // Two rows at large text sizes: a pill would cut the corner items, so the block keeps
            // the card radius.
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow { item(.highlight); item(.note) }
                GridRow { item(.lookUp); item(.ask) }
            }
            .fixedSize(horizontal: true, vertical: false)
            .environment(\.colorScheme, colorScheme == .dark ? .light : .dark)
            .background { fill(RoundedRectangle(cornerRadius: Radius.card.value, style: .continuous)) }
            // One action per row when two do not fit side by side (accessibility sizes on a phone):
            // the two-row grid broke "Highlight" inside the word at AX5.
            VStack(spacing: 0) {
                ForEach(SelectionAction.allCases, id: \.self) { item($0) }
            }
            .environment(\.colorScheme, colorScheme == .dark ? .light : .dark)
            .background { fill(RoundedRectangle(cornerRadius: Radius.card.value, style: .continuous)) }
        }
        .accessibilityElement(children: .contain)
    }

    /// The ink fill, resolved in the surrounding appearance (the contents use the opposite one).
    private func fill(_ shape: some Shape) -> some View {
        shape.fill(ColorToken.ink.color)
            .environment(\.colorScheme, colorScheme)
            .sylviaAuditRegion("menu.fill")
    }

    private func divider() -> some View {
        Rectangle()
            .fill(ColorToken.hairline.color)
            .frame(width: Hairline.width)
            .padding(.vertical, Spacing.xs)
    }

    private func item(_ action: SelectionAction) -> some View {
        Button { onAction(action) } label: {
            HStack(alignment: .firstTextBaseline, spacing: ComponentMetrics.glyphGap) {
                if action == .highlight {
                    // The Quote marker's glyph: the Literata quotation mark in the quote color (Ochre).
                    MarkerGlyph(.quote, role: .body)
                        .accessibilityHidden(true)
                        .sylviaAuditRegion("menu.highlightGlyph")
                }
                Text(action.labelKey.localized)
                    .sylviaFont(.body, weight: ComponentMetrics.labelWeight)
                    .foregroundStyle(ColorToken.ink.color)
            }
            .padding(.horizontal, Spacing.m)
            .frame(maxWidth: .infinity, minHeight: ComponentMetrics.minimumTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(action.labelKey.localized))
    }
}

/// Reader chrome (Section 4.4.7): minimal. Top: back, the book title in Micro, "Aa" (reader
/// settings), bookmark, search. Footer: the progress rule with chapter and percent. No page numbers
/// unless the publication maps them. Opaque `ground`; like the other bars the top row stops
/// growing at xxxLarge and its buttons show the large content viewer.
public struct ReaderChrome<Content: View>: View {
    let title: String
    let isBookmarked: Bool
    let progress: ProgressRule
    let onBack: () -> Void
    let onSettings: () -> Void
    let onBookmark: () -> Void
    let onSearch: () -> Void
    let content: Content
    @State private var settingsGate = LiftActivationGate()

    public init(title: String, isBookmarked: Bool, progress: ProgressRule, onBack: @escaping () -> Void,
                onSettings: @escaping () -> Void, onBookmark: @escaping () -> Void,
                onSearch: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.isBookmarked = isBookmarked
        self.progress = progress
        self.onBack = onBack
        self.onSettings = onSettings
        self.onBookmark = onBookmark
        self.onSearch = onSearch
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            progress
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.s)
        }
        .background(ColorToken.ground.color)
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            SylviaIconButton(systemImage: ControlSymbol.back.systemName, label: LabelKey.navBack.localized, action: onBack)
            Text(title)
                .sylviaFont(.micro)
                .foregroundStyle(ColorToken.muted.color)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            Button {
                settingsGate.run(onSettings)
            } label: {
                Text(verbatim: GlyphText.readerSettings)
                    .sylviaFont(.heading)
                    .foregroundStyle(ColorToken.ink.color)
                    .frame(minWidth: ComponentMetrics.minimumTarget, minHeight: ComponentMetrics.minimumTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(LabelKey.readerSettings.localized))
            .accessibilityShowsLargeContentViewer {
                Label { Text(LabelKey.readerSettings.localized) } icon: { Image(systemName: ControlSymbol.readerSettings.systemName) }
            }
            .sylviaLiftActivation(gate: settingsGate, action: onSettings)
            SylviaIconButton(systemImage: (isBookmarked ? ControlSymbol.bookmarkSet : ControlSymbol.bookmark).systemName,
                             label: LabelKey.readerBookmark.localized, isSelected: isBookmarked, action: onBookmark)
            SylviaIconButton(systemImage: ControlSymbol.search.systemName, label: LabelKey.readerSearch.localized, action: onSearch)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, ComponentMetrics.barVerticalPadding)
        .dynamicTypeSize(...DynamicTypeSize.sylviaBarMaximum)
        .background(ColorToken.ground.color)
        .accessibilityElement(children: .contain)
    }
}

/// One line of an impact report: a check-marked statement of what is freed or kept.
public struct ImpactLine: Sendable, Hashable, Identifiable {
    public let id: Int
    public let text: String

    public init(_ id: Int, _ text: String) {
        self.id = id
        self.text = text
    }
}

/// The impact report (Section 4.4.7, 17.2), shown before removal: check-marked lines for what is
/// freed and what is kept, an attention row for anything pending (with its reason and next step),
/// then the safe choice as the primary button. Other choices follow in order: an optional
/// secondary, then the destructive action last, never beside the primary.
public struct ImpactReport: View {
    public struct Pending: Sendable, Hashable {
        public let reason: String
        public let nextStep: String

        public init(reason: String, nextStep: String) {
            self.reason = reason
            self.nextStep = nextStep
        }
    }

    public struct Choice {
        let title: String
        let action: () -> Void

        public init(_ title: String, action: @escaping () -> Void) {
            self.title = title
            self.action = action
        }
    }

    let title: String
    let lines: [ImpactLine]
    let pending: Pending?
    let safeChoice: Choice
    let secondary: Choice?
    let destructive: Choice?

    public init(title: String, lines: [ImpactLine], pending: Pending?, safeChoice: Choice,
                secondary: Choice? = nil, destructive: Choice? = nil) {
        self.title = title
        self.lines = lines
        self.pending = pending
        self.safeChoice = safeChoice
        self.secondary = secondary
        self.destructive = destructive
    }

    public var body: some View {
        SylviaSheetContainer(title: title) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                ForEach(lines) { line in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                        StatusGlyph.check.image
                            .sylviaFont(.body, weight: ComponentMetrics.labelWeight)
                            .foregroundStyle(ColorToken.pine.color)
                            .accessibilityHidden(true)
                        Text(line.text)
                            .sylviaFont(.body)
                            .foregroundStyle(ColorToken.ink.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let pending {
                    AttentionRow(reason: pending.reason, nextStep: pending.nextStep)
                }
            }
            VStack(spacing: Spacing.s) {
                Button(safeChoice.title, action: safeChoice.action)
                    .buttonStyle(.sylvia(.primary))
                if let secondary {
                    Button(secondary.title, action: secondary.action)
                        .buttonStyle(.sylvia(.secondary))
                }
                if let destructive {
                    Button(destructive.title, action: destructive.action)
                        .buttonStyle(.sylvia(.destructive))
                        .padding(.top, secondary == nil ? Spacing.xl : 0)
                }
            }
        }
    }
}
