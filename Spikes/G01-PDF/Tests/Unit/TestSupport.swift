import CoreGraphics
import Foundation
import PDFAnchorKit
import PDFKit
import UIKit
import XCTest

/// Fixture access, evidence output and pixel helpers shared by the unit tests.
enum Fixture {
    static func url(_ name: String) -> URL {
        guard let url = Bundle(for: BundleToken.self).url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            fatalError("fixture \(name) is not in the test bundle")
        }
        return url
    }

    /// Copies a fixture into a fresh temporary directory (standing in for Sylvia-managed storage) and returns it.
    static func copy(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("g01-pdf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(name)
        try FileManager.default.copyItem(at: url(name), to: dest)
        return dest
    }

    static func open(_ name: String) throws -> PDFSourceDocument {
        try PDFSourceDocument.open(url: url(name))
    }
}

private final class BundleToken {}

/// Evidence files go to $SYLVIA_G01_PDF_EVIDENCE_DIR (set by Scripts/ci.d/32-g01-pdf.sh through the TEST_RUNNER_
/// prefix). Without it they go to a temporary directory, so an IDE run never edits the repository.
enum Evidence {
    static let directory: URL = {
        let env = ProcessInfo.processInfo.environment["SYLVIA_G01_PDF_EVIDENCE_DIR"]
        let url = env.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("g01-pdf-evidence", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func write(_ name: String, _ text: String) {
        let url = directory.appendingPathComponent(name)
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            print("evidence: wrote \(url.path)")
        } catch {
            XCTFail("could not write evidence \(name): \(error)")
        }
    }

    static func writePNG(_ name: String, _ image: CGImage) {
        let data = UIImage(cgImage: image).pngData()
        guard let data else { return XCTFail("PNG encoding failed for \(name)") }
        XCTAssertLessThan(data.count, 2_000_000, "evidence images must stay under 2 MB")
        let url = directory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            print("evidence: wrote \(url.path) (\(data.count) bytes)")
        } catch {
            XCTFail("could not write evidence \(name): \(error)")
        }
    }

    static var environmentLabel: String {
        let device = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"].map { "simulator \($0)" } ?? "device"
        let name = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "unknown device"
        return "\(device) (\(name)), \(ExtractionVersion.platformDescription())"
    }
}

/// Text escaping for evidence logs: non-ASCII scalars as \u{...}, newlines as \n.
func esc(_ s: String?) -> String {
    guard let s else { return "nil" }
    return s.unicodeScalars.map { u in
        if u == "\n" { return "\\n" }
        if u == "\r" { return "\\r" }
        if u.value < 0x20 || u.value > 0x7E { return String(format: "\\u{%X}", u.value) }
        return String(u)
    }.joined()
}

/// An RGBA8 copy of an image for pixel sampling. (0, 0) is the top-left pixel.
struct Pixels {
    let width: Int
    let height: Int
    private let data: [UInt8]

    init(_ image: CGImage) {
        let w = image.width
        let h = image.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        buffer.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        width = w
        height = h
        data = buffer
    }

    struct RGB: Equatable, CustomStringConvertible {
        var r: Int, g: Int, b: Int
        /// Rec. 709 relative luminance of the sRGB value (gamma-encoded approximation, 0...1).
        var luminance: Double { (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255 }
        func distance(to o: RGB) -> Int { max(abs(r - o.r), abs(g - o.g), abs(b - o.b)) }
        var description: String { String(format: "#%02X%02X%02X", r, g, b) }
    }

    func at(_ x: Int, _ y: Int) -> RGB {
        let cx = min(max(x, 0), width - 1)
        let cy = min(max(y, 0), height - 1)
        let i = (cy * width + cx) * 4
        return RGB(r: Int(data[i]), g: Int(data[i + 1]), b: Int(data[i + 2]))
    }

    /// The most common colour in a pixel rectangle (the paper or fill colour behind glyphs).
    func dominant(in rect: CGRect) -> RGB {
        var counts: [Int: Int] = [:]
        let r = rect.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !r.isNull, r.width > 0, r.height > 0 else { return RGB(r: -1, g: -1, b: -1) }
        for y in Int(r.minY)..<Int(r.maxY) {
            for x in Int(r.minX)..<Int(r.maxX) {
                let p = at(x, y)
                counts[(p.r << 16) | (p.g << 8) | p.b, default: 0] += 1
            }
        }
        let key = counts.max { $0.value < $1.value }!.key
        return RGB(r: (key >> 16) & 0xFF, g: (key >> 8) & 0xFF, b: key & 0xFF)
    }
}

enum Expected {
    static let paper = Pixels.RGB(r: 0xFF, g: 0xFF, b: 0xFF)
    static let ochreTint = Pixels.RGB(r: 0xF1, g: 0xE4, b: 0xC8)
    static let ochre = Pixels.RGB(r: 0x8A, g: 0x54, b: 0x10)
}

/// Converts a normalized display-space rect (origin top-left) into image pixels.
func pixelRect(_ n: NormalizedRect, imageWidth: Int, imageHeight: Int) -> CGRect {
    CGRect(x: n.x * Double(imageWidth), y: n.y * Double(imageHeight),
           width: n.width * Double(imageWidth), height: n.height * Double(imageHeight))
}

/// A grayscale copy of an image (Rec. 709 luminance), as a colour filter would show it.
func grayscale(_ image: CGImage) -> CGImage? {
    let space = CGColorSpaceCreateDeviceGray()
    guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return ctx.makeImage()
}

@MainActor
func spinRunLoop(seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

@MainActor
func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    return condition()
}
