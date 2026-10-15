import SwiftUI
import SylviaDesign
import SylviaDesignGallery
import UIKit

/// The appearance the environment resolves colors in (color scheme plus Increase Contrast).
struct CurrentAppearance {
    let colorScheme: ColorScheme
    let contrast: ColorSchemeContrast

    var appearance: Appearance {
        switch (colorScheme == .dark, contrast == .increased) {
        case (false, false): .light
        case (true, false): .dark
        case (false, true): .lightIncreasedContrast
        case (true, true): .darkIncreasedContrast
        }
    }

    var label: String {
        Microcopy.joined([colorScheme == .dark ? "Dark" : "Light", contrast == .increased ? "Increase Contrast" : ""])
    }
}

/// Every color token, its value read back from the compiled asset catalog for the current
/// appearance (device checklist steps 1-3), and every contrast pair measured from those values.
struct ColorsPage: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let current = CurrentAppearance(colorScheme: colorScheme, contrast: contrast)
        let appearance = current.appearance
        let results = ContrastReport.evaluate(appearances: [appearance]) { token, a in token.catalogValue(in: a) }
        let failing = results.filter { !$0.passes }.count
        SubPage("colors", title: "Colors", backTitle: "Catalog") {
            BodyText("Values read from the compiled asset catalog in \(current.label).", role: .callout, muted: true)
                .accessibilityIdentifier("colors.appearance")
            SylviaCard(padded: false) {
                ForEach(Array(ColorToken.allCases.enumerated()), id: \.element) { index, token in
                    if index > 0 { SylviaRule() }
                    HStack(spacing: Spacing.s) {
                        RoundedRectangle(cornerRadius: CGFloat(Radius.block.points ?? 0), style: .continuous)
                            .fill(token.color)
                            .frame(width: ComponentMetrics.minimumTarget, height: ComponentMetrics.minimumTarget)
                            .overlay {
                                RoundedRectangle(cornerRadius: CGFloat(Radius.block.points ?? 0), style: .continuous)
                                    .strokeBorder(ColorToken.hairline.color, lineWidth: Hairline.width)
                            }
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(token.reference).sylviaFont(.body).foregroundStyle(ColorToken.ink.color)
                            Text(token.catalogValue(in: appearance).description)
                                .sylviaFont(.caption, monospaced: true)
                                .foregroundStyle(ColorToken.muted.color)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, ComponentMetrics.cardPadding)
                    .padding(.vertical, Spacing.xs)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("color.\(token.rawValue)")
                }
            }
            SectionLabel("Contrast")
            BodyText("\(results.count) pairs in \(current.label); \(failing) below the threshold.", role: .callout)
                .accessibilityIdentifier("contrast.summary")
            SylviaCard(padded: false) {
                ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                    if index > 0 { SylviaRule() }
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                        Text("\(result.pair.foreground.reference) on \(result.pair.background.reference)")
                            .sylviaFont(.caption)
                            .foregroundStyle(ColorToken.ink.color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(result.ratio.formatted(.number.precision(.fractionLength(2))) + (result.passes ? "" : " below"))
                            .sylviaFont(.caption, monospaced: true)
                            .foregroundStyle((result.passes ? ColorToken.muted : ColorToken.markerAttentionText).color)
                    }
                    .padding(.horizontal, ComponentMetrics.cardPadding)
                    .padding(.vertical, Spacing.xs)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// The eight type roles at the current text size, with the resolved size and line height
/// (device checklist steps 4, 5 and 9).
struct TypePage: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight

    var body: some View {
        let category = UIContentSizeCategory(dynamicTypeSize)
        SubPage("type", title: "Type", backTitle: "Catalog") {
            BodyText("Text size \(category.rawValue.replacingOccurrences(of: "UICTContentSizeCategory", with: "")); Bold Text \(legibilityWeight == .bold ? "on" : "off").",
                     role: .callout, muted: true)
                .accessibilityIdentifier("type.size")
            ForEach(TypeRole.allCases, id: \.self) { role in
                let resolved = role.resolved(contentSize: category, boldText: legibilityWeight == .bold)
                SylviaCard {
                    Text(role.rawValue.capitalized + " · " + role.spec.usage)
                        .sylviaFont(.caption)
                        .foregroundStyle(ColorToken.muted.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(sample(for: role))
                        .sylviaFont(role)
                        .foregroundStyle(ColorToken.ink.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(resolved.face.rawValue) \(resolved.weight) · \(format(resolved.pointSize)) / \(format(resolved.lineHeight)) pt")
                        .sylviaFont(.caption, monospaced: true)
                        .foregroundStyle(ColorToken.muted.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("type.\(role.rawValue).size")
                }
            }
        }
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func sample(for role: TypeRole) -> String {
        switch role {
        case .display, .title: "Middlemarch"
        case .heading: "A Study of Provincial Life"
        case .reading: SampleText.reading
        case .body: "Eliot's case for partial sympathy: total perception would destroy us."
        case .callout: "Pair once. Pull books over your network or a cable."
        case .caption: "George Eliot · 2nd read · 14:02"
        case .micro: "Quote · Middlemarch · Bk II, ch. 20"
        }
    }
}

/// The seven markers, an unrecognized capture kind, the status pills and the availability badges.
struct MarkersPage: View {
    var body: some View {
        SubPage("markers", title: "Markers and status", backTitle: "Catalog") {
            SectionLabel("Markers")
            SylviaCard {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    ForEach(Gallery.markerRows, id: \.0) { _, config in MarkerRow(config) }
                }
            }
            AttentionRow(reason: Fixtures.ExampleCopy.pendingExcerptReason,
                         nextStep: Fixtures.ExampleCopy.pendingExcerptNextStep)
            SectionLabel("Status pills")
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(Gallery.pillStates, id: \.0) { _, config in StatusPill(config) }
            }
            SectionLabel("Availability")
            VStack(alignment: .leading, spacing: Spacing.xs) {
                AvailabilityBadge(.onThisDevice)
                AvailabilityBadge(.notOnThisDevice(source: "Studio"))
                AvailabilityBadge(.recordOnly)
            }
        }
    }
}

/// The custom symbols beside the SF Symbols they sit with, at four weights (checklist step 7).
struct SymbolsPage: View {
    private let weights: [(String, Font.Weight)] = [("Ultralight", .ultraLight), ("Regular", .regular),
                                                    ("Semibold", .semibold), ("Black", .black)]

    var body: some View {
        SubPage("symbols", title: "Symbols", backTitle: "Catalog") {
            ForEach(weights, id: \.0) { name, weight in
                SylviaCard {
                    Text(name).sylviaFont(.caption).foregroundStyle(ColorToken.muted.color)
                    HStack(spacing: Spacing.m) {
                        CustomSymbol.prompt.image.accessibilityLabel(Text(CustomSymbol.prompt.accessibilityLabel))
                        Image(systemName: ControlSymbol.disclosure.systemName).accessibilityHidden(true)
                        CustomSymbol.capture.image.accessibilityLabel(Text(CustomSymbol.capture.accessibilityLabel))
                        MarkerGlyph(.audio)
                        MarkerGlyph(.note)
                    }
                    .sylviaFont(.heading)
                    .fontWeight(weight)
                    .foregroundStyle(ColorToken.ink.color)
                }
            }
        }
    }
}

/// Every gallery sample on one page.
struct AllComponentsPage: View {
    var body: some View {
        // Edge to edge: each sample brings the 20 pt gutter it has in the snapshot references.
        SubPage("components", title: "All components", backTitle: "Catalog", gutter: false) {
            ForEach(Gallery.names, id: \.self) { name in
                SectionLabel(name)
                    .padding(.horizontal, Spacing.gutterPhone)
                SampleView(sample: Gallery.sample(name))
            }
        }
    }
}

/// One gallery sample.
struct ComponentPage: View {
    let name: String

    var body: some View {
        SubPage("component.\(name)", title: name, backTitle: "Catalog", gutter: false) {
            SampleView(sample: Gallery.sample(name))
        }
    }
}

/// A sample framed as the snapshot tests frame it: its width (at most the screen's), its fixed
/// height if any, and its size class.
struct SampleView: View {
    let sample: Sample

    var body: some View {
        sample.content
            .environment(\.horizontalSizeClass, sample.sizeClass == .regular ? .regular : .compact)
            .frame(maxWidth: sample.width)
            .frame(height: sample.height)
            .clipShape(Rectangle())
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
    }
}
