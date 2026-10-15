import SwiftUI
import SylviaDesign
import UIKit

/// The catalog's display switches (appearance, text size, Increase Contrast, Bold Text). They are
/// applied as trait overrides on the window, the same traits the system settings change, so every
/// token, type role and component resolves exactly as it would under the system setting. "System"
/// removes the override. The device review (Docs/Stage0/device-checklists/G06-Design.md) uses the
/// real system settings; these switches are for quick comparison.
@MainActor
@Observable
final class DisplaySettings {
    enum AppearanceChoice: String, CaseIterable, Sendable, Hashable {
        case system, light, dark

        var label: String {
            switch self {
            case .system: "System"
            case .light: "Light"
            case .dark: "Dark"
            }
        }
    }

    enum TextSizeChoice: String, CaseIterable, Sendable, Hashable {
        case system
        case large
        case xxxLarge
        case ax1
        case ax3
        case ax5

        var label: String {
            switch self {
            case .system: "System"
            case .large: "Default"
            case .xxxLarge: "XXXL"
            case .ax1: "AX1"
            case .ax3: "AX3"
            case .ax5: "AX5"
            }
        }

        var category: UIContentSizeCategory? {
            switch self {
            case .system: nil
            case .large: .large
            case .xxxLarge: .extraExtraExtraLarge
            case .ax1: .accessibilityMedium
            case .ax3: .accessibilityExtraLarge
            case .ax5: .accessibilityExtraExtraExtraLarge
            }
        }
    }

    var appearance: AppearanceChoice
    var textSize: TextSizeChoice = .system
    var increaseContrast: Bool
    var boldText: Bool
    /// Installs the layout audit on every screen and reports truncated texts (T51 proxy).
    var layoutAudit: Bool

    init(arguments: LaunchArguments) {
        appearance = arguments.appearance
        increaseContrast = arguments.increaseContrast
        boldText = arguments.boldText
        layoutAudit = arguments.layoutAudit
    }

    /// Applies the switches to `window` as trait overrides.
    func apply(to window: UIWindow) {
        switch appearance {
        case .system: window.traitOverrides.remove(UITraitUserInterfaceStyle.self)
        case .light: window.traitOverrides.userInterfaceStyle = .light
        case .dark: window.traitOverrides.userInterfaceStyle = .dark
        }
        if let category = textSize.category {
            window.traitOverrides.preferredContentSizeCategory = category
        } else {
            window.traitOverrides.remove(UITraitPreferredContentSizeCategory.self)
        }
        if increaseContrast {
            window.traitOverrides.accessibilityContrast = .high
        } else {
            window.traitOverrides.remove(UITraitAccessibilityContrast.self)
        }
        if boldText {
            window.traitOverrides.legibilityWeight = .bold
        } else {
            window.traitOverrides.remove(UITraitLegibilityWeight.self)
        }
    }

    /// A summary of the switches for the catalog index ("Dark · AX5 · Increase Contrast").
    var summary: String {
        var parts = [appearance.label, textSize.label]
        if increaseContrast { parts.append("Increase Contrast") }
        if boldText { parts.append("Bold Text") }
        return Microcopy.joined(parts)
    }
}

/// Applies the display switches to the hosting window whenever they change.
struct WindowTraits: ViewModifier {
    let display: DisplaySettings

    func body(content: Content) -> some View {
        content.background {
            WindowFinder { window in display.apply(to: window) }
                .id(stateKey)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    /// Changes whenever a switch changes, so the finder re-applies the window.traitOverrides.
    private var stateKey: String {
        "\(display.appearance.rawValue)-\(display.textSize.rawValue)-\(display.increaseContrast)-\(display.boldText)"
    }
}

/// Calls `onWindow` with the window that hosts this view once it is in one.
private struct WindowFinder: UIViewRepresentable {
    let onWindow: @MainActor (UIWindow) -> Void

    func makeUIView(context: Context) -> FinderView {
        let view = FinderView()
        view.onWindow = onWindow
        return view
    }

    func updateUIView(_ view: FinderView, context: Context) {
        view.onWindow = onWindow
        if let window = view.window { onWindow(window) }
    }

    final class FinderView: UIView {
        var onWindow: (@MainActor (UIWindow) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { onWindow?(window) }
        }
    }
}
