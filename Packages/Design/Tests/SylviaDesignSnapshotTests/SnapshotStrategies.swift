#if os(iOS)
import ImageIO
import SnapshotTesting
import UIKit
import UniformTypeIdentifiers

extension Snapshotting where Value == UIImage, Format == UIImage {
    /// Color snapshots: snapshot-testing's exact pixel comparison (precision 1, perceptual 1) on
    /// 8-bit sRGB PNGs.
    static func color(scale: CGFloat) -> Snapshotting {
        .image(precision: 1, perceptualPrecision: 1, scale: scale)
    }

    /// Grayscale snapshots: one-channel 8-bit PNGs compared byte for byte, without color
    /// management (the stored level is the computed luminance level).
    static func grayscale(scale: CGFloat) -> Snapshotting {
        Snapshotting(pathExtension: "png", diffing: .grayscale(scale: scale))
    }
}

extension Diffing where Value == UIImage {
    static func grayscale(scale: CGFloat) -> Diffing {
        Diffing.diff(
            toData: { image in GrayPNG.encode(image.cgImage!) },
            fromData: { data in UIImage(cgImage: GrayPNG.decode(data)!, scale: scale, orientation: .up) }
        ) { reference, new in
            guard let a = reference.cgImage, let b = new.cgImage else { return ("image could not be read", []) }
            guard a.width == b.width, a.height == b.height else {
                return ("size \(b.width)x\(b.height) px differs from the reference \(a.width)x\(a.height) px", [])
            }
            let old = GrayBitmap.bytes(a), fresh = GrayBitmap.bytes(b)
            var differing = 0, largest = 0
            for i in 0..<old.count where old[i] != fresh[i] {
                differing += 1
                largest = max(largest, abs(Int(old[i]) - Int(fresh[i])))
            }
            guard differing > 0 else { return nil }
            var diff = [UInt8](repeating: 0, count: old.count)
            for i in 0..<old.count { diff[i] = UInt8(min(abs(Int(old[i]) - Int(fresh[i])) * 8, 255)) }
            let difference = GrayBitmap.makeImage(diff, width: a.width, height: a.height)
            return ("\(differing) of \(old.count) grey pixels differ (largest difference \(largest) levels)",
                    [DiffAttachment.data(GrayPNG.encode(a), name: "reference.png"),
                     DiffAttachment.data(GrayPNG.encode(b), name: "failure.png"),
                     DiffAttachment.data(GrayPNG.encode(difference), name: "difference.png")])
        }
    }
}

/// PNG encoding of one-channel images through ImageIO.
enum GrayPNG {
    static func encode(_ image: CGImage) -> Data {
        let gray = GrayBitmap.makeImage(GrayBitmap.bytes(image), width: image.width, height: image.height)
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, gray, nil)
        precondition(CGImageDestinationFinalize(destination), "PNG encoding failed")
        return data as Data
    }

    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
#endif
