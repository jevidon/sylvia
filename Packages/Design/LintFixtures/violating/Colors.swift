import AppKit
import SwiftUI
import UIKit

struct BadColors: View {
    var body: some View {
        VStack {
            Text(verbatim: "Title").foregroundStyle(Color(red: 0.2, green: 0.3, blue: 0.4)) // lint-expect: color-components
            Rectangle().fill(Color(.sRGB, red: 0.1, green: 0.1, blue: 0.1, opacity: 1)) // lint-expect: color-components
            Rectangle().fill(Color(white: 0.5)) // lint-expect: color-components
            Rectangle().fill(Color(hue: 0.5, saturation: 0.2, brightness: 0.4)) // lint-expect: color-components
            Rectangle().fill(Color(hex: "#F4F2ED")) // lint-expect: hex-color
        }
    }
}

let accent = "#2F5D50" // lint-expect: hex-color
let shortHex = "#FFF" // lint-expect: hex-color
let translucent = "#1C1B181F" // lint-expect: hex-color
let uiKit = UIColor(red: 1, green: 0, blue: 0, alpha: 1) // lint-expect: color-components
let p3 = UIColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1) // lint-expect: color-components
let appKit = NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1) // lint-expect: color-components
let srgb = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1) // lint-expect: color-components
let cg = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1) // lint-expect: color-components
let literal = #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1) // lint-expect: hex-color
let packedColor = 0xF4F2ED // lint-expect: hex-color
