import AppKit
import SwiftUI
import UIKit

struct BadFonts: View {
    var body: some View {
        VStack {
            Text(verbatim: "x").font(.system(size: 17)) // lint-expect: font-size
            Text(verbatim: "x").font(Font.system(size: 17, weight: .semibold)) // lint-expect: font-size
            Text(verbatim: "x").font(.system(size: 17, weight: .regular, design: .serif)) // lint-expect: font-size
            Text(verbatim: "x").font(.custom("Literata", size: 19)) // lint-expect: font-size
            Text(verbatim: "x").font(.custom("Literata", fixedSize: 19)) // lint-expect: font-size
        }
    }
}

let a = UIFont.systemFont(ofSize: 13) // lint-expect: font-size
let b = UIFont.boldSystemFont(ofSize: 13) // lint-expect: font-size
let c = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular) // lint-expect: font-size
let d = UIFont(name: "Literata", size: 19) // lint-expect: font-size
let e = NSFont.systemFont(ofSize: 13) // lint-expect: font-size
let f: UIFont = .systemFont(ofSize: 13, weight: .medium) // lint-expect: font-size
let g = UIFont(descriptor: UIFontDescriptor(name: "Literata", size: 0), size: 19) // lint-expect: font-size
let h = Font.custom(fontName(for: role()), size: 19) // lint-expect: font-size
