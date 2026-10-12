import CoreText
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Registers the bundled Literata fonts for this process (Section 4.4.3; ADR-0013).
public enum FontRegistration {
    /// True once both Literata files are registered. Safe to call from any thread; registration
    /// happens once.
    @discardableResult
    public static func registerLiterata() -> Bool { registered }

    private static let registered: Bool = {
        var ok = true
        for file in LiterataFont.files {
            let name = (file as NSString).deletingPathExtension
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") else {
                ok = false
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                let code = error.map { CFErrorGetCode($0.takeRetainedValue()) }
                if code != CTFontManagerError.alreadyRegistered.rawValue { ok = false }
            }
        }
        return ok
    }()
}

/// A type role resolved for one text size, weight setting and platform.
public struct ResolvedTypeStyle: Sendable, Hashable {
    public let role: TypeRole
    public let face: Face
    public let pointSize: Double
    /// Line height in points (the role's ratio applied to ``pointSize``).
    public let lineHeight: Double
    /// Tracking in points (the role's fraction applied to ``pointSize``).
    public let tracking: Double
    public let weight: Int
    /// The `opsz` value set on Literata; nil for system faces.
    public let opticalSize: Double?
    public let uppercase: Bool

    /// The platform font for this style. Literata is created with explicit `wght` and `opsz`
    /// variation values; system faces with the nearest system weight.
    public func ctFont() -> CTFont {
        switch face {
        case .literata:
            FontRegistration.registerLiterata()
            let variation: [NSNumber: NSNumber] = [
                NSNumber(value: LiterataFont.weightAxisTag): NSNumber(value: weight),
                NSNumber(value: LiterataFont.opticalSizeAxisTag): NSNumber(value: opticalSize ?? pointSize),
            ]
            let attributes: [CFString: Any] = [
                kCTFontNameAttribute: LiterataFont.postScriptName,
                kCTFontVariationAttribute: variation,
            ]
            let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
            return CTFontCreateWithFontDescriptor(descriptor, pointSize, nil)
        case .system:
            #if canImport(UIKit)
            return UIFont.systemFont(ofSize: pointSize, weight: Self.systemWeight(weight)) as CTFont
            #else
            return NSFont.systemFont(ofSize: pointSize, weight: Self.systemWeight(weight)) as CTFont
            #endif
        case .monospace:
            #if canImport(UIKit)
            return UIFont.monospacedSystemFont(ofSize: pointSize, weight: Self.systemWeight(weight)) as CTFont
            #else
            return NSFont.monospacedSystemFont(ofSize: pointSize, weight: Self.systemWeight(weight)) as CTFont
            #endif
        }
    }

    #if canImport(UIKit)
    public func uiFont() -> UIFont { ctFont() as UIFont }
    #else
    public func nsFont() -> NSFont { ctFont() as NSFont }
    #endif

    /// The font's natural line height (ascent + descent + leading).
    public func naturalLineHeight() -> Double {
        let font = ctFont()
        return CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    }

    /// Extra spacing between lines that brings the natural line height to ``lineHeight``.
    public func lineSpacing() -> Double { max(0, lineHeight - naturalLineHeight()) }

    #if canImport(UIKit)
    typealias PlatformWeight = UIFont.Weight
    #else
    typealias PlatformWeight = NSFont.Weight
    #endif

    static func systemWeight(_ weight: Int) -> PlatformWeight {
        switch weight {
        case ..<150: .ultraLight
        case ..<250: .thin
        case ..<350: .light
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        case ..<750: .bold
        case ..<850: .heavy
        default: .black
        }
    }
}

extension TypeRole {
    /// Resolves the role for a base size (the role's size, or the reader's size for ``reading``),
    /// a Dynamic Type scale function and Bold Text.
    static func resolve(_ role: TypeRole, readingSize: ReadingSize, monospaced: Bool, weightOverride: Int?,
                        faceOverride: Face? = nil,
                        boldText: Bool, scale: (TextStyle, Double) -> Double) -> ResolvedTypeStyle {
        let spec = role.spec
        let base = role == .reading ? readingSize.points : spec.size
        let size = scale(spec.textStyle, base)
        let face: Face = faceOverride ?? (monospaced && spec.face == .system ? .monospace : spec.face)
        return ResolvedTypeStyle(
            role: role, face: face, pointSize: size,
            lineHeight: size * spec.lineHeightRatio,
            tracking: size * spec.tracking,
            weight: BoldText.weight(weightOverride ?? spec.weight, boldText: boldText),
            opticalSize: face == .literata ? LiterataFont.opticalSize(forPointSize: size) : nil,
            uppercase: spec.uppercase
        )
    }

    #if canImport(UIKit)
    /// Resolves the role for `traits`: the size scales in proportion to the mapped text style's
    /// system size at the traits' content size category; Bold Text comes from `legibilityWeight`.
    ///
    /// Roles whose default size equals their text style's (every role but Reading) therefore get
    /// exactly the system size at every category. `UIFontMetrics.scaledValue(for:compatibleWith:)`
    /// was measured on iOS 26.5 not to reproduce the system sizes (Body at AX5: 48 pt against 53),
    /// so it is not used (ADR-0013; evidence in uifontmetrics-vs-system-simulator.md).
    public func resolved(compatibleWith traits: UITraitCollection,
                         readingSize: ReadingSize = .default,
                         monospaced: Bool = false,
                         weight: Int? = nil, face: Face? = nil) -> ResolvedTypeStyle {
        TypeRole.resolve(self, readingSize: readingSize, monospaced: monospaced, weightOverride: weight,
                         faceOverride: face, boldText: traits.legibilityWeight == .bold) { style, base in
            base * style.systemPointSize(compatibleWith: traits) / style.iOSDefaultPointSize
        }
    }

    /// Convenience for a content size category and Bold Text setting. Main actor: UIKit's mutable
    /// traits require it.
    @MainActor
    public func resolved(contentSize: UIContentSizeCategory, boldText: Bool = false,
                         readingSize: ReadingSize = .default, monospaced: Bool = false,
                         weight: Int? = nil, face: Face? = nil) -> ResolvedTypeStyle {
        let traits = UITraitCollection { t in
            t.preferredContentSizeCategory = contentSize
            t.legibilityWeight = boldText ? .bold : .regular
        }
        return resolved(compatibleWith: traits, readingSize: readingSize, monospaced: monospaced, weight: weight,
                        face: face)
    }
    #else
    /// macOS has no Dynamic Type scale; sizes follow the macOS text styles. Each role keeps its
    /// proportion to its mapped style: size = role size x (macOS style size / iOS default size).
    public func resolved(boldText: Bool = false, readingSize: ReadingSize = .default,
                         monospaced: Bool = false, weight: Int? = nil, face: Face? = nil) -> ResolvedTypeStyle {
        TypeRole.resolve(self, readingSize: readingSize, monospaced: monospaced, weightOverride: weight,
                         faceOverride: face, boldText: boldText) { style, base in
            let macSize = NSFont.preferredFont(forTextStyle: style.nsTextStyle).pointSize
            return base * macSize / style.iOSDefaultPointSize
        }
    }
    #endif
}

extension TextStyle {
    #if canImport(UIKit)
    /// The system font size of this text style for `traits` (its content size category).
    public func systemPointSize(compatibleWith traits: UITraitCollection) -> Double {
        UIFont.preferredFont(forTextStyle: uiTextStyle, compatibleWith: traits).pointSize
    }

    public var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title1: .title1
        case .title2: .title2
        case .body: .body
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption2: .caption2
        }
    }
    #else
    public var nsTextStyle: NSFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title1: .title1
        case .title2: .title2
        case .body: .body
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption2: .caption2
        }
    }
    #endif
}

/// Applies a type role: font, tracking, line spacing and the Micro role's uppercase. Reads the
/// environment's Dynamic Type size and Bold Text, so text re-renders when either changes.
public struct TypeRoleModifier: ViewModifier {
    let role: TypeRole
    let readingSize: ReadingSize
    let monospaced: Bool
    let weight: Int?
    var face: Face? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight

    public func body(content: Content) -> some View {
        let style = resolvedStyle()
        content
            .font(Font(style.ctFont()))
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing())
            .textCase(style.uppercase ? .uppercase : nil)
            .modifier(TextAuditModifier(role: role))
    }

    func resolvedStyle() -> ResolvedTypeStyle {
        Self.resolve(role, dynamicTypeSize: dynamicTypeSize, legibilityWeight: legibilityWeight,
                     readingSize: readingSize, monospaced: monospaced, weight: weight, face: face)
    }

    /// The role resolved for a view's Dynamic Type size and Bold Text setting (for a view that needs
    /// a role's font as a value, for example for one run of an attributed string).
    @MainActor
    static func resolve(_ role: TypeRole, dynamicTypeSize: DynamicTypeSize, legibilityWeight: LegibilityWeight?,
                        readingSize: ReadingSize = .default, monospaced: Bool = false, weight: Int? = nil,
                        face: Face? = nil) -> ResolvedTypeStyle {
        let bold = legibilityWeight == .bold
        #if canImport(UIKit)
        return role.resolved(contentSize: UIContentSizeCategory(dynamicTypeSize), boldText: bold,
                             readingSize: readingSize, monospaced: monospaced, weight: weight, face: face)
        #else
        return role.resolved(boldText: bold, readingSize: readingSize, monospaced: monospaced, weight: weight,
                             face: face)
        #endif
    }
}

extension View {
    /// Sets text in a Marginalia type role. `monospaced` switches a system role to SF Mono for
    /// values (timecodes, byte counts, digests); `weight` is for the few treatments that name a
    /// different weight (for example the Generated question in Body 600).
    public func sylviaFont(_ role: TypeRole, readingSize: ReadingSize = .default, monospaced: Bool = false,
                           weight: Int? = nil) -> some View {
        modifier(TypeRoleModifier(role: role, readingSize: readingSize, monospaced: monospaced, weight: weight))
    }

    /// Sets a typeset glyph (the Quote mark) in `face` at the size of `role`, so the mark keeps its
    /// typeface wherever it sits (Section 4.4.5: the Quote glyph is set in Literata).
    func sylviaFont(_ role: TypeRole, face: Face, weight: Int? = nil) -> some View {
        modifier(TypeRoleModifier(role: role, readingSize: .default, monospaced: false, weight: weight, face: face))
    }
}
