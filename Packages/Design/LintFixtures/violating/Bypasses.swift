import CoreText
import SwiftUI
import UIKit

// Review round 1 (R1-01): spellings that an earlier version of the lint let through. Every line
// below must be reported with exactly the rule its marker names.

struct Bypasses: View {
    let source = "Studio"

    var body: some View {
        VStack {
            // Phrases with edge punctuation, or a phrase as a segment of a longer literal.
            Text("Saved.") // lint-expect: status-phrase
            Text("Ready!") // lint-expect: status-phrase
            Text("Saved ✓") // lint-expect: status-phrase
            Text("“Ready”") // lint-expect: status-phrase
            Text("Middlemarch · Ready") // lint-expect: status-phrase
            Text("Saving") // lint-expect: status-phrase
            Text("Waiting for \(source).") // lint-expect: status-phrase
            Text("Done!") // lint-expect: forbidden-phrase
            Text("Downloading…") // lint-expect: forbidden-phrase
            Text("Downloading...") // lint-expect: forbidden-phrase
            Text("Error: the file could not be read") // lint-expect: forbidden-phrase
            Text("Upload finished. Done!") // lint-expect: forbidden-phrase
            Text("Success") // lint-expect: forbidden-phrase
            Text("ERROR!") // lint-expect: forbidden-phrase
            Text("Thinking") // lint-expect: forbidden-phrase

            // Named system colors.
            Rectangle().fill(Color.red) // lint-expect: named-color
            Rectangle().fill(Color(uiColor: .systemBlue)) // lint-expect: named-color
            Rectangle().fill(.black.opacity(0.5)) // lint-expect: named-color
            Text(verbatim: "x").foregroundStyle(.secondary) // lint-expect: named-color
            Text(verbatim: "x").tint(.orange) // lint-expect: named-color
            Text(verbatim: "x").shadow(color: .black, radius: 2) // lint-expect: named-color
            Rectangle().fill(Color.accentColor) // lint-expect: named-color
            Rectangle().fill(Color("Brand")) // lint-expect: named-color
        }
    }
}

// Component initializers spelled with .init.
let initColor = Color.init(red: 0.2, green: 0.3, blue: 0.4) // lint-expect: color-components
let initUIColor = UIColor.init(red: 1, green: 0, blue: 0, alpha: 1) // lint-expect: color-components
let implicitInit: Color = .init(white: 0.4) // lint-expect: color-components
let implicitSRGB: Color = .init(.sRGB, red: 1, green: 0, blue: 0) // lint-expect: color-components
let cgGray = CGColor.init(gray: 0.5, alpha: 1) // lint-expect: color-components
let ciColor = CIColor(red: 1, green: 0, blue: 0) // lint-expect: color-components
let hexInit = Color.init(hex: 0) // lint-expect: hex-color

// Named UIKit and AppKit colors.
let label = UIColor.label // lint-expect: named-color
let named = UIColor(named: "Brand") // lint-expect: named-color
let background: UIColor = .systemBackground // lint-expect: named-color

// Literal font sizes outside .system(size:).
let resized = UIFont.preferredFont(forTextStyle: .body).withSize(22) // lint-expect: font-size
let coreText = CTFontCreateWithName("Literata" as CFString, 22, nil) // lint-expect: font-size
let coreTextDescriptor = CTFontDescriptorCreateWithNameAndSize("Literata" as CFString, 22) // lint-expect: font-size
let initFont = UIFont.init(name: "Literata", size: 22) // lint-expect: font-size
let implicitFont: UIFont? = .init(name: "Literata", size: 22) // lint-expect: font-size
let descriptor = UIFontDescriptor(name: "Literata", size: 22) // lint-expect: font-size
