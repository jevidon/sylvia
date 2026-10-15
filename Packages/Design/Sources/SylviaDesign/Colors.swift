import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension ColorToken {
    /// The token as a SwiftUI color from the package asset catalog. It follows the environment's
    /// color scheme and Increase Contrast setting.
    public var color: Color { Color(rawValue, bundle: .module) }

    #if canImport(UIKit)
    /// The token as a dynamic `UIColor` from the package asset catalog.
    public var uiColor: UIColor {
        guard let color = UIColor(named: rawValue, in: .module, compatibleWith: nil) else {
            preconditionFailure("color \(rawValue) missing from the SylviaDesign asset catalog")
        }
        return color
    }
    #elseif canImport(AppKit)
    /// The token as a dynamic `NSColor` from the package asset catalog.
    public var nsColor: NSColor {
        guard let color = NSColor(named: rawValue, bundle: .module) else {
            preconditionFailure("color \(rawValue) missing from the SylviaDesign asset catalog")
        }
        return color
    }
    #endif

    /// The asset catalog's value for `appearance`, read back as 8-bit sRGB. Used by the contrast
    /// tests to check what the catalog actually ships, not only the token definitions. Main actor:
    /// building trait collections with UIKit's mutable traits requires it.
    @MainActor
    public func catalogValue(in appearance: Appearance) -> SRGBColor {
        #if canImport(UIKit)
        let resolved = uiColor.resolvedColor(with: appearance.traitCollection)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            preconditionFailure("\(rawValue) is not an RGB color")
        }
        return SRGBColor.fromComponents(r, g, b, a)
        #elseif canImport(AppKit)
        // NSAppearance(named: .accessibilityHighContrastAqua) cannot be constructed directly (it
        // returns plain Aqua), so the high-contrast variants are resolved the way SwiftUI views
        // resolve them.
        return swiftUIValue(in: appearance)
        #endif
    }
}

extension ColorToken {
    /// The value a SwiftUI view gets for this token in `appearance` (color scheme plus
    /// `colorSchemeContrast`), read back as 8-bit sRGB.
    @MainActor
    public func swiftUIValue(in appearance: Appearance) -> SRGBColor {
        var environment = EnvironmentValues()
        environment.colorScheme = appearance.isDark ? .dark : .light
        // The only way to set the contrast for resolution; it is what SwiftUI previews use.
        environment._colorSchemeContrast = appearance.isIncreasedContrast ? .increased : .standard
        let resolved = color.resolve(in: environment)
        guard let srgbSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let srgb = resolved.cgColor.converted(to: srgbSpace, intent: .defaultIntent, options: nil),
              let c = srgb.components, c.count == 4 else {
            preconditionFailure("\(rawValue) could not be converted to sRGB")
        }
        return SRGBColor.fromComponents(c[0], c[1], c[2], c[3])
    }
}

extension SRGBColor {
    /// Rounds 0...1 components to 8 bits; alpha to three decimals (the catalog's precision).
    static func fromComponents(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> SRGBColor {
        func channel(_ v: CGFloat) -> UInt8 { UInt8((min(max(v, 0), 1) * 255).rounded()) }
        return SRGBColor(red: channel(r), green: channel(g), blue: channel(b),
                         alpha: (Double(a) * 1000).rounded() / 1000)
    }
}

extension Appearance {
    #if canImport(UIKit)
    /// Traits selecting this appearance's asset catalog variant.
    @MainActor
    public var traitCollection: UITraitCollection {
        UITraitCollection { traits in
            traits.userInterfaceStyle = isDark ? .dark : .light
            traits.accessibilityContrast = isIncreasedContrast ? .high : .normal
        }
    }
    #elseif canImport(AppKit)
    public var appearanceName: NSAppearance.Name {
        switch self {
        case .light: .aqua
        case .dark: .darkAqua
        case .lightIncreasedContrast: .accessibilityHighContrastAqua
        case .darkIncreasedContrast: .accessibilityHighContrastDarkAqua
        }
    }
    #endif
}
