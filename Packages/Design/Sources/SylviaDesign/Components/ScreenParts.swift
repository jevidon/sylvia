import SwiftUI

// Screen parts added for the design catalog's interaction prototype (G0.6 part 3; ADR-0013
// Section 11). The plan's Section 4.4.7 inventory does not name them, but every screen the boards
// draw needs them, and Section 4.4.9 keeps borders, fills and type out of screens. They are
// proposals for design review, built from the same tokens as the inventory.

/// A card (Section 4.4.4, 4.4.7): `surface`, a hairline border, radius 14. Content is clipped to the
/// card shape so edge-to-edge parts (rules, Inbox progress) follow the corners. Cards never nest.
public struct SylviaCard<Content: View>: View {
    let padded: Bool
    let content: Content

    /// `padded` adds the 12 pt card padding; rows that draw their own insets pass false.
    public init(padded: Bool = true, @ViewBuilder content: () -> Content) {
        self.padded = padded
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padded ? ComponentMetrics.cardPadding : 0)
            .background(ColorToken.surface.color)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card.value, style: .continuous))
            .sylviaBorder(.card)
            .accessibilityElement(children: .contain)
            .sylviaAuditRegion("card")
    }
}

/// A 1 pt hairline rule (Section 4.4.4: rules separate). Decorative; hidden from VoiceOver.
public struct SylviaRule: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(ColorToken.hairline.color)
            .frame(height: Hairline.width)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

/// A section eyebrow in the Micro role (Section 4.4.3: "Marker labels and section eyebrows only"):
/// muted, uppercase on screen, read in sentence case as a heading.
public struct SectionLabel: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .sylviaFont(.micro)
            .foregroundStyle(ColorToken.muted.color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The large title at the top of a primary area (Display role) with optional navigation bar items
/// beside it, as the Library, Thoughts and Inbox boards draw it.
public struct AreaTitle: View {
    let title: String
    let trailing: [SylviaBarItem]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(_ title: String, trailing: [SylviaBarItem] = []) {
        self.title = title
        self.trailing = trailing
    }

    public var body: some View {
        // At accessibility sizes the buttons sit above the title so the title keeps the full width.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Spacing.xxs))
        layout {
            if dynamicTypeSize.isAccessibilitySize { buttons }
            FittingText(title, role: .display)
                .foregroundStyle(ColorToken.ink.color)
                .accessibilityAddTraits(.isHeader)
            if !dynamicTypeSize.isAccessibilitySize { buttons }
        }
    }

    private var buttons: some View {
        HStack(spacing: 0) {
            ForEach(trailing) { item in
                SylviaIconButton(image: item.image, label: item.label, isSelected: item.isSelected, action: item.action)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.sylviaBarMaximum)
    }
}

/// One filter chip.
public struct FilterChip<ID: Hashable>: Identifiable {
    public let id: ID
    public let label: String

    public init(_ id: ID, label: String) {
        self.id = id
        self.label = label
    }
}

extension FilterChip: Sendable where ID: Sendable {}

/// Filter chips (Thoughts: All, Quotes, Notes, Audio, Generated, Words; Library status filters; Ask
/// context scope): one selected at a time. The selected chip is an ink capsule with `ground` text,
/// the others a hairline capsule with ink text, so selection reads without color. Each chip is a
/// button with the selected trait and a 44 pt target. Chips wrap onto further rows instead of
/// scrolling sideways, so no filter is ever hidden off screen (the boards scroll; see ADR-0013
/// Section 11).
public struct FilterChips<ID: Hashable>: View {
    let chips: [FilterChip<ID>]
    @Binding var selection: ID
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(_ chips: [FilterChip<ID>], selection: Binding<ID>) {
        self.chips = chips
        self._selection = selection
    }

    public var body: some View {
        FlowLayout(spacing: Spacing.xs) {
            ForEach(chips) { chip in
                let isSelected = chip.id == selection
                Button { selection = chip.id } label: {
                    Text(chip.label)
                        .sylviaFont(.callout)
                        .foregroundStyle((isSelected ? ColorToken.ground : ColorToken.ink).color)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Spacing.m)
                        .padding(.vertical, Spacing.xxs)
                        .frame(minHeight: ComponentMetrics.chipHeight)
                        // A label that wraps (accessibility sizes) sits on the card radius: a capsule
                        // would cut the corners of a two-line label (as the selection menu does).
                        .background {
                            (shape == .pill ? AnyShape(Capsule())
                                : AnyShape(RoundedRectangle(cornerRadius: shape.value, style: .continuous)))
                                .fill(isSelected ? ColorToken.ink.color : Color.clear)
                        }
                        .sylviaBorder(shape, color: isSelected ? .ink : .hairline)
                        .frame(minHeight: ComponentMetrics.minimumTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .sylviaAuditRegion("chip.\(isSelected ? "selected" : "plain")")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var shape: Radius { dynamicTypeSize.isAccessibilitySize ? .card : .pill }
}

/// Places subviews in rows, left to right, starting a new row when the next one does not fit.
struct FlowLayout: Layout {
    let spacing: CGFloat

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[(index: Int, size: CGSize)]] {
        var rows: [[(index: Int, size: CGSize)]] = [[]]
        var x: CGFloat = 0
        for (index, view) in subviews.enumerated() {
            var size = view.sizeThatFits(.unspecified)
            if size.width > width {
                size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            }
            if x > 0 && x + size.width > width {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append((index, size))
            x += size.width + spacing
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(subviews, width: width)
        let height = rows.map { $0.map(\.size.height).max() ?? 0 }.reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let widest = rows.map { row in row.map(\.size.width).reduce(0, +) + spacing * CGFloat(max(row.count - 1, 0)) }.max() ?? 0
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.minX
            let rowHeight = row.map(\.size.height).max() ?? 0
            for item in row {
                subviews[item.index].place(at: CGPoint(x: x, y: y + (rowHeight - item.size.height) / 2),
                                           proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += rowHeight + spacing
        }
    }
}

/// What an Inbox row offers after its status (Section 4.1, layout B): one trailing action, a
/// disclosure chevron (the whole row opens a detail view), or nothing.
public enum InboxRowTrailing {
    case none
    /// The whole row is a button that opens a detail view; a chevron shows it.
    case disclosure(action: () -> Void)
    /// One action button (Pause, Open or Resolve). `symbol` draws a glyph instead of the title,
    /// which is then the accessibility label.
    case action(title: String, symbol: ControlSymbol? = nil, action: () -> Void)
}

/// An Inbox row in the compact layout chosen on 6 October 2026 (Section 4.1, board "Inbox rows,
/// option B"): title and kind; a status pill with a one-line detail; one trailing action or a
/// disclosure chevron; transfer progress drawn as a rule along the row's bottom edge. At
/// accessibility text sizes the detail wraps and the trailing action moves below it (T51). The
/// detail never truncates at any size.
public struct InboxRow: View {
    let title: String
    let kind: String?
    let pill: StatusPill.Configuration
    let detail: String?
    let detailIsValue: Bool
    let progress: Double?
    let trailing: InboxRowTrailing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// `detailIsValue` sets the detail in Monospace (byte counts, as Section 4.4.3 asks).
    /// `progress` (0...1) draws the transfer rule along the bottom edge.
    public init(title: String, kind: String? = nil, pill: StatusPill.Configuration, detail: String? = nil,
                detailIsValue: Bool = false, progress: Double? = nil, trailing: InboxRowTrailing = .none) {
        self.title = title
        self.kind = kind
        self.pill = pill
        self.detail = detail
        self.detailIsValue = detailIsValue
        self.progress = progress
        self.trailing = trailing
    }

    public var body: some View {
        Group {
            if case .disclosure(let action) = trailing {
                Button(action: action) { content.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
        .overlay(alignment: .bottom) {
            if let progress {
                ProgressRule(fraction: progress)
                    .sylviaAuditRegion("inbox.progress")
            }
        }
        .accessibilityElement(children: .contain)
        .sylviaAuditRegion("inbox.row")
    }

    private var content: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Spacing.s))
        return layout {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                // A no-break space keeps the separator with the title when the kind wraps.
                Text(kind.map { title + "\u{00A0}" + Microcopy.separator.dropFirst() + $0 } ?? title)
                    .sylviaFont(.body, weight: ComponentMetrics.labelWeight)
                    .foregroundStyle(ColorToken.ink.color)
                    .fixedSize(horizontal: false, vertical: true)
                statusLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            trailingView
        }
        .padding(.horizontal, ComponentMetrics.cardPadding)
        .padding(.vertical, Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The pill and its detail on one line when both fit; otherwise the detail moves below the pill
    /// and wraps (it never truncates and never breaks inside a word to stay beside the pill).
    @ViewBuilder private var statusLine: some View {
        if let detail {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: Spacing.xs) {
                    StatusPill(pill).fixedSize()
                    detailText(detail).fixedSize()
                }
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    StatusPill(pill).fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
                    detailText(detail).fixedSize(horizontal: false, vertical: true)
                }
                // Take the row's full width, so the pill and the detail wrap at the column's
                // width and not at the width of their first line.
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            StatusPill(pill).fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
        }
    }

    private func detailText(_ text: String) -> some View {
        Text(text)
            .sylviaFont(.caption, monospaced: detailIsValue)
            .foregroundStyle(ColorToken.muted.color)
    }

    @ViewBuilder private var trailingView: some View {
        switch trailing {
        case .none:
            EmptyView()
        case .disclosure:
            Image(systemName: ControlSymbol.disclosure.systemName)
                .sylviaFont(.body)
                .foregroundStyle(ColorToken.muted.color)
                .accessibilityHidden(true)
        case .action(let title, let symbol, let action):
            Button(action: action) {
                if let symbol {
                    Image(systemName: symbol.systemName).accessibilityHidden(true)
                } else {
                    Text(title)
                }
            }
            .buttonStyle(.sylvia(.secondary, fillsWidth: false))
            .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
            .accessibilityLabel(Text(title))
            .sylviaAuditRegion("inbox.action")
        }
    }
}

/// A text field (search, a follow-up question): `surface` fill, hairline border, radius 10, an
/// optional leading glyph, the prompt in `muted`. The label is the accessibility label.
public struct SylviaTextField: View {
    let label: String
    let prompt: String
    @Binding var text: String
    let symbol: ControlSymbol?

    public init(_ label: String, text: Binding<String>, prompt: String, symbol: ControlSymbol? = nil) {
        self.label = label
        self.prompt = prompt
        self._text = text
        self.symbol = symbol
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            if let symbol {
                Image(systemName: symbol.systemName)
                    .sylviaFont(.body)
                    .foregroundStyle(ColorToken.muted.color)
                    .accessibilityHidden(true)
            }
            TextField(label, text: $text, prompt: Text(prompt).foregroundStyle(ColorToken.muted.color), axis: .vertical)
                .sylviaFont(.body)
                .foregroundStyle(ColorToken.ink.color)
                .accessibilityLabel(Text(label))
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: ComponentMetrics.minimumTarget)
        .sylviaFill(.surface, .control)
        .sylviaBorder(.control)
        .sylviaAuditRegion("field")
    }
}

/// A status banner: the glyph and phrase of a status on its tint, with an optional detail in ink and
/// an optional action (Section 4.4.6 "Capturing audio": "Moment saved · preserving audio", "Audio
/// excerpt saved", "Excerpt not preserved · Retry"). Text on the tint is only ink and the state's
/// own color (Section 4.4.2). With `action` and no `actionTitle` the whole banner is the button
/// (the phrase itself names the action, as "Retry" does); with both, the action is a separate
/// button in the state's color.
public struct StatusBanner: View {
    let configuration: StatusPill.Configuration
    let detail: String?
    let actionTitle: String?
    let action: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(_ configuration: StatusPill.Configuration, detail: String? = nil, actionTitle: String? = nil,
                action: (() -> Void)? = nil) {
        self.configuration = configuration
        self.detail = detail
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        Group {
            if let action, actionTitle == nil {
                Button(action: action) { content.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
        .sylviaFill(configuration.fill, .block)
        .accessibilityElement(children: .contain)
        .sylviaAuditRegion("banner")
    }

    private var content: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.s))
        return layout {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                configuration.glyph.image
                    .sylviaFont(.body, weight: ComponentMetrics.labelWeight)
                    .foregroundStyle(configuration.textColor.color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(configuration.text)
                        .sylviaFont(.body, weight: ComponentMetrics.labelWeight)
                        .foregroundStyle(configuration.textColor.color)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .sylviaFont(.callout)
                            .foregroundStyle(ColorToken.ink.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            if let action, let actionTitle {
                Button(action: action) {
                    Text(actionTitle)
                        .sylviaFont(.body, weight: ComponentMetrics.labelWeight)
                        .foregroundStyle(configuration.textColor.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: ComponentMetrics.minimumTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(ComponentMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// An action card (onboarding: "Import a book", "Connect a Mac", "Add a record"; settings rows): a
/// card-shaped button with a Pine glyph on a Pine-tint tile, a title, an explanation and a
/// disclosure chevron.
public struct ActionCard: View {
    let symbol: ControlSymbol?
    let title: String
    let detail: String?
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Without a `symbol` the card has no tile.
    public init(symbol: ControlSymbol?, title: String, detail: String? = nil, action: @escaping () -> Void) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
                : AnyLayout(HStackLayout(alignment: .center, spacing: Spacing.m))
            layout {
                if let symbol {
                    Image(systemName: symbol.systemName)
                        .sylviaFont(.heading)
                        .foregroundStyle(ColorToken.pine.color)
                        .padding(Spacing.xs)
                        .frame(minWidth: ComponentMetrics.actionTile, minHeight: ComponentMetrics.actionTile)
                        .sylviaFill(.pineTint, .control)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .sylviaFont(.body, weight: ComponentMetrics.labelWeight)
                        .foregroundStyle(ColorToken.ink.color)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .sylviaFont(.callout)
                            .foregroundStyle(ColorToken.muted.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: ControlSymbol.disclosure.systemName)
                        .sylviaFont(.body)
                        .foregroundStyle(ColorToken.muted.color)
                        .accessibilityHidden(true)
                }
            }
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sylviaFill(.surface, .card)
            .sylviaBorder(.card)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .sylviaAuditRegion("actionCard")
    }
}

/// One paragraph of reading text (Section 4.4.3 Reading role; 4.4.8): Literata at the reader's size,
/// an optional saved highlight drawn as the Ochre tint with an Ochre underline (the underline
/// survives grayscale), an optional live selection on the Pine tint, and an optional margin dot in
/// the quote color that marks a saved thought. The highlight and the dot are also spoken
/// ("Highlighted", "Saved thought here"), so neither is carried by color alone. Ranges are given as
/// substrings of `text`; a substring that does not occur is ignored.
public struct ReadingParagraph: View {
    let text: String
    let highlighted: String?
    let selected: String?
    let marksSavedThought: Bool
    let readingSize: ReadingSize

    public init(_ text: String, highlighted: String? = nil, selected: String? = nil, marksSavedThought: Bool = false,
                readingSize: ReadingSize = .default) {
        self.text = text
        self.highlighted = highlighted
        self.selected = selected
        self.marksSavedThought = marksSavedThought
        self.readingSize = readingSize
    }

    /// The attributed text: highlight and selection runs in the current appearance's tokens.
    var attributed: AttributedString {
        var string = AttributedString(text)
        if let highlighted, let range = string.range(of: highlighted) {
            string[range].backgroundColor = ColorToken.ochreTint.color
            string[range].underlineStyle = Text.LineStyle(pattern: .solid, color: ColorToken.ochre.color)
        }
        if let selected, let range = string.range(of: selected) {
            string[range].backgroundColor = ColorToken.pineTint.color
        }
        return string
    }

    /// True when the highlight substring occurs in the text.
    public var showsHighlight: Bool { highlighted.map { !$0.isEmpty && text.contains($0) } ?? false }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Text(attributed)
                .sylviaFont(.reading, readingSize: readingSize)
                .foregroundStyle(ColorToken.ink.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            // The margin keeps its width whether or not a dot is shown, so paragraphs line up.
            Circle()
                .fill(Marker.quote.textColor.color)
                .frame(width: ComponentMetrics.attentionDot, height: ComponentMetrics.attentionDot)
                .opacity(marksSavedThought ? 1 : 0)
                .accessibilityHidden(true)
                .sylviaAuditRegion(marksSavedThought ? "reading.marginDot" : "reading.margin")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text))
        .accessibilityValue(Text(accessibilityValue))
        .sylviaAuditRegion("reading.paragraph")
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if showsHighlight { parts.append(LabelKey.readerHighlighted.localized) }
        if marksSavedThought { parts.append(LabelKey.readerSavedThought.localized) }
        return Microcopy.joined(parts)
    }
}

/// The round play/pause control of the full player: a Pine disc with the glyph in `pine.on`,
/// `ComponentMetrics.playerPlayControl` across (never under 44 pt). Labelled "Play" or "Pause".
public struct PlayPauseButton: View {
    let isPlaying: Bool
    let diameter: CGFloat
    let action: () -> Void
    @State private var gate = LiftActivationGate()

    public init(isPlaying: Bool, diameter: CGFloat = ComponentMetrics.playerPlayControl, action: @escaping () -> Void) {
        self.isPlaying = isPlaying
        self.diameter = max(diameter, ComponentMetrics.minimumTarget)
        self.action = action
    }

    public var body: some View {
        Button {
            gate.run(action)
        } label: {
            Image(systemName: (isPlaying ? ControlSymbol.pause : ControlSymbol.play).systemName)
                .sylviaFont(.title)
                .foregroundStyle(ColorToken.pineOn.color)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(ColorToken.pine.color))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.sylviaBarMaximum)
        .accessibilityLabel(Text((isPlaying ? LabelKey.controlPause : LabelKey.controlPlay).localized))
        .accessibilityShowsLargeContentViewer {
            Label { Text((isPlaying ? LabelKey.controlPause : LabelKey.controlPlay).localized) } icon: {
                Image(systemName: (isPlaying ? ControlSymbol.pause : ControlSymbol.play).systemName)
            }
        }
        .sylviaLiftActivation(gate: gate, action: action)
        .sylviaAuditRegion("player.playPause")
    }
}
