import CoreGraphics
import Foundation

/// A rectangle normalized to a page box, in **unrotated page space**: the PDF user-space convention with the
/// origin at the lower-left corner of the box, x to the right, y up, each value a fraction of the box's width
/// or height. Encoded as `[x, y, width, height]`.
public struct NormalizedRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try c.decode(Double.self)
        y = try c.decode(Double.self)
        width = try c.decode(Double.self)
        height = try c.decode(Double.self)
        guard c.isAtEnd else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "normalized rect has more than four values")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x)
        try c.encode(y)
        try c.encode(width)
        try c.encode(height)
    }

    /// Largest absolute difference between corresponding values.
    public func maxDeviation(from other: NormalizedRect) -> Double {
        max(abs(x - other.x), abs(y - other.y), abs(width - other.width), abs(height - other.height))
    }
}

/// Page rotation as the PDF /Rotate value normalized to 0, 90, 180 or 270 degrees **clockwise** for display.
public enum PageRotation: Int, Codable, Sendable, CaseIterable {
    case r0 = 0, r90 = 90, r180 = 180, r270 = 270

    public init(degrees: Int) throws(GeometryError) {
        let n = ((degrees % 360) + 360) % 360
        guard let r = PageRotation(rawValue: n) else { throw .unsupportedRotation(degrees) }
        self = r
    }
}

public enum GeometryError: Error, Equatable, Sendable {
    case unsupportedRotation(Int)
    case emptyPageBox
}

public enum PageGeometry {
    /// Values are rounded to this many decimal places when stored (1e-6 of a US Letter page is under 0.001 pt).
    public static let storedDecimalPlaces = 6

    public static func normalize(_ rect: CGRect, in box: CGRect) throws(GeometryError) -> NormalizedRect {
        guard box.width > 0, box.height > 0 else { throw .emptyPageBox }
        return NormalizedRect(
            x: round6(Double((rect.minX - box.minX) / box.width)),
            y: round6(Double((rect.minY - box.minY) / box.height)),
            width: round6(Double(rect.width / box.width)),
            height: round6(Double(rect.height / box.height))
        )
    }

    public static func denormalize(_ n: NormalizedRect, in box: CGRect) -> CGRect {
        CGRect(
            x: box.minX + CGFloat(n.x) * box.width,
            y: box.minY + CGFloat(n.y) * box.height,
            width: CGFloat(n.width) * box.width,
            height: CGFloat(n.height) * box.height
        )
    }

    /// Maps a normalized unrotated-page rectangle into **display space** as a viewer shows the page after
    /// applying the clockwise rotation: normalized to the displayed page, origin at the top-left, y down.
    /// This is what a client on any platform draws an overlay with (it needs only the stored rect and rotation).
    public static func displayRect(_ n: NormalizedRect, rotation: PageRotation) -> NormalizedRect {
        switch rotation {
        case .r0:
            return NormalizedRect(x: n.x, y: 1 - (n.y + n.height), width: n.width, height: n.height)
        case .r90:
            return NormalizedRect(x: n.y, y: n.x, width: n.height, height: n.width)
        case .r180:
            return NormalizedRect(x: 1 - (n.x + n.width), y: n.y, width: n.width, height: n.height)
        case .r270:
            return NormalizedRect(x: 1 - (n.y + n.height), y: 1 - (n.x + n.width), width: n.height, height: n.width)
        }
    }

    /// Inverse of `displayRect`.
    public static func unrotatedRect(fromDisplay d: NormalizedRect, rotation: PageRotation) -> NormalizedRect {
        switch rotation {
        case .r0:
            return NormalizedRect(x: d.x, y: 1 - (d.y + d.height), width: d.width, height: d.height)
        case .r90:
            return NormalizedRect(x: d.y, y: d.x, width: d.height, height: d.width)
        case .r180:
            return NormalizedRect(x: 1 - (d.x + d.width), y: d.y, width: d.width, height: d.height)
        case .r270:
            return NormalizedRect(x: 1 - (d.y + d.height), y: 1 - (d.x + d.width), width: d.height, height: d.width)
        }
    }

    /// Size of the displayed page for a box and rotation (width and height swap at 90 and 270).
    public static func displaySize(of box: CGRect, rotation: PageRotation) -> CGSize {
        switch rotation {
        case .r0, .r180: return box.size
        case .r90, .r270: return CGSize(width: box.height, height: box.width)
        }
    }

    static func round6(_ v: Double) -> Double {
        let scale = 1_000_000.0
        return (v * scale).rounded() / scale
    }
}
