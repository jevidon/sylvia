import Foundation

/// An sRGB color with 8-bit channels and a separate alpha (plan 4.4.2).
///
/// Channel values are stored exactly as they appear in the token tables (`#RRGGBB`), so a value
/// written to the asset catalog and the JSON export is never re-quantized. Alpha is kept as a
/// decimal because the plan states translucent tokens as percentages ("ink at 12%").
public struct SRGBColor: Hashable, Sendable, CustomStringConvertible {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    /// 0...1. Opaque colors have alpha 1.
    public let alpha: Double

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: Double = 1) {
        precondition((0...1).contains(alpha), "alpha must be within 0...1")
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Parses `#RRGGBB`. Traps on malformed input: token literals are compile-time data.
    public init(hex: String) {
        guard let parsed = SRGBColor.parse(hex) else {
            preconditionFailure("not a #RRGGBB color: \(hex)")
        }
        self = parsed
    }

    /// Returns nil unless `text` is exactly `#RRGGBB` (six hex digits, either case).
    public static func parse(_ text: String) -> SRGBColor? {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count == 7, scalars[0] == "#" else { return nil }
        var channels: [UInt8] = []
        for index in stride(from: 1, to: 7, by: 2) {
            let pair = String(String.UnicodeScalarView(scalars[index...index + 1]))
            guard pair.allSatisfy(\.isHexDigit), let value = UInt8(pair, radix: 16) else { return nil }
            channels.append(value)
        }
        return SRGBColor(red: channels[0], green: channels[1], blue: channels[2])
    }

    public var isOpaque: Bool { alpha == 1 }

    /// `#RRGGBB`, upper case. Alpha is not included.
    public var hexRGB: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    /// `#RRGGBB` for opaque colors, `#RRGGBBAA` otherwise (alpha rounded to the nearest 8-bit value;
    /// the exact decimal alpha is exported separately).
    public var hex: String {
        if isOpaque { return hexRGB }
        return hexRGB + String(format: "%02X", Int((alpha * 255).rounded()))
    }

    public var description: String {
        isOpaque ? hexRGB : "\(hexRGB) at \(alpha)"
    }

    /// The same RGB with a different alpha.
    public func withAlpha(_ alpha: Double) -> SRGBColor {
        SRGBColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// Source-over compositing of `self` at `opacity` over an opaque `background`, in gamma-encoded
    /// sRGB (the way design tools and CSS blend), rounded to the nearest 8-bit value per channel.
    /// "Marker text at 14% over Night" is `marker.composited(over: night, opacity: 0.14)`.
    public func composited(over background: SRGBColor, opacity: Double) -> SRGBColor {
        precondition(background.isOpaque, "background must be opaque")
        precondition((0...1).contains(opacity), "opacity must be within 0...1")
        func blend(_ top: UInt8, _ bottom: UInt8) -> UInt8 {
            UInt8((opacity * Double(top) + (1 - opacity) * Double(bottom)).rounded())
        }
        return SRGBColor(
            red: blend(red, background.red),
            green: blend(green, background.green),
            blue: blend(blue, background.blue)
        )
    }

    /// Moves `fraction` of the way from `self` toward `target` (both opaque), rounded to 8-bit.
    /// Equivalent to compositing `target` at `fraction` over `self`.
    public func mixed(toward target: SRGBColor, fraction: Double) -> SRGBColor {
        precondition(isOpaque, "mixed(toward:) needs an opaque color")
        return target.composited(over: self, opacity: fraction)
    }

    /// Multiplies each channel by `factor` (0...1), rounded to 8-bit. Used only by the documented
    /// minimal-darkening search for Increase Contrast overrides (``ContrastAdjustment``).
    public func scaled(by factor: Double) -> SRGBColor {
        precondition((0...1).contains(factor), "factor must be within 0...1")
        func scale(_ channel: UInt8) -> UInt8 { UInt8((Double(channel) * factor).rounded()) }
        return SRGBColor(red: scale(red), green: scale(green), blue: scale(blue), alpha: alpha)
    }

    /// WCAG 2.x relative luminance of the opaque color.
    public var relativeLuminance: Double {
        func linear(_ channel: UInt8) -> Double {
            let c = Double(channel) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2.x contrast ratio between two opaque colors (1...21).
    public static func contrastRatio(_ a: SRGBColor, _ b: SRGBColor) -> Double {
        precondition(a.isOpaque && b.isOpaque, "contrast is defined for opaque colors")
        let la = a.relativeLuminance
        let lb = b.relativeLuminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
