import Compression
import Foundation

public enum ZipError: Error, Equatable, Sendable {
    case archiveTooLarge
    case notAZip
    case zip64Unsupported
    case entryNotFound(String)
    case unsafePath(String)
    case unsupportedCompression(UInt16)
    case entryTooLarge(String)
    case suspiciousCompressionRatio(String)
    case corrupt(String)
    case checksumMismatch(String)
}

/// A minimal, bounded ZIP reader for the spike's own text extraction (no Readium; brief item 6).
/// Supports stored and deflated entries, verifies CRC-32, rejects unsafe paths, ZIP64, oversized entries and
/// suspicious compression ratios. Production EPUB handling goes through the reader adapter chosen in G0.1.
public struct ZipReader: Sendable {
    public struct Entry: Sendable {
        public let path: String
        let method: UInt16
        let crc32: UInt32
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    public static let maxArchiveBytes = 256 << 20
    public static let maxEntryBytes = 32 << 20
    public static let maxCompressionRatio = 200

    let data: Data
    public let entries: [String: Entry]

    public init(url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? Int, size > Self.maxArchiveBytes { throw ZipError.archiveTooLarge }
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    public init(data: Data) throws(ZipError) {
        guard data.count <= Self.maxArchiveBytes else { throw .archiveTooLarge }
        self.data = data
        // End of central directory: signature 0x06054b50 within the last 64 KiB + 22 bytes.
        let minEOCD = 22
        guard data.count >= minEOCD else { throw .notAZip }
        let searchStart = max(0, data.count - (65_535 + minEOCD))
        var eocd: Int?
        var offset = data.count - minEOCD
        while offset >= searchStart {
            if Self.u32(data, offset) == 0x0605_4B50 { eocd = offset; break }
            offset -= 1
        }
        guard let eocd else { throw .notAZip }
        let entryCount = Int(Self.u16(data, eocd + 10))
        let directorySize = Int(Self.u32(data, eocd + 12))
        let directoryOffset = Int(Self.u32(data, eocd + 16))
        if entryCount == 0xFFFF || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF { throw .zip64Unsupported }
        guard directoryOffset + directorySize <= eocd else { throw .corrupt("central directory out of range") }

        var entries: [String: Entry] = [:]
        var cursor = directoryOffset
        for _ in 0..<entryCount {
            guard cursor + 46 <= data.count, Self.u32(data, cursor) == 0x0201_4B50 else { throw .corrupt("bad central directory entry") }
            let flags = Self.u16(data, cursor + 8)
            if flags & 0x1 != 0 { throw .corrupt("encrypted entry") }
            let method = Self.u16(data, cursor + 10)
            let crc = Self.u32(data, cursor + 16)
            let compressed = Int(Self.u32(data, cursor + 20))
            let uncompressed = Int(Self.u32(data, cursor + 24))
            let nameLength = Int(Self.u16(data, cursor + 28))
            let extraLength = Int(Self.u16(data, cursor + 30))
            let commentLength = Int(Self.u16(data, cursor + 32))
            let localOffset = Int(Self.u32(data, cursor + 42))
            if compressed == 0xFFFF_FFFF || uncompressed == 0xFFFF_FFFF || localOffset == 0xFFFF_FFFF { throw .zip64Unsupported }
            guard cursor + 46 + nameLength <= data.count else { throw .corrupt("name out of range") }
            let name = String(decoding: data[(cursor + 46)..<(cursor + 46 + nameLength)], as: UTF8.self)
            cursor += 46 + nameLength + extraLength + commentLength
            if name.hasSuffix("/") { continue }
            guard Self.isSafe(name) else { throw .unsafePath(name) }
            entries[name] = Entry(path: name, method: method, crc32: crc, compressedSize: compressed,
                                  uncompressedSize: uncompressed, localHeaderOffset: localOffset)
        }
        self.entries = entries
    }

    static func isSafe(_ path: String) -> Bool {
        if path.isEmpty || path.hasPrefix("/") || path.contains("\\") || path.contains("\u{0}") { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }

    public func read(_ path: String) throws(ZipError) -> Data {
        guard let entry = entries[path] else { throw .entryNotFound(path) }
        guard entry.uncompressedSize <= Self.maxEntryBytes else { throw .entryTooLarge(path) }
        if entry.compressedSize > 0, entry.uncompressedSize / max(entry.compressedSize, 1) > Self.maxCompressionRatio {
            throw .suspiciousCompressionRatio(path)
        }
        let local = entry.localHeaderOffset
        guard local + 30 <= data.count, Self.u32(data, local) == 0x0403_4B50 else { throw .corrupt("bad local header for \(path)") }
        let start = local + 30 + Int(Self.u16(data, local + 26)) + Int(Self.u16(data, local + 28))
        guard start + entry.compressedSize <= data.count else { throw .corrupt("entry data out of range: \(path)") }
        let compressed = data.subdata(in: start..<(start + entry.compressedSize))
        let output: Data
        switch entry.method {
        case 0:
            output = compressed
        case 8:
            output = try Self.inflate(compressed, expected: entry.uncompressedSize, path: path)
        default:
            throw .unsupportedCompression(entry.method)
        }
        guard output.count == entry.uncompressedSize else { throw .corrupt("size mismatch: \(path)") }
        guard CRC32.checksum(output) == entry.crc32 else { throw .checksumMismatch(path) }
        return output
    }

    static func inflate(_ input: Data, expected: Int, path: String) throws(ZipError) -> Data {
        if expected == 0 { return Data() }
        var output = Data(count: expected)
        let written = output.withUnsafeMutableBytes { destination in
            input.withUnsafeBytes { source in
                // COMPRESSION_ZLIB decodes raw DEFLATE (RFC 1951), which is what ZIP method 8 stores.
                compression_decode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!, expected,
                                          source.bindMemory(to: UInt8.self).baseAddress!, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expected else { throw .corrupt("inflate produced \(written) of \(expected) bytes: \(path)") }
        return output
    }

    static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[data.startIndex + offset]) | UInt16(data[data.startIndex + offset + 1]) << 8
    }

    static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(u16(data, offset)) | UInt32(u16(data, offset + 2)) << 16
    }
}

enum CRC32 {
    static let table: [UInt32] = (0..<256).map { index in
        var c = UInt32(index)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}
