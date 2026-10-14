import UIKit
import XCTest

/// Screen-capture checks shared by the UI tests: is the highlight overlay that the harness publishes (window
/// coordinates, points) actually on screen as an Ochre fill plus underline? No test methods here.
@MainActor
class ScreenCheckTestCase: XCTestCase {
    struct RGB { var r, g, b: Int
        func distance(to o: RGB) -> Int { max(abs(r - o.r), abs(g - o.g), abs(b - o.b)) }
        var hex: String { String(format: "#%02X%02X%02X", r, g, b) }
    }

    static let ochre = RGB(r: 0x8A, g: 0x54, b: 0x10)
    static let ochreTint = RGB(r: 0xF1, g: 0xE4, b: 0xC8)

    override func setUp() {
        continueAfterFailure = false
    }

    /// The screenshot as an upright bitmap in the app's current interface orientation, so that window coordinates
    /// map onto it by one scale factor. `XCUIScreenshot` images carry their orientation as metadata; drawing through
    /// `UIImage` applies it. Returns nil (with a test failure) if the result does not have the app's aspect.
    func uprightScreenImage(_ shot: XCUIScreenshot, appFrame: CGRect, note: inout [String]) -> CGImage? {
        let image = shot.image
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        format.preferredRange = .standard
        let upright = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        guard let cg = upright.cgImage else {
            XCTFail("no screenshot bitmap")
            return nil
        }
        note.append("screenshot \(Int(image.size.width))x\(Int(image.size.height)) pt, orientation metadata \(image.imageOrientation.rawValue), "
                    + "upright bitmap \(cg.width)x\(cg.height) px; app frame \(Int(appFrame.width))x\(Int(appFrame.height)) pt")
        let appLandscape = appFrame.width > appFrame.height
        let imageLandscape = cg.width > cg.height
        XCTAssertEqual(appLandscape, imageLandscape, "screenshot and app disagree on orientation: \(note.last ?? "")")
        return appLandscape == imageLandscape ? cg : nil
    }

    /// Pixels of the image inside a window-coordinate rect.
    func pixels(_ image: CGImage, _ rect: CGRect, pointsWide: CGFloat) -> [RGB] {
        // Never convert a non-finite value to Int (that trapped the runner once: ui-runner-nan-crash.txt).
        guard pointsWide > 0, !rect.isNull, !rect.isInfinite else { return [] }
        let scale = CGFloat(image.width) / pointsWide
        let r = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale).integral
        let w = image.width, h = image.height
        guard !r.isNull, !r.isInfinite, r.width >= 1, r.height >= 1 else { return [] }
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        buffer.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var out: [RGB] = []
        for y in max(0, Int(r.minY))..<max(max(0, Int(r.minY)), min(h, Int(r.maxY))) {
            for x in max(0, Int(r.minX))..<max(max(0, Int(r.minX)), min(w, Int(r.maxX))) {
                let i = (y * w + x) * 4
                out.append(RGB(r: Int(buffer[i]), g: Int(buffer[i + 1]), b: Int(buffer[i + 2])))
            }
        }
        return out
    }

    /// Equal within 0.01 pt (an intersection recomputes width from maxX - minX).
    static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.01 && abs(a.minY - b.minY) < 0.01 && abs(a.width - b.width) < 0.01 && abs(a.height - b.height) < 0.01
    }

    /// Fraction of pixels within `tolerance` (per channel) of `colour`.
    func share(_ px: [RGB], near colour: RGB, tolerance: Int) -> Double {
        px.isEmpty ? 0 : Double(px.filter { $0.distance(to: colour) <= tolerance }.count) / Double(px.count)
    }

    /// Checks each published highlight line on screen; returns a report line per line. A line that runs past the
    /// PDF view (zoomed in) is checked where it is inside the view; one outside the view is listed and skipped. At
    /// least `minimumChecked` lines must be checked. With `expectOverlay: false` (a control) every checked line must
    /// instead show no underline and mostly white paper where the fill would be. With `saveImage: false` the screen
    /// capture is only attached to the test result, not written to the evidence directory.
    func checkOverlayOnScreen(_ app: XCUIApplication, name: String, minimumChecked: Int = 1, expectOverlay: Bool = true,
                              saveImage: Bool = true) -> [String] {
        let lines = Harness.rects(app, "overlayFrames")
        XCTAssertFalse(lines.isEmpty, "no highlight lines published for the current page")
        Thread.sleep(forTimeInterval: 1.5) // let PDFView finish rendering its tiles
        // Re-read after the tiles settled: the geometry is republished every 0.5 s.
        let settled = Harness.rects(app, "overlayFrames")
        let viewFrame = Harness.rects(app, "pdfViewFrame").first.map { Harness.rect(Substring($0)) } ?? .null
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.lifetime = .keepAlways
        add(attachment)
        var report: [String] = []
        let appFrame = app.frame
        guard let image = uprightScreenImage(shot, appFrame: appFrame, note: &report) else { return report }
        // Saved upright (as the person sees it), not in the screenshot's raw sensor orientation.
        if saveImage { Harness.writeEvidencePNG("ui-\(name).png", UIImage(cgImage: image)) }
        report.append("PDF view frame (window points) \(viewFrame.integral)")
        var checked = 0
        for line in settled {
            let parts = line.split(separator: " ")
            guard parts.count == 2 else { continue }
            let fullU = Harness.rect(parts[0].dropFirst(2))
            let fullF = Harness.rect(parts[1].dropFirst(2))
            // When zoomed, a line can run past the edge of the PDF view: check the part that is inside it.
            let u = viewFrame.isNull ? CGRect.null : fullU.intersection(viewFrame)
            let f = viewFrame.isNull ? CGRect.null : fullF.intersection(viewFrame)
            guard !u.isNull, !f.isNull, max(u.width, u.height) >= 4, max(f.width, f.height) >= 4 else {
                report.append("line \(fullU.union(fullF).integral) is outside the PDF view; not checked")
                continue
            }
            if !Self.same(u, fullU) || !Self.same(f, fullF) { report.append("line \(fullU.union(fullF).integral) runs past the PDF view; checking the part inside it") }
            checked += 1
            // The underline can be under 1 pt on screen at fit-to-width zoom, so its edges are antialiased: require
            // that a solid share of the band is ochre and that the fill band is mostly the tint.
            let underlineShare = share(pixels(image, u.width > 3 ? u.insetBy(dx: 1, dy: 0) : u, pointsWide: appFrame.width), near: Self.ochre, tolerance: 24)
            let underlineShareRotated = share(pixels(image, u.height > 3 ? u.insetBy(dx: 0, dy: 1) : u, pointsWide: appFrame.width), near: Self.ochre, tolerance: 24)
            // At reading zoom the glyphs cover much of the fill band; what matters is that the paper behind them is
            // the tint, not white.
            let fillPixels = pixels(image, f.insetBy(dx: min(1, f.width / 4), dy: min(1, f.height / 4)), pointsWide: appFrame.width)
            let fillShare = share(fillPixels, near: Self.ochreTint, tolerance: 12)
            let paperShare = share(fillPixels, near: RGB(r: 255, g: 255, b: 255), tolerance: 4)
            let uShare = max(underlineShare, underlineShareRotated)
            report.append("underline \(u.integral): \(Int(uShare * 100)) % of pixels within 24 of \(Self.ochre.hex); fill \(f.integral): \(Int(fillShare * 100)) % within 12 of \(Self.ochreTint.hex), \(Int(paperShare * 100)) % white paper")
            // Also in the test log, so a failed check still shows its measurement.
            print("[screen-check \(name)] overlay frames \(settled); \(report.last ?? "")")
            if expectOverlay {
                XCTAssertGreaterThanOrEqual(uShare, 0.2, "underline band on screen is not ochre (\(name))")
                XCTAssertGreaterThanOrEqual(fillShare, 0.3, "fill band on screen is not ochre.tint (\(name))")
                XCTAssertLessThanOrEqual(paperShare, 0.05, "white paper shows through the fill band (\(name))")
            } else {
                XCTAssertLessThan(uShare, 0.05, "control: an ochre underline is on screen (\(name))")
                XCTAssertLessThan(fillShare, 0.05, "control: the ochre.tint fill is on screen (\(name))")
                XCTAssertGreaterThan(paperShare, 0.3, "control: no white paper in the fill band (\(name))")
            }
        }
        XCTAssertGreaterThanOrEqual(checked, minimumChecked, "too few highlight lines on screen to check (\(name))")
        return report
    }
}
