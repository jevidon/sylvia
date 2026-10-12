import CoreGraphics
import Foundation
import Testing
@testable import SylviaDesign
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Renders `draw` into an RGBA bitmap and returns (ink coverage in points², bounding box of ink).
private func measureInk(width: Int, height: Int, scale: CGFloat,
                        draw: (CGContext) -> Void) -> (ink: Double, box: CGRect, png: Data?) {
    let pw = Int(CGFloat(width) * scale), ph = Int(CGFloat(height) * scale)
    let context = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: pw * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: scale, y: scale)
    #if canImport(UIKit)
    // UIKit drawing assumes a top-left origin; bitmap contexts are bottom-left.
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    #endif
    draw(context)
    let data = context.data!.assumingMemoryBound(to: UInt8.self)
    var ink = 0.0
    var minX = pw, minY = ph, maxX = -1, maxY = -1
    for y in 0..<ph {
        for x in 0..<pw {
            let a = data[(y * pw + x) * 4 + 3]
            ink += Double(a) / 255
            if a > 127 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    let box = maxX < 0 ? .zero : CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                                        width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
    let png: Data? = context.makeImage().flatMap { image in
        #if canImport(UIKit)
        UIImage(cgImage: image).pngData()
        #else
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        #endif
    }
    return (ink / Double(scale * scale), box, png)
}

#if canImport(UIKit)
private func symbolImage(_ name: String, custom: Bool, configuration: UIImage.SymbolConfiguration) -> UIImage? {
    custom ? UIImage(named: name, in: SylviaDesign.bundle, with: configuration)
        : UIImage(systemName: name, withConfiguration: configuration)
}

private func ink(of image: UIImage) -> (ink: Double, box: CGRect) {
    let size = image.size
    let r = measureInk(width: Int(size.width.rounded(.up)) + 2, height: Int(size.height.rounded(.up)) + 2, scale: 3) { cg in
        UIGraphicsPushContext(cg)
        image.withTintColor(.black).draw(at: CGPoint(x: 1, y: 1))
        UIGraphicsPopContext()
    }
    return (r.ink, r.box)
}

private let weights: [UIImage.SymbolWeight] = [.ultraLight, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
#else
private func symbolImage(_ name: String, custom: Bool, configuration: NSImage.SymbolConfiguration) -> NSImage? {
    let base = custom ? NSImage(symbolName: name, bundle: SylviaDesign.bundle, variableValue: 0)
        : NSImage(systemSymbolName: name, accessibilityDescription: nil)
    return base?.withSymbolConfiguration(configuration)
}

private func ink(of image: NSImage) -> (ink: Double, box: CGRect) {
    let size = image.size
    let r = measureInk(width: Int(size.width.rounded(.up)) + 2, height: Int(size.height.rounded(.up)) + 2, scale: 3) { cg in
        let ns = NSGraphicsContext(cgContext: cg, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        image.draw(at: NSPoint(x: 1, y: 1), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }
    return (r.ink, r.box)
}

private let weights: [NSFont.Weight] = [.ultraLight, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
#endif

@Suite("Custom symbols and marker glyphs (plan 4.4.5)")
@MainActor
struct SymbolTests {
    @Test("Custom symbols load from the package as symbol images with accessibility labels", arguments: CustomSymbol.allCases)
    func loads(symbol: CustomSymbol) throws {
        #if canImport(UIKit)
        let image = try #require(symbol.uiImage())
        #expect(image.isSymbolImage)
        #else
        let image = try #require(symbol.nsImage())
        #expect(image.accessibilityDescription == symbol.accessibilityLabel)
        #endif
        #expect(image.size.width > 0)
        #expect(symbol.accessibilityLabel == symbol.accessibilityLabelKey.text)
    }

    @Test("Ink rises with every step of symbol weight, like SF Symbols", arguments: CustomSymbol.allCases)
    func weightInterpolates(symbol: CustomSymbol) throws {
        var previous = 0.0
        var row: [String] = []
        for weight in weights {
            #if canImport(UIKit)
            let config = UIImage.SymbolConfiguration(pointSize: 40, weight: weight)
            #else
            let config = NSImage.SymbolConfiguration(pointSize: 40, weight: weight)
            #endif
            let image = try #require(symbolImage(symbol.rawValue, custom: true, configuration: config))
            let measured = ink(of: image).ink
            #expect(measured > previous, "\(symbol) weight \(weight): \(measured) after \(previous)")
            previous = measured
            row.append(String(format: "%.1f", measured))
        }
        Evidence.write("symbol-weights-\(symbol.rawValue)-\(Evidence.platformSuffix).txt",
                       text: "\(Evidence.environmentLabel)\nink (pt^2) at 40 pt, ultraLight...black: \(row.joined(separator: ", "))\n")
    }

    @Test("Size matches system symbols at the same configuration", arguments: CustomSymbol.allCases)
    func sizeMatchesSystem(symbol: CustomSymbol) throws {
        #if canImport(UIKit)
        let config = UIImage.SymbolConfiguration(pointSize: 34, weight: .regular)
        #else
        let config = NSImage.SymbolConfiguration(pointSize: 34, weight: .regular)
        #endif
        let custom = ink(of: try #require(symbolImage(symbol.rawValue, custom: true, configuration: config))).box
        let reference = ink(of: try #require(symbolImage("waveform", custom: false, configuration: config))).box
        // The bracket glyph spans the same height as the waveform; the prompt glyph is 10/16 of it on the boards.
        let expectedRatio = symbol == .capture ? 1.0 : 11.75 / 17.75
        let ratio = custom.height / reference.height
        #expect(abs(ratio - expectedRatio) < 0.15, "\(symbol): height ratio \(ratio) to waveform")
    }

    #if canImport(UIKit)
    @Test("Custom symbols scale with Dynamic Type through a text-style configuration", arguments: CustomSymbol.allCases)
    func dynamicType(symbol: CustomSymbol) throws {
        func height(_ category: UIContentSizeCategory) throws -> CGFloat {
            let config = UIImage.SymbolConfiguration(textStyle: .body)
                .applying(UIImage.SymbolConfiguration(traitCollection: UITraitCollection(preferredContentSizeCategory: category)))
            let image = try #require(UIImage(named: symbol.rawValue, in: SylviaDesign.bundle, with: config))
            return image.size.height
        }
        let normal = try height(.large)
        let largest = try height(.accessibilityExtraExtraExtraLarge)
        #expect(largest > normal * 2, "\(normal) -> \(largest)")
    }
    #endif

    @Test("Every SF Symbol the markers and pills name exists on this platform")
    func systemSymbolsExist() {
        var names = Marker.allCases.compactMap { marker -> String? in
            if case .systemSymbol(let name) = marker.glyph { return name }
            if case .typeset(_, _, let equivalent) = marker.glyph { return equivalent }
            return nil
        }
        names += StatusGlyph.allCases.map(\.systemSymbol)
        for name in names {
            #if canImport(UIKit)
            #expect(UIImage(systemName: name) != nil, "\(name)")
            #else
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(name)")
            #endif
        }
    }

    @Test("Evidence: custom glyphs beside system symbols at four weights")
    func evidenceSheet() throws {
        let names: [(String, Bool)] = [("sylvia.prompt", true), ("chevron.right", false), ("sylvia.capture", true),
                                       ("waveform", false), ("pencil.tip", false)]
        let sheetWeights = [weights[0], weights[2], weights[4], weights[7]]
        let cell: CGFloat = 56
        let r = measureInk(width: Int(cell) * names.count, height: Int(cell) * sheetWeights.count, scale: 2) { cg in
            for (row, weight) in sheetWeights.enumerated() {
                for (column, (name, custom)) in names.enumerated() {
                    #if canImport(UIKit)
                    let config = UIImage.SymbolConfiguration(pointSize: 28, weight: weight)
                    guard let image = symbolImage(name, custom: custom, configuration: config) else { continue }
                    UIGraphicsPushContext(cg)
                    image.withTintColor(.black).draw(at: CGPoint(x: CGFloat(column) * cell + 10, y: CGFloat(row) * cell + 10))
                    UIGraphicsPopContext()
                    #else
                    let config = NSImage.SymbolConfiguration(pointSize: 28, weight: weight)
                    guard let image = symbolImage(name, custom: custom, configuration: config) else { continue }
                    let ns = NSGraphicsContext(cgContext: cg, flipped: false)
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = ns
                    let y = CGFloat(sheetWeights.count - 1 - row) * cell + 10
                    image.draw(at: NSPoint(x: CGFloat(column) * cell + 10, y: y), from: .zero, operation: .sourceOver, fraction: 1)
                    NSGraphicsContext.restoreGraphicsState()
                    #endif
                }
            }
        }
        #expect(r.ink > 0)
        if let png = r.png { Evidence.write("symbols-sheet-\(Evidence.platformSuffix).png", png) }
    }
}
