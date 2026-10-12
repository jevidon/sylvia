import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Text in a type role that is not broken inside a word when a smaller text size avoids it (T51).
///
/// At the largest accessibility sizes a single long word set in a large role ("Middlemarch" in the
/// Title role is 58 pt at AX5) is wider than an iPhone screen, and SwiftUI then breaks it between
/// letters ("Middlemarc / h"). `FittingText` measures the widest word in the role's resolved font
/// and, while it does not fit the width the text was given, steps the Dynamic Type size down one
/// step at a time, never below the default size (Large). Text that fits is untouched, so at the
/// default size and for ordinary titles it behaves exactly like `Text(_).sylviaFont(role)`. It
/// wraps and never truncates. The same rule fits typographic cover titles (``TypographicCover``).
/// On macOS, where there is no Dynamic Type scale, it is plain text in the role.
public struct FittingText: View {
    let text: String
    let role: TypeRole
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight
    @State private var width: CGFloat?

    public init(_ text: String, role: TypeRole) {
        self.text = text
        self.role = role
    }

    public var body: some View {
        #if canImport(UIKit)
        Text(text)
            .sylviaFont(role)
            .dynamicTypeSize(fittedSize)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
        #else
        Text(text)
            .sylviaFont(role)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }

    #if canImport(UIKit)
    private var fittedSize: DynamicTypeSize {
        guard let width else { return dynamicTypeSize }
        return Self.fittedSize(text, role: role, width: width, size: dynamicTypeSize,
                               boldText: legibilityWeight == .bold)
    }

    /// The largest Dynamic Type size from `size` down to `.large` at which the widest word of
    /// `text` in `role` fits `width` (one point of slack for layout rounding). Returns `size`
    /// when it already fits, and `.large` when even that does not.
    @MainActor
    public static func fittedSize(_ text: String, role: TypeRole, width: CGFloat, size: DynamicTypeSize,
                                  boldText: Bool) -> DynamicTypeSize {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard width > 0, !words.isEmpty else { return size }
        let steps = DynamicTypeSize.allCases
        guard var index = steps.firstIndex(of: size), let floor = steps.firstIndex(of: .large) else { return size }
        while index > floor {
            let style = role.resolved(contentSize: UIContentSizeCategory(steps[index]), boldText: boldText)
            if widestWord(words, style: style) <= width - 1 { break }
            index -= 1
        }
        return steps[index]
    }

    /// The typographic width of the widest word, with the role's tracking and case.
    static func widestWord(_ words: [String], style: ResolvedTypeStyle) -> CGFloat {
        words.map { word in
            let shown = style.uppercase ? word.uppercased() : word
            let attributed = NSAttributedString(string: shown, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): style.ctFont(),
                NSAttributedString.Key(kCTKernAttributeName as String): style.tracking,
            ])
            return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil)
        }.max() ?? 0
    }
    #endif
}
