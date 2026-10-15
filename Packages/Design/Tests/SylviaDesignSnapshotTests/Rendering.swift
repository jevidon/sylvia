#if os(iOS)
import Darwin
import SwiftUI
import Testing
import UIKit
@testable import SylviaDesign

/// One rendering condition: appearance (light, dark, both with Increase Contrast), text size and
/// Bold Text. Snapshot names come from it ("light-default", "dark-ic-ax5", ...).
struct Variant: Hashable, CustomStringConvertible {
    enum Size: String { case standard = "default", ax5 }

    let appearance: Appearance
    let size: Size
    let boldText: Bool

    init(_ appearance: Appearance, _ size: Size, boldText: Bool = false) {
        self.appearance = appearance
        self.size = size
        self.boldText = boldText
    }

    var name: String {
        let a: String
        switch appearance {
        case .light: a = "light"
        case .dark: a = "dark"
        case .lightIncreasedContrast: a = "light-ic"
        case .darkIncreasedContrast: a = "dark-ic"
        }
        return "\(a)-\(size.rawValue)\(boldText ? "-bold" : "")"
    }

    var description: String { name }

    /// Pixels per point of the snapshot: 2 at the default size; 1 at AX5, where text is already
    /// 40-60 pt and 2x would multiply the committed size by four for no extra legibility.
    var scale: CGFloat { size == .ax5 ? 1 : 2 }

    var contentSize: UIContentSizeCategory {
        size == .ax5 ? .accessibilityExtraExtraExtraLarge : .large
    }

    /// The snapshot matrix of T51/T53: four appearances at the default and the largest
    /// accessibility size.
    static let matrix: [Variant] = [Appearance.light, .dark, .lightIncreasedContrast, .darkIncreasedContrast]
        .flatMap { a in [Variant(a, .standard), Variant(a, .ax5)] }

    /// Bold Text, light, default size (color only).
    static let bold = Variant(.light, .standard, boldText: true)
}

/// The device the references are recorded on (ADR-0013 Section 9).
enum RecordingDevice {
    static let modelIdentifier = "iPhone18,3" // iPhone 17
    static let runtimePrefix = "26.5"
    /// iPhone 17 width in points.
    static let width: CGFloat = 402

    static var current: (model: String, runtime: String) {
        let env = ProcessInfo.processInfo.environment
        return (env["SIMULATOR_MODEL_IDENTIFIER"] ?? "unknown", env["SIMULATOR_RUNTIME_VERSION"] ?? "unknown")
    }

    static var isRecordingDevice: Bool {
        current.model == modelIdentifier && current.runtime.hasPrefix(runtimePrefix)
    }
}

/// An accessibility element as UIKit exposes it from the SwiftUI hosting view.
struct AXNode: CustomStringConvertible {
    let label: String
    let value: String
    let hint: String
    let traits: UIAccessibilityTraits
    let frame: CGRect
    let showsLargeContentViewer: Bool
    let largeContentTitle: String?

    var isButton: Bool { traits.contains(.button) }
    var isSelected: Bool { traits.contains(.selected) }

    var description: String {
        "\"\(label)\" value=\"\(value)\" traits=\(traits.rawValue) lcv=\(showsLargeContentViewer) frame=\(frame)"
    }
}

/// A rendered sample: the color image, the layout audit and the accessibility elements.
@MainActor
struct Rendered {
    let image: UIImage
    let audit: LayoutAudit
    let elements: [AXNode]
    let size: CGSize
}

@MainActor
enum Renderer {
    /// UIKit populates the SwiftUI accessibility tree only when an assistive technology or UI
    /// automation is active. This test-only call turns UI automation on in the test process, the
    /// same way the open-source AccessibilitySnapshot library does; nothing ships with it.
    static let accessibilityEnabled: Bool = {
        guard let handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let symbol = dlsym(handle, "_AXSSetAutomationEnabled") else { return false }
        typealias SetEnabled = @convention(c) (Int32) -> Void
        unsafeBitCast(symbol, to: SetEnabled.self)(1)
        return true
    }()

    /// A window to host the sample. The package test runner has no window scene (measured: none is
    /// connected on iOS 26.5), so the window is sceneless. `UIWindow()` and `UIWindow(frame:)` are
    /// deprecated on iOS 26 in favour of `init(windowScene:)`, which needs a scene this process does
    /// not have; the bare initializer is reached through `NSObject.Type` (the same call without the
    /// deprecated Swift overlay) so the test target builds without warnings. Test-only; nothing ships.
    static func makeWindow(frame: CGRect) -> UIWindow {
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            let windowClass: NSObject.Type = UIWindow.self
            guard let bare = windowClass.init() as? UIWindow else { preconditionFailure("UIWindow could not be created") }
            window = bare
        }
        window.frame = frame
        return window
    }

    /// Renders `view` at `width` points (height fits the content, or `height` when given) under the
    /// variant's traits, with a layout audit installed.
    static func render<V: View>(_ view: V, variant: Variant, width: CGFloat = RecordingDevice.width,
                                height: CGFloat? = nil, sizeClass: UIUserInterfaceSizeClass = .compact) -> Rendered {
        _ = accessibilityEnabled
        let audit = LayoutAudit()
        let host = UIHostingController(rootView: view.environment(\.sylviaLayoutAudit, audit))
        host.safeAreaRegions = []
        host.traitOverrides.userInterfaceStyle = variant.appearance.isDark ? .dark : .light
        host.traitOverrides.accessibilityContrast = variant.appearance.isIncreasedContrast ? .high : .normal
        host.traitOverrides.preferredContentSizeCategory = variant.contentSize
        host.traitOverrides.legibilityWeight = variant.boldText ? .bold : .regular
        host.traitOverrides.displayScale = variant.scale
        host.traitOverrides.horizontalSizeClass = sizeClass
        host.view.backgroundColor = .clear

        let window = makeWindow(frame: CGRect(x: 0, y: 0, width: width, height: height ?? 2000))
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        let fitted = host.sizeThatFits(in: CGSize(width: width, height: height ?? .greatestFiniteMagnitude))
        let size = CGSize(width: width, height: height ?? ceil(fitted.height))
        window.frame = CGRect(origin: .zero, size: size)
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        // Let geometry callbacks and the accessibility tree settle.
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))

        // 8-bit sRGB, not the simulator's extended-range Display P3 default.
        let format = UIGraphicsImageRendererFormat(for: host.traitCollection)
        format.scale = variant.scale
        format.preferredRange = .standard
        format.opaque = true
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image { context in
            host.view.layer.render(in: context.cgContext)
        }
        var nodes: [AXNode] = []
        collect(host.view, into: &nodes)
        window.isHidden = true
        window.rootViewController = nil
        return Rendered(image: image, audit: audit, elements: nodes, size: size)
    }

    private static func collect(_ object: NSObject, into nodes: inout [AXNode]) {
        let children: [Any]
        if let list = object.accessibilityElements, !list.isEmpty {
            children = list
        } else {
            let count = object.accessibilityElementCount()
            children = (count == NSNotFound || count <= 0) ? [] : (0..<count).compactMap { object.accessibilityElement(at: $0) }
        }
        for case let child as NSObject in children {
            if child.isAccessibilityElement {
                let item = child as? UILargeContentViewerItem
                nodes.append(AXNode(label: child.accessibilityLabel ?? "", value: child.accessibilityValue ?? "",
                                    hint: child.accessibilityHint ?? "", traits: child.accessibilityTraits,
                                    frame: child.accessibilityFrame,
                                    showsLargeContentViewer: item?.showsLargeContentViewer ?? false,
                                    largeContentTitle: item?.largeContentTitle))
            }
            collect(child, into: &nodes)
        }
        if children.isEmpty, let view = object as? UIView {
            for sub in view.subviews { collect(sub, into: &nodes) }
        }
    }
}

/// 8-bit sRGB pixels of an image, top row first.
struct Pixels {
    let width: Int
    let height: Int
    /// RGBA, premultiplied (images are opaque).
    let rgba: [UInt8]
    let scale: CGFloat

    init(_ image: UIImage) {
        let cg = image.cgImage!
        let w = cg.width, h = cg.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                    bytesPerRow: w * 4, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        width = w
        height = h
        scale = image.scale
        rgba = bytes
    }

    func rgb(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
        let i = (y * width + x) * 4
        return (rgba[i], rgba[i + 1], rgba[i + 2])
    }

    /// The luminance grey level (0-255) at a pixel.
    func grey(x: Int, y: Int) -> UInt8 {
        let (r, g, b) = rgb(x: x, y: y)
        return Grayscale.level(r, g, b)
    }

    /// Grey levels inside a rect given in points.
    func greys(in rect: CGRect) -> [UInt8] {
        let x0 = max(Int((rect.minX * scale).rounded(.up)), 0), x1 = min(Int((rect.maxX * scale).rounded(.down)), width)
        let y0 = max(Int((rect.minY * scale).rounded(.up)), 0), y1 = min(Int((rect.maxY * scale).rounded(.down)), height)
        guard x0 < x1, y0 < y1 else { return [] }
        var result: [UInt8] = []
        result.reserveCapacity((x1 - x0) * (y1 - y0))
        for y in y0..<y1 { for x in x0..<x1 { result.append(grey(x: x, y: y)) } }
        return result
    }
}

/// The grayscale conversion of ADR-0013 Section 9: WCAG relative luminance of each sRGB pixel,
/// re-encoded with the sRGB transfer function as a grey level. It keeps every WCAG contrast ratio
/// (which depends on luminance only) and removes hue, which is what a reader with no color sees.
enum Grayscale {
    private static let linear: [Double] = (0...255).map { v in
        let c = Double(v) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static func luminance(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Double {
        0.2126 * linear[Int(r)] + 0.7152 * linear[Int(g)] + 0.0722 * linear[Int(b)]
    }

    static func encode(_ y: Double) -> UInt8 {
        let c = y <= 0.0031308 ? 12.92 * y : 1.055 * pow(y, 1 / 2.4) - 0.055
        return UInt8((min(max(c, 0), 1) * 255).rounded())
    }

    static func level(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> UInt8 { encode(luminance(r, g, b)) }

    /// Luminance of a grey level.
    static func luminance(level: UInt8) -> Double { linear[Int(level)] }

    /// WCAG contrast ratio between two grey levels.
    static func contrast(_ a: UInt8, _ b: UInt8) -> Double {
        let la = luminance(level: a), lb = luminance(level: b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// The grayscale rendering of `image`: one 8-bit channel holding the sRGB-encoded luminance.
    static func image(_ image: UIImage) -> UIImage {
        let pixels = Pixels(image)
        var out = [UInt8](repeating: 255, count: pixels.width * pixels.height)
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                out[y * pixels.width + x] = pixels.grey(x: x, y: y)
            }
        }
        return UIImage(cgImage: GrayBitmap.makeImage(out, width: pixels.width, height: pixels.height),
                       scale: image.scale, orientation: .up)
    }
}
/// One-channel 8-bit images and their exact byte comparison. Values are stored and compared without
/// color management, so a grey level in the file is exactly the computed level.
enum GrayBitmap {
    static let space = CGColorSpaceCreateDeviceGray()

    static func makeImage(_ bytes: [UInt8], width: Int, height: Int) -> CGImage {
        var copy = bytes
        return copy.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width, space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue)!.makeImage()!
        }
    }

    /// The image's grey bytes, drawn into a DeviceGray context (no conversion for a DeviceGray image).
    static func bytes(_ image: CGImage) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: image.width * image.height)
        out.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width, space: space,
                                    bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return out
    }
}
#endif
