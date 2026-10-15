import SwiftUI
import SylviaDesign
import SylviaDesignGallery

/// The app root: the catalog, or the prototype opened directly at a screen from the launch
/// arguments (`-SylviaScreen inbox`).
struct CatalogRoot: View {
    let launch: LaunchArguments
    @State private var prototype: PrototypeLaunch?
    @State private var path: [CatalogPage]

    init(launch: LaunchArguments) {
        self.launch = launch
        _path = State(initialValue: launch.page.flatMap(CatalogPage.init(launchName:)).map { [$0] } ?? [])
    }

    var body: some View {
        if let screen = launch.screen {
            PrototypeRoot(start: screen, writeSeconds: launch.writeSeconds, onLeave: nil)
        } else {
            NavigationStack(path: $path) {
                CatalogIndex(openPrototype: { prototype = PrototypeLaunch(screen: $0) })
                    .navigationDestination(for: CatalogPage.self) { page in page.view }
            }
            .fullScreenCover(item: $prototype) { launchItem in
                PrototypeRoot(start: launchItem.screen, writeSeconds: launch.writeSeconds) { prototype = nil }
            }
        }
    }
}

struct PrototypeLaunch: Identifiable {
    let screen: PrototypeScreen
    var id: String { screen.rawValue }
}

/// Pages of the catalog.
enum CatalogPage: Hashable {
    case colors, type, markers, symbols, allComponents, component(String)

    /// From a launch argument: "colors", "allComponents", "component.textField" and so on.
    init?(launchName: String) {
        switch launchName {
        case "colors": self = .colors
        case "type": self = .type
        case "markers": self = .markers
        case "symbols": self = .symbols
        case "allComponents": self = .allComponents
        default:
            let prefix = "component."
            guard launchName.hasPrefix(prefix) else { return nil }
            let name = String(launchName.dropFirst(prefix.count))
            guard Gallery.names.contains(name) else { return nil }
            self = .component(name)
        }
    }

    @MainActor @ViewBuilder var view: some View {
        switch self {
        case .colors: ColorsPage()
        case .type: TypePage()
        case .markers: MarkersPage()
        case .symbols: SymbolsPage()
        case .allComponents: AllComponentsPage()
        case .component(let name): ComponentPage(name: name)
        }
    }
}

struct CatalogIndex: View {
    let openPrototype: (PrototypeScreen) -> Void
    @Environment(DisplaySettings.self) private var display

    var body: some View {
        AuditedScreen("catalog") {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    AreaTitle("Design catalog")
                    BodyText("Marginalia from the SylviaDesign package: tokens, type, markers, every component in every state, and an interaction prototype with static public-domain fixtures. Nothing here is sent anywhere.",
                             role: .callout, muted: true)
                    DisplayControls()
                    SectionLabel("Design language")
                    SylviaCard(padded: false) {
                        NavigationLink(value: CatalogPage.colors) { pageRow("Colors", caption: "Every token with its value in the current appearance") }
                        SylviaRule()
                        NavigationLink(value: CatalogPage.type) { pageRow("Type", caption: "The eight roles at the current text size") }
                        SylviaRule()
                        NavigationLink(value: CatalogPage.markers) { pageRow("Markers and status", caption: "Seven markers, status pills, availability badges") }
                        SylviaRule()
                        NavigationLink(value: CatalogPage.symbols) { pageRow("Symbols", caption: "Custom symbols beside SF Symbols at four weights") }
                    }
                    .buttonStyle(.plain)
                    SectionLabel("Components")
                    SylviaCard(padded: false) {
                        NavigationLink(value: CatalogPage.allComponents) { pageRow("All components", caption: "\(Gallery.names.count) samples on one page") }
                        ForEach(Gallery.names, id: \.self) { name in
                            SylviaRule()
                            NavigationLink(value: CatalogPage.component(name)) { pageRow(name, caption: nil) }
                        }
                    }
                    .buttonStyle(.plain)
                    SectionLabel("Interaction prototype")
                    Button("Open the prototype") { openPrototype(.onboarding) }
                        .buttonStyle(.sylvia(.primary))
                    SylviaCard(padded: false) {
                        ForEach(Array(PrototypeScreen.allCases.enumerated()), id: \.element) { index, screen in
                            if index > 0 { SylviaRule() }
                            CardRow(screen.title, caption: screen.rawValue) { openPrototype(screen) }
                        }
                    }
                }
                .screenGutter()
                .padding(.vertical, Spacing.m)
            }
            .background(ColorToken.ground.color.ignoresSafeArea())
            .statusBarGround()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func pageRow(_ title: String, caption: String?) -> some View {
        HStack(spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title).sylviaFont(.body).foregroundStyle(ColorToken.ink.color)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption {
                    Text(caption).sylviaFont(.caption).foregroundStyle(ColorToken.muted.color)
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
}

/// Appearance, text size, Increase Contrast, Bold Text and the layout audit.
struct DisplayControls: View {
    @Environment(DisplaySettings.self) private var display

    var body: some View {
        @Bindable var display = display
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionLabel("Display")
            BodyText(display.summary, role: .caption, muted: true)
                .accessibilityIdentifier("display.summary")
            BodyText("Appearance", role: .callout)
            FilterChips(DisplaySettings.AppearanceChoice.allCases.map { FilterChip($0, label: $0.label) },
                        selection: $display.appearance)
            BodyText("Text size", role: .callout)
            FilterChips(DisplaySettings.TextSizeChoice.allCases.map { FilterChip($0, label: $0.label) },
                        selection: $display.textSize)
            SylviaCard {
                toggle("Increase Contrast", isOn: $display.increaseContrast)
                toggle("Bold Text", isOn: $display.boldText)
                toggle("Layout audit", isOn: $display.layoutAudit)
            }
        }
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).sylviaFont(.body).foregroundStyle(ColorToken.ink.color)
        }
        .tint(ColorToken.pine.color)
        .frame(minHeight: ComponentMetrics.minimumTarget)
    }
}
