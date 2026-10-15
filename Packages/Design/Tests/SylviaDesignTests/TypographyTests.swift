import CoreText
import Foundation
import SwiftUI
import Testing
@testable import SylviaDesign
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The variation value of `tag` on `font`; Core Text omits an axis that sits at its default.
private func variation(_ font: CTFont, _ tag: UInt32, default value: Double) -> Double {
    let dict = CTFontCopyVariation(font) as? [NSNumber: NSNumber] ?? [:]
    return dict[NSNumber(value: tag)]?.doubleValue ?? value
}

private func weightTrait(_ font: CTFont) -> Double {
    let traits = CTFontCopyTraits(font) as? [CFString: Any] ?? [:]
    return (traits[kCTFontWeightTrait] as? NSNumber)?.doubleValue ?? 0
}

@Suite("Type roles on the platform (plan 4.4.3, 4.4.8)")
@MainActor
struct TypographyTests {
    #if canImport(UIKit)
    static let categories: [UIContentSizeCategory] = [
        .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge,
        .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge, .accessibilityExtraExtraLarge,
        .accessibilityExtraExtraExtraLarge,
    ]

    func resolved(_ role: TypeRole, _ category: UIContentSizeCategory = .large, bold: Bool = false,
                  reading: ReadingSize = .default) -> ResolvedTypeStyle {
        role.resolved(contentSize: category, boldText: bold, readingSize: reading)
    }
    #else
    func resolved(_ role: TypeRole, bold: Bool = false, reading: ReadingSize = .default) -> ResolvedTypeStyle {
        role.resolved(boldText: bold, readingSize: reading)
    }
    #endif

    @Test("Literata registers from the package bundle")
    func registration() {
        #expect(FontRegistration.registerLiterata())
        #expect(FontRegistration.registerLiterata(), "idempotent")
        #expect(SylviaDesign.bundle.url(forResource: "OFL", withExtension: "txt", subdirectory: "Fonts") != nil,
                "the license ships beside the fonts")
        let font = TypeRole.reading.spec.face == .literata ? resolvedDefault(.reading).ctFont() : nil
        #expect(font.map { CTFontCopyFamilyName($0) as String } == "Literata")
    }

    func resolvedDefault(_ role: TypeRole, bold: Bool = false) -> ResolvedTypeStyle {
        #if canImport(UIKit)
        resolved(role, .large, bold: bold)
        #else
        resolved(role, bold: bold)
        #endif
    }

    @Test("Literata roles carry their weight (400/500/600) and an optical size equal to the point size",
          arguments: [TypeRole.display, .title, .heading, .reading])
    func literataVariation(role: TypeRole) {
        let style = resolvedDefault(role)
        let font = style.ctFont()
        #expect(CTFontCopyFamilyName(font) as String == "Literata")
        #expect(variation(font, LiterataFont.weightAxisTag, default: 400) == Double(role.spec.weight))
        #expect(abs(variation(font, LiterataFont.opticalSizeAxisTag, default: 12) - style.pointSize) < 0.01)
        #expect(abs(CTFontGetSize(font) - style.pointSize) < 0.001)
    }

    @Test("Bold Text raises Literata and system weights", arguments: TypeRole.allCases)
    func boldText(role: TypeRole) {
        let regular = resolvedDefault(role)
        let bold = resolvedDefault(role, bold: true)
        #expect(bold.weight == role.spec.weight + 200)
        if role.spec.face == .literata {
            #expect(variation(bold.ctFont(), LiterataFont.weightAxisTag, default: 400) == Double(role.spec.weight + 200))
        } else {
            #expect(weightTrait(bold.ctFont()) > weightTrait(regular.ctFont()), "\(role)")
        }
    }

    @Test("System roles use the system face at their weight")
    func systemWeights() {
        let body = weightTrait(resolvedDefault(.body).ctFont())
        let callout = weightTrait(resolvedDefault(.callout).ctFont())
        let micro = weightTrait(resolvedDefault(.micro).ctFont())
        #expect(body < callout && callout < micro, "400 < 500 < 600")
        #expect(!(CTFontCopyFamilyName(resolvedDefault(.body).ctFont()) as String).contains("Literata"))
    }

    @Test("Monospace switches a system role to SF Mono with fixed-width digits")
    func monospace() {
        #if canImport(UIKit)
        let style = TypeRole.caption.resolved(contentSize: .large, monospaced: true)
        #else
        let style = TypeRole.caption.resolved(monospaced: true)
        #endif
        #expect(style.face == .monospace)
        #expect(CTFontGetSymbolicTraits(style.ctFont()).contains(.traitMonoSpace))
    }

    @Test("Line height and tracking scale with the size; Micro is uppercase with +8% tracking")
    func lineAndTracking() {
        for role in TypeRole.allCases {
            let s = resolvedDefault(role)
            #expect(abs(s.lineHeight / s.pointSize - role.spec.lineHeightRatio) < 1e-9)
            #expect(abs(s.tracking - role.spec.tracking * s.pointSize) < 1e-9)
            let natural = s.naturalLineHeight()
            if natural <= s.lineHeight { #expect(abs(natural + s.lineSpacing() - s.lineHeight) < 1e-6, "\(role)") }
        }
        let micro = resolvedDefault(.micro)
        #expect(micro.uppercase && abs(micro.tracking - 0.08 * micro.pointSize) < 1e-9)
    }

    #if canImport(UIKit)
    @Test("Default Dynamic Type size gives the table's sizes")
    func defaultSizes() {
        for role in TypeRole.allCases {
            #expect(abs(resolved(role).pointSize - role.spec.size) < 0.01, "\(role)")
        }
    }

    @Test("Every role except Reading tracks its system text style exactly at every content size",
          arguments: TypeRole.allCases.filter { $0 != .reading })
    func tracksSystemStyle(role: TypeRole) {
        for category in Self.categories {
            let traits = UITraitCollection(preferredContentSizeCategory: category)
            let system = UIFont.preferredFont(forTextStyle: role.spec.textStyle.uiTextStyle, compatibleWith: traits)
            let ours = resolved(role, category).pointSize
            #expect(abs(ours - system.pointSize) < 0.5, "\(role) at \(category.rawValue): \(ours) vs \(system.pointSize)")
        }
    }

    @Test("Finding: UIFontMetrics does not reproduce system sizes; Sylvia's roles do")
    func uiFontMetricsComparison() {
        var table = "# UIFontMetrics against the system text style sizes\n\nEnvironment: \(Evidence.environmentLabel)\n\n"
        table += "For each mapped text style and content size: the system size (`UIFont.preferredFont`), "
        table += "`UIFontMetrics.scaledValue(for: default size)`, `UIFontMetrics.scaledFont(for: systemFont(ofSize: default size))`, "
        table += "and Sylvia's resolved role size.\n\n"
        table += "| Style | Category | System | scaledValue | scaledFont | Sylvia role |\n| --- | --- | --- | --- | --- | --- |\n"
        var maxValueDeviation = 0.0
        for role in TypeRole.allCases where role != .reading {
            let style = role.spec.textStyle
            for category in Self.categories {
                let traits = UITraitCollection(preferredContentSizeCategory: category)
                let system = UIFont.preferredFont(forTextStyle: style.uiTextStyle, compatibleWith: traits).pointSize
                let metrics = UIFontMetrics(forTextStyle: style.uiTextStyle)
                let value = metrics.scaledValue(for: style.iOSDefaultPointSize, compatibleWith: traits)
                let font = metrics.scaledFont(for: UIFont.systemFont(ofSize: style.iOSDefaultPointSize),
                                              compatibleWith: traits).pointSize
                let ours = resolved(role, category).pointSize
                #expect(abs(ours - system) < 1e-6, "\(role) at \(category.rawValue)")
                maxValueDeviation = max(maxValueDeviation, abs(value - system))
                table += "| \(style.rawValue) | \(category.rawValue.replacingOccurrences(of: "UICTContentSizeCategory", with: "")) | "
                table += "\(String(format: "%.2f", system)) | \(String(format: "%.2f", value)) | \(String(format: "%.2f", font)) | "
                table += "\(String(format: "%.2f", ours)) |\n"
            }
        }
        table += "\nLargest |scaledValue - system|: \(String(format: "%.2f", maxValueDeviation)) pt.\n"
        Evidence.write("uifontmetrics-vs-system-simulator.md", text: table)
    }

    @Test("Reading scales with Body: user size x (body size / 17) at every content size")
    func readingScales() {
        for category in Self.categories {
            let body = UIFont.preferredFont(forTextStyle: .body,
                                            compatibleWith: UITraitCollection(preferredContentSizeCategory: category)).pointSize
            for user in [14.0, 19, 28] {
                let size = resolved(.reading, category, reading: ReadingSize(points: user)).pointSize
                #expect(abs(size - user * body / 17) < 1.0, "\(user) at \(category.rawValue): \(size)")
            }
        }
        // The user range is clamped before scaling.
        #expect(resolved(.reading, reading: ReadingSize(points: 40)).pointSize == 28)
    }

    @Test("Largest accessibility size: roles grow and Literata keeps a valid optical size")
    func largestAccessibilitySize() {
        var table = "# Type roles at the default and largest accessibility sizes\n\nEnvironment: \(Evidence.environmentLabel)\n\n"
        table += "| Role | Face | Weight | Size at Large | Size at AX5 | Line at AX5 | opsz at AX5 | Bold Text weight |\n"
        table += "| --- | --- | --- | --- | --- | --- | --- | --- |\n"
        for role in TypeRole.allCases {
            let normal = resolved(role, .large)
            let largest = resolved(role, .accessibilityExtraExtraExtraLarge)
            #expect(largest.pointSize > normal.pointSize * 1.5, "\(role)")
            if role.spec.face == .literata {
                let font = largest.ctFont()
                let opsz = variation(font, LiterataFont.opticalSizeAxisTag, default: 12)
                #expect(abs(opsz - LiterataFont.opticalSize(forPointSize: largest.pointSize)) < 0.01)
            }
            let bold = resolved(role, .accessibilityExtraExtraExtraLarge, bold: true)
            table += "| \(role.rawValue) | \(largest.face.rawValue) | \(largest.weight) | \(String(format: "%.1f", normal.pointSize)) | "
            table += "\(String(format: "%.1f", largest.pointSize)) | \(String(format: "%.1f", largest.lineHeight)) | "
            table += "\(largest.opticalSize.map { String(format: "%.1f", $0) } ?? "n/a") | \(bold.weight) |\n"
        }
        Evidence.write("type-roles-simulator.md", text: table)
    }

    @Test("Bold Text comes from the trait collection's legibility weight")
    func boldFromTraits() {
        let traits = UITraitCollection(legibilityWeight: .bold)
        #expect(TypeRole.body.resolved(compatibleWith: traits).weight == 600)
        #expect(TypeRole.body.resolved(compatibleWith: UITraitCollection(legibilityWeight: .regular)).weight == 400)
    }
    #else
    @Test("macOS: each role keeps its proportion to the macOS text style")
    func macSizes() {
        var table = "# Type roles on macOS\n\nEnvironment: \(Evidence.environmentLabel)\n\n| Role | macOS style size | Role size | Line |\n| --- | --- | --- | --- |\n"
        for role in TypeRole.allCases {
            let mac = NSFont.preferredFont(forTextStyle: role.spec.textStyle.nsTextStyle).pointSize
            let s = resolved(role)
            let expected = (role == .reading ? ReadingSize.defaultPoints : role.spec.size) * mac
                / role.spec.textStyle.iOSDefaultPointSize
            #expect(abs(s.pointSize - expected) < 1e-9, "\(role)")
            if role != .reading { #expect(abs(s.pointSize - mac) < 1e-9, "\(role) equals the macOS style") }
            table += "| \(role.rawValue) | \(mac) | \(String(format: "%.2f", s.pointSize)) | \(String(format: "%.2f", s.lineHeight)) |\n"
        }
        Evidence.write("type-roles-host.md", text: table)
    }
    #endif
}

@Suite("SwiftUI type role modifier")
@MainActor
struct TypeRoleModifierTests {
    func renderedSize(_ view: some View) -> CGSize {
        let renderer = ImageRenderer(content: view.fixedSize())
        renderer.scale = 1
        guard let image = renderer.cgImage else { return .zero }
        return CGSize(width: image.width, height: image.height)
    }

    #if canImport(UIKit)
    @Test("sylviaFont follows the environment's Dynamic Type size")
    func followsDynamicType() {
        let normal = renderedSize(Text(verbatim: "Middlemarch").sylviaFont(.title).environment(\.dynamicTypeSize, .large))
        let largest = renderedSize(Text(verbatim: "Middlemarch").sylviaFont(.title)
            .environment(\.dynamicTypeSize, .accessibility5))
        #expect(normal.height > 0)
        #expect(largest.height > normal.height * 1.5, "\(normal) -> \(largest)")
    }

    @Test("Custom symbols in SwiftUI scale with Dynamic Type", arguments: CustomSymbol.allCases)
    func symbolFollowsDynamicType(symbol: CustomSymbol) {
        let normal = renderedSize(symbol.image.font(.body).environment(\.dynamicTypeSize, .large))
        let largest = renderedSize(symbol.image.font(.body).environment(\.dynamicTypeSize, .accessibility5))
        #expect(normal.height > 0)
        #expect(largest.height > normal.height * 2, "\(normal) -> \(largest)")
    }
    #endif

    @Test("sylviaFont honors Bold Text from the environment")
    func followsBoldText() {
        let regular = renderedSize(Text(verbatim: "Middlemarch").sylviaFont(.body).environment(\.legibilityWeight, .regular))
        let bold = renderedSize(Text(verbatim: "Middlemarch").sylviaFont(.body).environment(\.legibilityWeight, .bold))
        #expect(regular.width > 0)
        #expect(bold.width > regular.width, "\(regular) -> \(bold)")
    }
}
