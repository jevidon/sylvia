import UIKit

/// Launch options. Stage 0 harness only; UI tests drive it through launch arguments.
///
///   -fixture <name.pdf>          open this bundled fixture (default labels-multipage.pdf)
///   -noLinkInterceptor           control run: do not install the link interceptor (PDFKit's default handling)
///   -resetHighlights             delete stored highlights for the fixture before opening
///   -seedRange <page>:<start>:<end>   capture and store a highlight for this scalar range, then show that page
///   -noRedrawAfterHighlight      control run: after saving a highlight, do not call PDFView.setNeedsDisplay()
struct HarnessOptions {
    var fixture = "labels-multipage.pdf"
    var installLinkInterceptor = true
    var resetHighlights = false
    var seedRange: (page: Int, start: Int, end: Int)?
    var redrawAfterHighlight = true

    static func fromProcess() -> HarnessOptions {
        var o = HarnessOptions()
        let args = ProcessInfo.processInfo.arguments
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if let f = value(after: "-fixture") { o.fixture = f }
        o.installLinkInterceptor = !args.contains("-noLinkInterceptor")
        o.resetHighlights = args.contains("-resetHighlights")
        o.redrawAfterHighlight = !args.contains("-noRedrawAfterHighlight")
        if let s = value(after: "-seedRange") {
            let parts = s.split(separator: ":").compactMap { Int($0) }
            if parts.count == 3 { o.seedRange = (parts[0], parts[1], parts[2]) }
        }
        return o
    }
}

enum HarnessLaunch {
    @MainActor
    static func makeRootViewController() -> UIViewController {
        ReaderViewController(options: .fromProcess())
    }
}
