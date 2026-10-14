import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// The pairing link as a QR code drawn with text, for `sylvia-source --qr` (plan 15.2: "a copyable code or
/// link and optionally a QR"). The phone scans it with Sylvia's own scanner (ADR-0008 recommends that over the
/// system Camera, which may hand a `sylvia://` link to another app).
///
/// The QR code carries the invitation secret, exactly like the printed code and link, so the command-line source
/// draws it only on its controlling terminal (`/dev/tty`), never on standard output: redirected or logged output
/// never contains it.
public enum PairingQRCode {
    public enum Failure: Error, Equatable {
        /// The text does not fit in a QR code at the chosen error-correction level.
        case tooLong
        case renderingFailed
    }

    /// Error correction level L (about 7 % recovery): the code is read from a screen, not from print that can
    /// be damaged, and L keeps a pairing link of about 500 characters near 80 terminal columns.
    public static let correctionLevel = "L"
    /// Light modules around the symbol, as the QR specification requires (ISO/IEC 18004: four modules).
    public static let quietZone = 4

    /// The symbol's modules, row by row (true = dark), without a quiet zone.
    public static func modules(for text: String) throws(Failure) -> [[Bool]] {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = correctionLevel
        guard let image = filter.outputImage, !image.extent.isEmpty else { throw .tooLong }
        let width = Int(image.extent.width)
        let height = Int(image.extent.height)
        guard width > 0, height > 0, let cgImage = CIContext().createCGImage(image, from: image.extent) else { throw .renderingFailed }
        // One pixel per module: draw into an 8-bit grey bitmap whose layout is known, then threshold.
        var pixels = [UInt8](repeating: 255, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.interpolationQuality = .none
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw .renderingFailed }
        // Bitmap rows run top to bottom. Trim whatever margin the generator added: the finder patterns sit in three
        // corners, so the dark pixels' bounding box is exactly the symbol.
        let dark = (0..<height).map { row in (0..<width).map { column in pixels[row * width + column] < 128 } }
        let rows = dark.indices.filter { dark[$0].contains(true) }
        let columns = (0..<width).filter { column in dark.contains { $0[column] } }
        guard let top = rows.first, let bottom = rows.last, let left = columns.first, let right = columns.last,
            bottom - top == right - left
        else { throw .renderingFailed }
        return (top...bottom).map { row in Array(dark[row][left...right]) }
    }

    /// The modules with the quiet zone added on every side.
    public static func withQuietZone(_ modules: [[Bool]]) -> [[Bool]] {
        let size = modules.count + 2 * quietZone
        let blank = [Bool](repeating: false, count: size)
        let pad = [Bool](repeating: false, count: quietZone)
        return Array(repeating: blank, count: quietZone) + modules.map { pad + $0 + pad } + Array(repeating: blank, count: quietZone)
    }

    /// Terminal lines that draw the symbol and its quiet zone: two module rows per line with half-block
    /// characters, black on white through ANSI colours, so the code scans the same in light and dark terminals.
    /// The terminal must be at least `columns(for:)` characters wide; a wrapped line breaks the code.
    public static func terminalLines(for text: String) throws(Failure) -> [String] {
        terminalLines(modules: withQuietZone(try modules(for: text)))
    }

    static let blackOnWhite = "\u{1B}[30;47m"
    static let reset = "\u{1B}[0m"

    static func terminalLines(modules: [[Bool]]) -> [String] {
        stride(from: 0, to: modules.count, by: 2).map { row in
            let upper = modules[row]
            let lower = row + 1 < modules.count ? modules[row + 1] : [Bool](repeating: false, count: upper.count)
            let cells = zip(upper, lower).map { pair -> Character in
                switch pair {
                case (true, true): "\u{2588}"  // full block
                case (true, false): "\u{2580}"  // upper half block
                case (false, true): "\u{2584}"  // lower half block
                case (false, false): " "
                }
            }
            return blackOnWhite + String(cells) + reset
        }
    }

    /// Terminal columns the drawing needs.
    public static func columns(for text: String) throws(Failure) -> Int {
        try modules(for: text).count + 2 * quietZone
    }

    /// Reads drawn lines back into modules (tests: the drawing shows exactly the symbol).
    public static func modules(fromTerminalLines lines: [String]) -> [[Bool]] {
        var result: [[Bool]] = []
        for line in lines {
            let cells = line.replacingOccurrences(of: blackOnWhite, with: "").replacingOccurrences(of: reset, with: "")
            result.append(cells.map { $0 == "\u{2588}" || $0 == "\u{2580}" })
            result.append(cells.map { $0 == "\u{2588}" || $0 == "\u{2584}" })
        }
        return result
    }
}
