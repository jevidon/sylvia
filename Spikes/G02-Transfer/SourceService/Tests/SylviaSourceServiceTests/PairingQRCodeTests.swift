import CoreGraphics
import Foundation
import Testing
import Vision
@_spi(Testing) import SylviaSourceService
import SylviaTransferCore

/// The pairing QR code that `sylvia-source --qr` draws on its terminal (gate gap from the round 3 review: the brief
/// makes the QR optional, and the source printed only the code and link). Environment: host (macOS). The drawing
/// is read back into modules, rendered as an image and decoded with Apple's Vision barcode reader, which must
/// return exactly the pairing link. The log records sizes only, never a link or a secret.
@Suite("Pairing QR code drawn by the command-line source (plan 15.2)", .serialized)
struct PairingQRCodeTests {
    static func payload(sourceName: String, endpoints: [PairingPayload.Endpoint], secretBytes: Int = 32) throws -> PairingPayload {
        PairingPayload(
            sourceID: CanonicalID.make(), sourceName: sourceName, endpoints: endpoints,
            spki: try SPKIPin(hex: String(repeating: "ab", count: 32)), invitationID: CanonicalID.make(),
            invitationSecret: (0..<secretBytes).map { _ in UInt8.random(in: 0...255) }, expiresAt: Date().addingTimeInterval(600))
    }

    /// A valid DNS name of exactly 253 characters (the longest `HostValidation` accepts): four labels of 63, 63, 63
    /// and 61 characters.
    static func longestHostName(_ index: Int) -> String {
        let first = "h\(index)" + String(repeating: "a", count: 61)
        return [first, String(repeating: "b", count: 63), String(repeating: "c", count: 63), String(repeating: "d", count: 61)]
            .joined(separator: ".")
    }

    /// Bytes a QR code holds at error-correction level L in byte mode (version 40, ISO/IEC 18004 Table 7).
    static let qrByteCapacityAtLevelL = 2_953

    /// Modules as a grey image, `scale` pixels per module, dark modules black.
    static func image(_ modules: [[Bool]], scale: Int = 8) throws -> CGImage {
        let size = modules.count * scale
        var pixels = [UInt8](repeating: 255, count: size * size)
        for (row, line) in modules.enumerated() {
            for (column, dark) in line.enumerated() where dark {
                for y in row * scale..<(row + 1) * scale {
                    for x in column * scale..<(column + 1) * scale { pixels[y * size + x] = 0 }
                }
            }
        }
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        return try #require(CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    static func decode(_ image: CGImage) async throws -> [String] {
        var request = DetectBarcodesRequest()
        request.symbologies = [.qr]
        let observations = try await request.perform(on: image)
        return observations.compactMap(\.payloadString)
    }

    /// Draws `link`, reads the drawing back and decodes it. Returns the log line.
    static func checkDrawing(of link: String, label: String) async throws -> String {
        let modules = try PairingQRCode.modules(for: link)
        let expected = PairingQRCode.withQuietZone(modules)
        let lines = try PairingQRCode.terminalLines(for: link)
        var drawn = PairingQRCode.modules(fromTerminalLines: lines)
        // Two module rows per line: an odd symbol (every QR version is odd) gets one light row of padding.
        #expect(drawn.count == expected.count + expected.count % 2)
        if drawn.count > expected.count {
            #expect(drawn.last?.allSatisfy { !$0 } == true, "the padding row has a dark module")
            drawn.removeLast()
        }
        #expect(drawn == expected, "\(label): the terminal drawing differs from the symbol")
        let decoded = try await decode(try image(drawn))
        #expect(decoded == [link], "\(label): decoded \(decoded.count) code(s), equal to the link: \(decoded == [link])")
        let columns = try PairingQRCode.columns(for: link)
        #expect(columns == expected.count)
        return "\(label): link \(link.count) characters; symbol \(modules.count)x\(modules.count) modules (level \(PairingQRCode.correctionLevel)); terminal \(columns) columns x \(lines.count) lines; quiet zone \(PairingQRCode.quietZone) modules; drawing read back equals the symbol: \(drawn == expected); Vision decoded the drawing to exactly the link: \(decoded == [link])"
    }

    @Test func pairingLinksDrawnOnTheTerminalDecodeToTheLinkAndOversizedTextIsRefused() async throws {
        let harness = try await Harness.make(files: ["a.bin": [1, 2, 3]])
        defer { await harness.cleanUp() }
        let real = try await harness.service.issueInvitation().link()
        var lines = [try await Self.checkDrawing(of: real, label: "invitation of the in-process source (one loopback endpoint)")]
        // What --lan --advertise-host gives on a Mac with Wi-Fi and Tailscale: four endpoints.
        let fourEndpoints = try Self.payload(sourceName: "Justin's MacBook Pro", endpoints: [
            .init(host: "192.168.20.104", port: 52_731), .init(host: "M5-Max-MBP.local", port: 52_731),
            .init(host: "100.104.83.3", port: 52_731), .init(host: "m5-max-mbp.tail0123ab.ts.net", port: 52_731),
        ]).link()
        lines.append(try await Self.checkDrawing(of: fourEndpoints, label: "four endpoints (LAN, .local, Tailscale, MagicDNS)"))
        // Eight endpoints with 71-character names and the longest source name still fit in a QR code. (Round 3
        // correction: this case was described as the largest payload the protocol allows; it is not, see below.)
        let endpoints = (0..<PairingPayload.maximumEndpoints).map { index in
            PairingPayload.Endpoint(host: "mac-\(index)-" + String(repeating: "n", count: 50) + ".example.ts.net", port: 65_535)
        }
        let long = try Self.payload(
            sourceName: String(repeating: "M", count: PairingPayload.maximumSourceNameLength), endpoints: endpoints
        ).link()
        lines.append(try await Self.checkDrawing(of: long, label: "eight endpoints with 71-character names and a 64-character source name"))
        // A payload at the protocol's limits (eight endpoints with 253-character names, a 64-character ASCII source name, a
        // 64-byte secret) is a valid pairing link, under the 4,096-character limit, but longer than a QR code holds at
        // level L. It is refused with tooLong, and the command-line source then prints the code and link only
        // ("qr: not drawn (tooLong); paste the code instead", SourceCommandLine.drawQRCode).
        let largestEndpoints = (0..<PairingPayload.maximumEndpoints).map { PairingPayload.Endpoint(host: Self.longestHostName($0), port: 65_535) }
        #expect(largestEndpoints.allSatisfy { $0.host.utf8.count == 253 && HostValidation.isValid($0.host) })
        let largest = try Self.payload(
            sourceName: String(repeating: "M", count: PairingPayload.maximumSourceNameLength), endpoints: largestEndpoints, secretBytes: 64
        ).link()
        let decodedLargest = try PairingPayload.decode(largest, now: Date())
        #expect(decodedLargest.endpoints == largestEndpoints, "the payload at the protocol's limits is not a valid pairing link")
        #expect(largest.utf8.count <= PairingPayload.maximumEncodedLength && largest.utf8.count > Self.qrByteCapacityAtLevelL)
        #expect(throws: PairingQRCode.Failure.tooLong) { try PairingQRCode.terminalLines(for: largest) }
        lines.append(
            "a payload at the protocol's limits (eight endpoints with 253-character names, a 64-character ASCII source name, a 64-byte secret): "
                + "link \(largest.count) characters, a valid pairing link (limit \(PairingPayload.maximumEncodedLength)) but more than the "
                + "\(Self.qrByteCapacityAtLevelL) bytes a QR code holds at level L: refused with tooLong, so the source prints the code and link and "
                + "\"qr: not drawn (tooLong); paste the code instead\"")
        // Any text beyond QR capacity is refused the same way.
        #expect(throws: PairingQRCode.Failure.tooLong) { try PairingQRCode.terminalLines(for: String(repeating: "a", count: 3_000)) }
        lines.append("3,000 characters (beyond QR capacity at level L): refused with tooLong")
        Evidence.write("cli-qr-code.log", ([
            "environment: host (macOS \(ProcessInfo.processInfo.operatingSystemVersionString)); PairingQRCodeTests (swift test)",
            "PairingQRCode draws the pairing link with half blocks, black on white; the drawing is read back into modules, rendered at 8 px per module and decoded with Vision (DetectBarcodesRequest, .qr)",
        ] + lines).joined(separator: "\n") + "\n")
    }
}
