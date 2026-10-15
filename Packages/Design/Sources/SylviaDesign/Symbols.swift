import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension CustomSymbol {
    /// The custom symbol as a SwiftUI image with its accessibility label. As a symbol image it
    /// takes its size from the surrounding font (so it follows Dynamic Type) and its weight from
    /// the font weight or `.fontWeight`, like SF Symbols.
    public var image: Image {
        Image(rawValue, bundle: .module, label: Text(accessibilityLabel))
    }

    public var accessibilityLabel: String { accessibilityLabelKey.localized }

    #if canImport(UIKit)
    public func uiImage(configuration: UIImage.Configuration? = nil) -> UIImage? {
        UIImage(named: rawValue, in: .module, with: configuration)
    }
    #elseif canImport(AppKit)
    public func nsImage(configuration: NSImage.SymbolConfiguration? = nil) -> NSImage? {
        let image = NSImage(symbolName: rawValue, bundle: .module, variableValue: 0)
        image?.accessibilityDescription = accessibilityLabel
        guard let configuration else { return image }
        return image?.withSymbolConfiguration(configuration)
    }
    #endif
}

/// A marker's glyph in its own color: an SF Symbol, a package custom symbol, or the Quote mark set
/// in Literata. Sized by the surrounding font; labelled with the marker's label.
public struct MarkerGlyph: View {
    let marker: Marker
    let role: TypeRole?

    /// `role` sizes the glyph (symbols and the typeset Quote mark alike); nil takes symbols' size
    /// from the surrounding font and sets the Quote mark in the Reading role.
    public init(_ marker: Marker, role: TypeRole? = nil) {
        self.marker = marker
        self.role = role
    }

    public var body: some View {
        glyph
            .foregroundStyle(marker.textColor.color)
            .accessibilityLabel(Text(marker.labelKey.localized))
    }

    @ViewBuilder private var glyph: some View {
        switch marker.glyph {
        case .systemSymbol(let name):
            if let role { Image(systemName: name).sylviaFont(role) } else { Image(systemName: name) }
        case .customSymbol(let symbol):
            if let role { symbol.image.sylviaFont(role) } else { symbol.image }
        case .typeset(let text, let face, _):
            // In its own face (Literata) at the size of `role`, following Dynamic Type.
            Text(verbatim: text).sylviaFont(role ?? .reading, face: face, weight: LiterataFont.markWeight)
        }
    }
}

/// A status pill glyph (dot, check, triangle).
extension StatusGlyph {
    public var image: Image { Image(systemName: systemSymbol) }
}
