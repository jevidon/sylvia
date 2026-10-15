import Foundation

/// Limits applied before any EPUB byte is decompressed (plan 8.3). Values are the plan's proposed release
/// defaults where it names one; the others are spike proposals recorded in ADR-0004.
public struct ZIPPreflightPolicy: Sendable, Equatable {
    /// Plan 8.3: 10,000 archive entries.
    public var maxEntries: Int = 10_000
    /// Plan 8.3: 1 GiB EPUB expanded content (sum of declared uncompressed sizes).
    public var maxTotalUncompressedBytes: UInt64 = 1 << 30
    /// Spike proposal: no single entry above 256 MiB.
    public var maxEntryUncompressedBytes: UInt64 = 256 << 20
    /// Spike proposal: deflated entries larger than `ratioCheckMinimumBytes` may not expand more than 100:1.
    /// The compatibility matrix records the ratios seen in real fixtures.
    public var maxCompressionRatio: Double = 100
    public var ratioCheckMinimumBytes: UInt64 = 1 << 20
    /// Spike proposal: a markup or style entry (XHTML, HTML, XML, OPF, NCX, CSS, SVG, SMIL) expands to at most 16 MiB.
    /// Readium 3.11.0 reads a whole entry into one buffer when it serves or parses it (SafetyTests: the 200 MiB
    /// chapter of g01-bomb.epub came back as a single 200 MiB read), so this bounds the memory one chapter can take.
    /// The largest markup entry in the real fixtures is under 1 MiB (ZIPPreflightTests output).
    public var maxMarkupEntryBytes: UInt64 = 16 << 20
    /// Spike proposal: entry names are at most 1,024 bytes.
    public var maxNameBytes: Int = 1024

    public init() {}
}

public struct ZIPEntryInfo: Sendable, Equatable, Codable {
    public var name: String
    public var method: UInt16
    public var flags: UInt16
    public var crc32: UInt32
    public var compressedSize: UInt64
    public var uncompressedSize: UInt64
    public var localHeaderOffset: UInt64
    public var versionMadeBy: UInt16
    public var externalAttributes: UInt32

    /// True when the entry was written on a Unix host with a symbolic-link file mode.
    public var isSymlink: Bool {
        (versionMadeBy >> 8) == 3 && ((externalAttributes >> 16) & 0o170000) == 0o120000
    }

    public var isDirectory: Bool { name.hasSuffix("/") }

    static let markupExtensions: Set<String> = ["xhtml", "html", "htm", "xml", "opf", "ncx", "css", "svg", "smil"]

    /// Markup and style entries, by extension (what Readium parses or serves to the web view as a document).
    public var isMarkup: Bool {
        guard let dot = name.lastIndex(of: ".") else { return false }
        return Self.markupExtensions.contains(name[name.index(after: dot)...].lowercased())
    }
}

public enum ZIPPreflightViolation: Sendable, Equatable, Codable, CustomStringConvertible {
    case notAZIP(String)
    case truncated(String)
    case tooManyEntries(Int)
    case invalidName(String)
    case pathTraversal(String)
    case absolutePath(String)
    case symlink(String)
    case duplicateName(String)
    case zipLevelEncryption(String)
    case unsupportedCompression(String, method: UInt16)
    case inconsistentSizes(String, compressed: UInt64, uncompressed: UInt64)
    case entryTooLarge(String, bytes: UInt64)
    case markupTooLarge(String, bytes: UInt64)
    case totalTooLarge(bytes: UInt64)
    case compressionRatio(String, ratio: Double)
    case localHeaderMismatch(String)

    public var description: String {
        switch self {
        case let .notAZIP(r): "not a ZIP archive: \(r)"
        case let .truncated(r): "truncated archive: \(r)"
        case let .tooManyEntries(n): "too many entries: \(n)"
        case let .invalidName(n): "invalid entry name: \(n.debugDescription)"
        case let .pathTraversal(n): "path traversal: \(n)"
        case let .absolutePath(n): "absolute path: \(n)"
        case let .symlink(n): "symbolic link entry: \(n)"
        case let .duplicateName(n): "duplicate entry: \(n)"
        case let .zipLevelEncryption(n): "ZIP-level encrypted entry: \(n)"
        case let .unsupportedCompression(n, m): "unsupported compression \(m): \(n)"
        case let .inconsistentSizes(n, c, u): "declared sizes inconsistent (compressed \(c) > uncompressed \(u)): \(n)"
        case let .entryTooLarge(n, b): "entry expands to \(b) bytes: \(n)"
        case let .markupTooLarge(n, b): "markup entry expands to \(b) bytes: \(n)"
        case let .totalTooLarge(b): "archive expands to \(b) bytes"
        case let .compressionRatio(n, r): "compression ratio \(Int(r)):1: \(n)"
        case let .localHeaderMismatch(n): "local header does not match central directory: \(n)"
        }
    }

    /// Stable machine-readable code for logs and the import state machine (plan 8.2 `unsupported`).
    public var code: String {
        switch self {
        case .notAZIP: "not_zip"
        case .truncated: "truncated"
        case .tooManyEntries: "too_many_entries"
        case .invalidName: "invalid_name"
        case .pathTraversal: "path_traversal"
        case .absolutePath: "absolute_path"
        case .symlink: "symlink"
        case .duplicateName: "duplicate_name"
        case .zipLevelEncryption: "zip_encryption"
        case .unsupportedCompression: "unsupported_compression"
        case .inconsistentSizes: "inconsistent_sizes"
        case .entryTooLarge: "entry_too_large"
        case .markupTooLarge: "markup_too_large"
        case .totalTooLarge: "total_too_large"
        case .compressionRatio: "compression_ratio"
        case .localHeaderMismatch: "local_header_mismatch"
        }
    }
}

public struct ZIPPreflightReport: Sendable, Equatable, Codable {
    public var entries: [ZIPEntryInfo]
    public var violations: [ZIPPreflightViolation]
    public var totalUncompressedBytes: UInt64
    public var isAcceptable: Bool { violations.isEmpty }
}

/// Reads only the ZIP central directory (and checks each local header signature) without decompressing anything.
/// Pure Foundation so it runs on the host and on device; it is the adapter's first gate before Readium sees a file.
public enum ZIPPreflight {
    public static func inspect(fileAt url: URL, policy: ZIPPreflightPolicy = .init()) -> ZIPPreflightReport {
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            return inspect(data: data, policy: policy)
        } catch {
            return ZIPPreflightReport(entries: [], violations: [.notAZIP("unreadable: \(error.localizedDescription)")], totalUncompressedBytes: 0)
        }
    }

    public static func inspect(data: Data, policy: ZIPPreflightPolicy = .init()) -> ZIPPreflightReport {
        var violations: [ZIPPreflightViolation] = []
        let parsed: [ZIPEntryInfo]
        do {
            parsed = try readCentralDirectory(data, maxEntries: policy.maxEntries)
        } catch let failure as PreflightFailure {
            return ZIPPreflightReport(entries: [], violations: [failure.violation], totalUncompressedBytes: 0)
        } catch {
            return ZIPPreflightReport(entries: [], violations: [.notAZIP("\(error)")], totalUncompressedBytes: 0)
        }

        var seen = Set<String>()
        var total: UInt64 = 0
        for entry in parsed {
            let name = entry.name
            if let problem = nameProblem(name, maxBytes: policy.maxNameBytes) { violations.append(problem) }
            if !seen.insert(name).inserted { violations.append(.duplicateName(name)) }
            if entry.isSymlink { violations.append(.symlink(name)) }
            if entry.flags & 0x0001 != 0 { violations.append(.zipLevelEncryption(name)) }
            switch entry.method {
            case 0:
                if entry.compressedSize != entry.uncompressedSize {
                    violations.append(.inconsistentSizes(name, compressed: entry.compressedSize, uncompressed: entry.uncompressedSize))
                }
            case 8:
                // Deflate's worst case is stored blocks: 5 bytes of overhead per 65,535 input bytes, plus a few bytes.
                let slack = max(UInt64(64), entry.uncompressedSize / 100)
                if entry.compressedSize > entry.uncompressedSize + slack {
                    violations.append(.inconsistentSizes(name, compressed: entry.compressedSize, uncompressed: entry.uncompressedSize))
                }
                if entry.uncompressedSize >= policy.ratioCheckMinimumBytes {
                    let ratio = Double(entry.uncompressedSize) / Double(max(entry.compressedSize, 1))
                    if ratio > policy.maxCompressionRatio { violations.append(.compressionRatio(name, ratio: ratio)) }
                }
            default:
                violations.append(.unsupportedCompression(name, method: entry.method))
            }
            if entry.uncompressedSize > policy.maxEntryUncompressedBytes {
                violations.append(.entryTooLarge(name, bytes: entry.uncompressedSize))
            }
            if entry.isMarkup, entry.uncompressedSize > policy.maxMarkupEntryBytes {
                violations.append(.markupTooLarge(name, bytes: entry.uncompressedSize))
            }
            let (sum, overflow) = total.addingReportingOverflow(entry.uncompressedSize)
            total = overflow ? .max : sum
            if !localHeaderMatches(entry, in: data) { violations.append(.localHeaderMismatch(name)) }
        }
        if total > policy.maxTotalUncompressedBytes { violations.append(.totalTooLarge(bytes: total)) }
        return ZIPPreflightReport(entries: parsed, violations: violations, totalUncompressedBytes: total)
    }

    // MARK: - Names

    static func nameProblem(_ name: String, maxBytes: Int) -> ZIPPreflightViolation? {
        if name.isEmpty || name.utf8.count > maxBytes { return .invalidName(name) }
        if name.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) { return .invalidName(name) }
        if name.hasPrefix("/") { return .absolutePath(name) }
        if name.contains("\\") { return .invalidName(name) }
        if name.count >= 2, name.dropFirst().first == ":" { return .absolutePath(name) }
        let segments = name.split(separator: "/", omittingEmptySubsequences: false)
        if segments.contains(where: { $0 == ".." }) { return .pathTraversal(name) }
        return nil
    }

    // MARK: - Central directory

    struct PreflightFailure: Error { let violation: ZIPPreflightViolation }

    private static func readCentralDirectory(_ data: Data, maxEntries: Int) throws -> [ZIPEntryInfo] {
        let reader = ByteReader(data)
        guard data.count >= 22 else { throw PreflightFailure(violation: .notAZIP("shorter than an end-of-central-directory record")) }
        // The EOCD record is in the last 22 + 65,535 bytes.
        let searchStart = max(0, data.count - 22 - 65_535)
        var eocd: Int?
        var i = data.count - 22
        while i >= searchStart {
            if reader.u32(i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard let eocdOffset = eocd else {
            if reader.u32(0) == 0x0403_4B50 {
                throw PreflightFailure(violation: .truncated("no end-of-central-directory record"))
            }
            throw PreflightFailure(violation: .notAZIP("no end-of-central-directory record"))
        }
        var entryCount = UInt64(reader.u16(eocdOffset + 10))
        var cdSize = UInt64(reader.u32(eocdOffset + 12))
        var cdOffset = UInt64(reader.u32(eocdOffset + 16))

        // ZIP64 end of central directory locator sits immediately before the EOCD.
        if entryCount == 0xFFFF || cdSize == 0xFFFF_FFFF || cdOffset == 0xFFFF_FFFF {
            let locator = eocdOffset - 20
            guard locator >= 0, reader.u32(locator) == 0x0706_4B50 else {
                throw PreflightFailure(violation: .truncated("ZIP64 locator missing"))
            }
            let z64 = reader.u64(locator + 8)
            guard z64 < UInt64(data.count), let z = Int(exactly: z64), reader.u32(z) == 0x0606_4B50 else {
                throw PreflightFailure(violation: .truncated("ZIP64 end record missing"))
            }
            entryCount = reader.u64(z + 32)
            cdSize = reader.u64(z + 40)
            cdOffset = reader.u64(z + 48)
        }
        if entryCount > UInt64(maxEntries) { throw PreflightFailure(violation: .tooManyEntries(Int(clamping: entryCount))) }
        guard cdOffset <= UInt64(data.count), cdSize <= UInt64(data.count) - cdOffset else {
            throw PreflightFailure(violation: .truncated("central directory lies outside the file"))
        }

        var entries: [ZIPEntryInfo] = []
        var p = Int(cdOffset)
        let end = Int(cdOffset + cdSize)
        for _ in 0 ..< entryCount {
            guard p + 46 <= end, reader.u32(p) == 0x0201_4B50 else {
                throw PreflightFailure(violation: .truncated("central directory entry \(entries.count) is damaged"))
            }
            let madeBy = reader.u16(p + 4)
            let flags = reader.u16(p + 8)
            let method = reader.u16(p + 10)
            let crc = reader.u32(p + 16)
            var compressed = UInt64(reader.u32(p + 20))
            var uncompressed = UInt64(reader.u32(p + 24))
            let nameLength = Int(reader.u16(p + 28))
            let extraLength = Int(reader.u16(p + 30))
            let commentLength = Int(reader.u16(p + 32))
            let external = reader.u32(p + 38)
            var localOffset = UInt64(reader.u32(p + 42))
            let nameStart = p + 46
            guard nameStart + nameLength + extraLength + commentLength <= end else {
                throw PreflightFailure(violation: .truncated("central directory entry \(entries.count) overruns"))
            }
            let nameBytes = data.subdata(in: nameStart ..< nameStart + nameLength)
            guard let name = String(data: nameBytes, encoding: .utf8) ?? String(data: nameBytes, encoding: .isoLatin1) else {
                throw PreflightFailure(violation: .invalidName("<undecodable>"))
            }
            // ZIP64 extended information extra field (0x0001) replaces the 0xFFFFFFFF placeholders in order.
            var e = nameStart + nameLength
            let extraEnd = e + extraLength
            while e + 4 <= extraEnd {
                let id = reader.u16(e)
                let size = Int(reader.u16(e + 2))
                if id == 0x0001 {
                    var q = e + 4
                    if uncompressed == 0xFFFF_FFFF, q + 8 <= e + 4 + size { uncompressed = reader.u64(q); q += 8 }
                    if compressed == 0xFFFF_FFFF, q + 8 <= e + 4 + size { compressed = reader.u64(q); q += 8 }
                    if localOffset == 0xFFFF_FFFF, q + 8 <= e + 4 + size { localOffset = reader.u64(q); q += 8 }
                }
                e += 4 + size
            }
            entries.append(ZIPEntryInfo(
                name: name, method: method, flags: flags, crc32: crc,
                compressedSize: compressed, uncompressedSize: uncompressed,
                localHeaderOffset: localOffset, versionMadeBy: madeBy, externalAttributes: external
            ))
            p = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    private static func localHeaderMatches(_ entry: ZIPEntryInfo, in data: Data) -> Bool {
        let reader = ByteReader(data)
        guard let o = Int(exactly: entry.localHeaderOffset), o + 30 <= data.count, reader.u32(o) == 0x0403_4B50 else {
            return false
        }
        let n = Int(reader.u16(o + 26))
        guard o + 30 + n <= data.count else { return false }
        let local = data.subdata(in: o + 30 ..< o + 30 + n)
        return local == Data(entry.name.utf8) || String(data: local, encoding: .isoLatin1) == entry.name
    }
}

/// Little-endian reads that return zero outside the buffer instead of trapping.
struct ByteReader {
    let data: Data
    init(_ data: Data) { self.data = data }

    func u8(_ i: Int) -> UInt8 {
        guard i >= 0, i < data.count else { return 0 }
        return data[data.startIndex + i]
    }

    func u16(_ i: Int) -> UInt16 { UInt16(u8(i)) | UInt16(u8(i + 1)) << 8 }
    func u32(_ i: Int) -> UInt32 { UInt32(u16(i)) | UInt32(u16(i + 2)) << 16 }
    func u64(_ i: Int) -> UInt64 { UInt64(u32(i)) | UInt64(u32(i + 4)) << 32 }
}
