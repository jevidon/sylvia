import SwiftUI
import SylviaDesign

/// The Sylvia design catalog (G0.6 part 3): the component gallery used for the device review, the
/// token, type, marker and symbol screens, and the interaction prototype. Static fixture data from
/// public-domain works; nothing is sent anywhere.
@main
struct DesignCatalogApp: App {
    @State private var display = DisplaySettings(arguments: LaunchArguments.current)
    private let launch = LaunchArguments.current

    init() {
        // Literata is registered once per process from the package bundle (ADR-0013 Section 4).
        _ = FontRegistration.registerLiterata()
    }

    var body: some Scene {
        WindowGroup {
            CatalogRoot(launch: launch)
                .environment(display)
                .modifier(WindowTraits(display: display))
        }
    }
}

/// Options read from the launch arguments (`-SylviaScreen library` and so on), so tests and
/// reviewers can open a screen and a display setting directly.
struct LaunchArguments: Sendable {
    /// A prototype screen to open at launch (``PrototypeScreen`` raw value).
    var screen: PrototypeScreen?
    /// A catalog page to open at launch (`colors`, `type`, `markers`, `symbols`, `allComponents`,
    /// `component.<sample>`).
    var page: String?
    /// "light" or "dark": overrides the system appearance.
    var appearance: DisplaySettings.AppearanceChoice
    var increaseContrast: Bool
    var boldText: Bool
    var layoutAudit: Bool
    /// Seconds the simulated durable write takes (default 1.5).
    var writeSeconds: Double?

    static let current: LaunchArguments = {
        let defaults = UserDefaults.standard
        return LaunchArguments(
            screen: defaults.string(forKey: "SylviaScreen").flatMap(PrototypeScreen.init(rawValue:)),
            page: defaults.string(forKey: "SylviaPage"),
            appearance: defaults.string(forKey: "SylviaAppearance").flatMap(DisplaySettings.AppearanceChoice.init(rawValue:)) ?? .system,
            increaseContrast: defaults.bool(forKey: "SylviaIncreaseContrast"),
            boldText: defaults.bool(forKey: "SylviaBoldText"),
            layoutAudit: defaults.bool(forKey: "SylviaLayoutAudit"),
            writeSeconds: defaults.object(forKey: "SylviaWriteSeconds") == nil ? nil : defaults.double(forKey: "SylviaWriteSeconds")
        )
    }()
}
