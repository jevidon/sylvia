import SwiftUI
import UIKit

// Review round 2 (R2-01): spellings that the line-by-line lint let through. A call wrapped over
// several lines is reported on the line where it starts; every marked line must be reported with
// exactly the rules its markers name, and no other line.

struct WrappedCalls: View {
    let on = true

    var body: some View {
        VStack {
            // (a) Calls split across lines, as swift-format wraps them.
            Text(verbatim: "a").font(.system( // lint-expect: font-size
                size: 13))
            Text(verbatim: "b").font(Font.system( // lint-expect: font-size
                size: 12, weight: .bold))
            Text(verbatim: "c").font(Font.custom("Literata", // lint-expect: font-size
                size: 22))
            Text(verbatim: "d").font(.custom( // lint-expect: font-size
                "Literata",
                fixedSize: 22))
            Text(verbatim: "e").font(.system(size: // lint-expect: font-size
                13))
            Rectangle()
                .fill(Color( // lint-expect: color-components
                    .sRGB,
                    red: 0.1, green: 0.2, blue: 0.3))
            Rectangle()
                .foregroundStyle( // lint-expect: named-color
                    .secondary)
            Rectangle()
                .shadow(
                    color: .black, // lint-expect: named-color
                    radius: 2)

            // (b) A named color as a ternary branch of a color modifier.
            Text(verbatim: "f").foregroundStyle(on ? .red : .blue) // lint-expect: named-color
            Text(verbatim: "g").background(on ? Color.clear : .black) // lint-expect: named-color
            Rectangle().fill(on
                ? .primary // lint-expect: named-color
                : .secondary) // lint-expect: named-color

            // (c) Phrases wrapped in Markdown, which Text renders from a literal.
            Text("**Saved**") // lint-expect: status-phrase
            Text("_Done_") // lint-expect: forbidden-phrase
            Text("~~Ready~~") // lint-expect: status-phrase
            Text("`Saved`") // lint-expect: status-phrase
            Text("[Saved](https://example.com)") // lint-expect: status-phrase
            Text("**Not saved** · your text is still here") // lint-expect: status-phrase
            Text("Middlemarch · *Ready*") // lint-expect: status-phrase
        }
    }
}

// (a) Platform calls split across lines.
let wrappedSystemFont = UIFont.systemFont( // lint-expect: font-size
    ofSize: 12)
let wrappedComponents = Color( // lint-expect: color-components
    red: 0.1, green: 0.2, blue: 0.3)
let wrappedWhite = Color( // lint-expect: color-components
    white: 0.5)
let wrappedUIColor = UIColor // lint-expect: color-components
    .init(red: 1, green: 0, blue: 0, alpha: 1) // lint-expect: color-components
let wrappedFontName = UIFont( // lint-expect: font-size
    name: "Literata",
    size: 22)
let wrappedImplicitFont: UIFont? = .init( // lint-expect: font-size
    name: "Literata",
    size: 22)

// (b) Named colors by type, in a provider closure, and bridged from UIKit.
let typedColor: Color = .red // lint-expect: named-color
let typedOptional: Color? = .black // lint-expect: named-color
let typedTernary: Color = Bool.random() ? .white : .gray // lint-expect: named-color
let typedUIColor: UIColor = .label // lint-expect: named-color
let provider = UIColor { _ in .black } // lint-expect: color-provider
let explicitProvider = UIColor(dynamicProvider: { _ in .white }) // lint-expect: color-provider
let bridged = Color(uiColor: .label) // lint-expect: named-color
let bridgedUnlabelled = Color(.secondaryLabel) // lint-expect: named-color
var computedColor: Color { .red } // lint-expect: named-color
func colorFunction() -> Color { return .blue } // lint-expect: named-color

@MainActor func configure(_ view: UIView, _ label: UILabel) {
    view.backgroundColor = .white // lint-expect: named-color
    label.textColor = .label // lint-expect: named-color
    view.layer.borderColor = .black // lint-expect: named-color
}

@MainActor func configure(_ button: UIButton) {
    button.setTitleColor( // lint-expect: named-color
        .white, for: .normal)
}

// (d) A size in a font descriptor's attributes.
let sized = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body).addingAttributes([.size: 22]) // lint-expect: font-size
let sizedByName = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
    .addingAttributes([UIFontDescriptor.AttributeName.size: 22]) // lint-expect: font-size

// Other font(ofSize:) factories.
let boldFont = UIFont.boldSystemFont(ofSize: 12) // lint-expect: font-size
let monospacedFont = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular) // lint-expect: font-size
