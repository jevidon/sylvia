#if os(iOS)
import SwiftUI
import UIKit
@testable import SylviaDesign

/// Measurements on grayscale renderings (ADR-0013 Section 9). Every rendering here is the
/// luminance conversion of the color image (``Grayscale``), so a measured contrast between two grey
/// levels equals the WCAG contrast of the original colors and carries no hue.
struct GrayMeasure {
    let pixels: Pixels
    let scale: CGFloat

    init(_ rendered: Rendered) {
        pixels = Pixels(rendered.image)
        scale = rendered.image.scale
    }

    /// The most common grey level in `rect` (points), or in the whole image.
    func mode(in rect: CGRect? = nil) -> UInt8 {
        let levels = rect.map { pixels.greys(in: $0) } ?? pixels.greys(in: CGRect(x: 0, y: 0,
            width: CGFloat(pixels.width) / scale, height: CGFloat(pixels.height) / scale))
        var histogram = [Int](repeating: 0, count: 256)
        for level in levels { histogram[Int(level)] += 1 }
        return UInt8(histogram.indices.max { histogram[$0] < histogram[$1] } ?? 0)
    }

    /// The level in `rect` with the highest contrast against `reference`.
    func extreme(in rect: CGRect, against reference: UInt8) -> UInt8 {
        pixels.greys(in: rect).max { Grayscale.contrast($0, reference) < Grayscale.contrast($1, reference) } ?? reference
    }

    /// Fraction of pixels in `rect` whose contrast against `background` is at least `threshold`.
    func coverage(in rect: CGRect, background: UInt8, threshold: Double) -> Double {
        let levels = pixels.greys(in: rect)
        guard !levels.isEmpty else { return 0 }
        return Double(levels.filter { Grayscale.contrast($0, background) >= threshold }.count) / Double(levels.count)
    }

    /// Runs of "frame" pixels along the pixel row nearest to `y` points, between `x0` and `x1`
    /// points: a pixel belongs to the frame when its contrast against `interior` is at least
    /// `threshold`. A solid border gives one run; a dashed one gives many.
    func frameRuns(y: CGFloat, from x0: CGFloat, to x1: CGFloat, interior: UInt8, threshold: Double) -> Int {
        let row = min(max(Int((y * scale).rounded(.down)), 0), pixels.height - 1)
        let start = max(Int((x0 * scale).rounded(.up)), 0), end = min(Int((x1 * scale).rounded(.down)), pixels.width)
        var runs = 0
        var inRun = false
        for x in start..<max(end, start) {
            let isFrame = Grayscale.contrast(pixels.grey(x: x, y: row), interior) >= threshold
            if isFrame && !inRun { runs += 1 }
            inRun = isFrame
        }
        return runs
    }

    /// The row (in points, top edge of a pixel row) within the first `depth` points below
    /// `rect.minY` whose pixels contrast most with `interior` on average: where a 1 pt top border is.
    func borderRow(of rect: CGRect, interior: UInt8, depth: CGFloat = 2) -> CGFloat {
        let first = Int((rect.minY * scale).rounded(.down)), last = Int(((rect.minY + depth) * scale).rounded(.up))
        let x0 = Int(((rect.minX + rect.height / 2) * scale).rounded(.up))
        let x1 = Int(((rect.maxX - rect.height / 2) * scale).rounded(.down))
        var best = first, bestScore = -1.0
        for row in max(first, 0)...min(last, pixels.height - 1) where x1 > x0 {
            var sum = 0.0
            for x in x0..<x1 { sum += Grayscale.contrast(pixels.grey(x: x, y: row), interior) }
            let score = sum / Double(x1 - x0)
            if score > bestScore { bestScore = score; best = row }
        }
        return CGFloat(best) / scale
    }

    /// A binary shape mask of the ink in `rect` (pixels contrasting with the region's most common
    /// level by at least `threshold`), cropped to the ink's bounding box and resampled to an n x n
    /// grid, so shapes of different sizes compare by form.
    func shapeMask(in rect: CGRect, threshold: Double = 1.5, grid n: Int = 24) -> [Bool] {
        let background = mode(in: rect)
        let x0 = max(Int((rect.minX * scale).rounded(.down)), 0), x1 = min(Int((rect.maxX * scale).rounded(.up)), pixels.width)
        let y0 = max(Int((rect.minY * scale).rounded(.down)), 0), y1 = min(Int((rect.maxY * scale).rounded(.up)), pixels.height)
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in y0..<max(y1, y0) {
            for x in x0..<max(x1, x0) where Grayscale.contrast(pixels.grey(x: x, y: y), background) >= threshold {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return [Bool](repeating: false, count: n * n) }
        var mask = [Bool](repeating: false, count: n * n)
        let w = Double(maxX - minX + 1), h = Double(maxY - minY + 1)
        for gy in 0..<n {
            for gx in 0..<n {
                let px = minX + min(Int((Double(gx) + 0.5) * w / Double(n)), maxX - minX)
                let py = minY + min(Int((Double(gy) + 0.5) * h / Double(n)), maxY - minY)
                mask[gy * n + gx] = Grayscale.contrast(pixels.grey(x: px, y: py), background) >= threshold
            }
        }
        return mask
    }

    /// Fraction of cells where two masks differ.
    static func maskDifference(_ a: [Bool], _ b: [Bool]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 1 }
        return Double(zip(a, b).filter { $0 != $1 }.count) / Double(a.count)
    }
}

/// Collects the primary-button count a view publishes (one primary per screen).
@MainActor
final class PrimaryCount {
    var value = 0
}

extension View {
    @MainActor
    func reportingPrimaryCount(into box: PrimaryCount) -> some View {
        onPreferenceChange(PrimaryButtonCountKey.self) { count in
            MainActor.assumeIsolated { box.value = count }
        }
    }
}

/// Formats a ratio for the evidence tables.
func ratio(_ value: Double) -> String { String(format: "%.2f", value) }
#endif
