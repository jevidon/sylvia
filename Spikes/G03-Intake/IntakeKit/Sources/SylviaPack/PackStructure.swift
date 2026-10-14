import Darwin
import Foundation
import SylviaIntakeCore

/// One archive entry as the central directory and its local header describe it, after cross-checking both.
public struct PackEntryRecord: Sendable, Equatable {
    public let index: Int
    public let name: String
    public let method: UInt16
    public let flags: UInt16
    public let crc32: UInt32
    public let compressedSize: UInt64
    public let uncompressedSize: UInt64
    public let localHeaderOffset: UInt64
    public let dataOffset: UInt64
    public let unixMode: UInt32?
}

/// Strict structural parse of a .sylviapack v1 archive, done with bounded reads before any archive library
/// sees the file (ADR-0010). A v1 pack is written in one pass by Sylvia's writer, so its layout is exact:
///
///   [local header + data] x N, central directory, ZIP64 end record + locator (when needed), end record
///
/// with no gaps, no overlap, no archive comment and the end record in the last 22 bytes. That makes a
/// truncated or partially copied file detectable in constant time, where the evaluated libraries scan the
/// whole file backwards for an end-record signature and can mistake payload bytes for one.
public struct PackStructure: Sendable {
    public let fileSize: UInt64
    public let entries: [PackEntryRecord]
    public let centralDirectoryOffset: UInt64
    public let centralDirectorySize: UInt64
    public let usesZIP64EndRecord: Bool

    static let localHeaderSignature: UInt32 = 0x0403_4B50
    static let centralHeaderSignature: UInt32 = 0x0201_4B50
    static let endSignature: UInt32 = 0x0605_4B50
    static let zip64EndSignature: UInt32 = 0x0606_4B50
    static let zip64LocatorSignature: UInt32 = 0x0706_4B50
    static let endRecordSize: UInt64 = 22
    static let zip64LocatorSize: UInt64 = 20
    static let zip64EndRecordFixedSize: UInt64 = 56
    static let centralHeaderSize = 46
    static let localHeaderSize = 30

    /// General-purpose flags a v1 pack may use: only bit 11 (UTF-8 names).
    static let allowedFlags: UInt16 = 0x0800

    public static func parse(fd: Int32, fileSize: UInt64, limits: PackLimits) throws(PackRejection) -> PackStructure {
        do {
            return try parseUnchecked(fd: fd, fileSize: fileSize, limits: limits)
        } catch let rejection as PackRejection {
            throw rejection
        } catch {
            throw PackRejection(.ioError, String(describing: error))
        }
    }

    private static func parseUnchecked(fd: Int32, fileSize: UInt64, limits: PackLimits) throws -> PackStructure {
        guard fileSize >= endRecordSize else { throw PackRejection(.truncated, "shorter than an end record") }

        // 1. End record: exactly the last 22 bytes, no comment.
        let endOffset = fileSize - endRecordSize
        let end = ByteReader(try Durability.readExactly(fd: fd, count: Int(endRecordSize), at: endOffset))
        guard end.u32(0) == endSignature else {
            // Distinguish an archive comment (end record followed by exactly its comment) from a truncated or
            // foreign file, with one bounded read of the largest possible comment span.
            let span = min(fileSize, endRecordSize + 0xFFFF)
            let tail = try Durability.readExactly(fd: fd, count: Int(span), at: fileSize - span)
            let signature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
            let hasCommentedEnd: Bool = tail.withUnsafeBytes { raw in
                var start = 0
                while start + Int(endRecordSize) <= raw.count {
                    guard let hit = memmem(raw.baseAddress! + start, raw.count - start, signature, 4) else { return false }
                    let p = raw.baseAddress!.distance(to: hit)
                    if p + Int(endRecordSize) <= raw.count,
                       Int(UInt16(raw[p + 20]) | UInt16(raw[p + 21]) << 8) == raw.count - p - Int(endRecordSize) {
                        return true
                    }
                    start = p + 1
                }
                return false
            }
            if hasCommentedEnd { throw PackRejection(.archiveComment) }
            throw PackRejection(.truncated, "no end record at the end of the file")
        }
        guard end.u16(20) == 0 else { throw PackRejection(.archiveComment) }
        guard end.u16(4) == 0, end.u16(6) == 0, end.u16(8) == end.u16(10) else { throw PackRejection(.multiDisk) }
        var entryCount = UInt64(end.u16(10))
        var cdSize = UInt64(end.u32(12))
        var cdOffset = UInt64(end.u32(16))
        var cdEnd = endOffset   // where the central directory must end
        var usesZIP64 = false

        // 2. ZIP64 locator and record, directly before the end record, when present.
        if endOffset >= zip64LocatorSize + zip64EndRecordFixedSize {
            let locatorOffset = endOffset - zip64LocatorSize
            let locator = ByteReader(try Durability.readExactly(fd: fd, count: Int(zip64LocatorSize), at: locatorOffset))
            if locator.u32(0) == zip64LocatorSignature {
                guard locator.u32(4) == 0, locator.u32(16) == 1 else { throw PackRejection(.multiDisk) }
                let recordOffset = locator.u64(8)
                guard recordOffset <= locatorOffset - zip64EndRecordFixedSize else {
                    throw PackRejection(.malformedStructure, "ZIP64 end record offset")
                }
                let record = ByteReader(try Durability.readExactly(fd: fd, count: Int(zip64EndRecordFixedSize), at: recordOffset))
                guard record.u32(0) == zip64EndSignature else { throw PackRejection(.malformedStructure, "ZIP64 end record signature") }
                // Size of the remaining record; v1 packs carry no extensible data sector.
                guard record.u64(4) == zip64EndRecordFixedSize - 12 else {
                    throw PackRejection(.unsupportedFeature, "ZIP64 extensible data")
                }
                guard recordOffset + zip64EndRecordFixedSize == locatorOffset else {
                    throw PackRejection(.layoutGap, "bytes between ZIP64 end record and locator")
                }
                guard record.u32(16) == 0, record.u32(20) == 0, record.u64(24) == record.u64(32) else {
                    throw PackRejection(.multiDisk)
                }
                let count64 = record.u64(32)
                let size64 = record.u64(40)
                let offset64 = record.u64(48)
                // Each 32-bit field must either agree with the ZIP64 value or be the 0xFFFF... escape.
                guard entryCount == 0xFFFF || entryCount == count64,
                      cdSize == 0xFFFF_FFFF || cdSize == size64,
                      cdOffset == 0xFFFF_FFFF || cdOffset == offset64 else {
                    throw PackRejection(.malformedStructure, "end record disagrees with ZIP64 end record")
                }
                entryCount = count64
                cdSize = size64
                cdOffset = offset64
                cdEnd = recordOffset
                usesZIP64 = true
            }
        }
        if !usesZIP64, entryCount == 0xFFFF || cdSize == 0xFFFF_FFFF || cdOffset == 0xFFFF_FFFF {
            throw PackRejection(.truncated, "ZIP64 escape values without a ZIP64 end record")
        }

        // 3. Bounds before reading the central directory.
        guard entryCount <= UInt64(limits.maxEntries) else {
            throw PackRejection(.tooManyEntries, "\(entryCount) entries; limit \(limits.maxEntries)")
        }
        guard cdSize <= UInt64(limits.maxCentralDirectoryBytes) else { throw PackRejection(.centralDirectoryTooLarge) }
        let (cdLimit, overflow) = cdOffset.addingReportingOverflow(cdSize)
        guard !overflow, cdLimit == cdEnd else {
            throw PackRejection(.layoutGap, "central directory does not end where the end records begin")
        }

        // 4. Central directory records.
        let cd = ByteReader(try Durability.readExactly(fd: fd, count: Int(cdSize), at: cdOffset))
        var entries: [PackEntryRecord] = []
        entries.reserveCapacity(Int(entryCount))
        var cursor = 0
        for index in 0..<Int(entryCount) {
            guard cursor + centralHeaderSize <= cd.count else { throw PackRejection(.malformedStructure, "central directory too short") }
            guard cd.u32(cursor) == centralHeaderSignature else { throw PackRejection(.malformedStructure, "central header signature") }
            let versionMadeBy = cd.u16(cursor + 4)
            let versionNeeded = cd.u16(cursor + 6)
            let flags = cd.u16(cursor + 8)
            let method = cd.u16(cursor + 10)
            let crc = cd.u32(cursor + 16)
            var compressed = UInt64(cd.u32(cursor + 20))
            var uncompressed = UInt64(cd.u32(cursor + 24))
            let nameLength = Int(cd.u16(cursor + 28))
            let extraLength = Int(cd.u16(cursor + 30))
            let commentLength = Int(cd.u16(cursor + 32))
            let diskStart = cd.u16(cursor + 34)
            let externalAttributes = cd.u32(cursor + 38)
            var localOffset = UInt64(cd.u32(cursor + 42))
            let variableStart = cursor + centralHeaderSize
            guard variableStart + nameLength + extraLength + commentLength <= cd.count else {
                throw PackRejection(.malformedStructure, "central header overruns the directory")
            }
            let nameBytes = cd.slice(variableStart, nameLength)
            let extra = cd.slice(variableStart + nameLength, extraLength)
            guard commentLength == 0 else { throw PackRejection(.unsupportedFeature, "entry comment") }

            if flags & 0x0001 != 0 || flags & 0x0040 != 0 || flags & 0x2000 != 0 { throw PackRejection(.encryptedEntry) }
            guard flags & ~allowedFlags == 0 else {
                throw PackRejection(.unsupportedFeature, "general-purpose flags 0x\(String(flags, radix: 16))")
            }
            guard versionNeeded <= 45 else { throw PackRejection(.unsupportedFeature, "version needed \(versionNeeded)") }
            guard method == 0 || method == 8 else { throw PackRejection(.unsupportedCompression, "method \(method)") }

            // ZIP64 extended information: present fields follow the escape values, in order.
            let zip64 = try zip64Fields(extra: extra,
                                        needUncompressed: uncompressed == 0xFFFF_FFFF,
                                        needCompressed: compressed == 0xFFFF_FFFF,
                                        needOffset: localOffset == 0xFFFF_FFFF,
                                        needDisk: diskStart == 0xFFFF)
            if let value = zip64.uncompressed { uncompressed = value }
            if let value = zip64.compressed { compressed = value }
            if let value = zip64.offset { localOffset = value }
            guard (zip64.disk ?? UInt32(diskStart)) == 0 else { throw PackRejection(.multiDisk) }

            let name = try decodeName(nameBytes, utf8Flag: flags & 0x0800 != 0)
            let mode = try checkEntryType(versionMadeBy: versionMadeBy, externalAttributes: externalAttributes, name: name)
            if method == 0, compressed != uncompressed {
                throw PackRejection(.storedSizeMismatch, "entry \(index)")
            }

            entries.append(PackEntryRecord(
                index: index, name: name, method: method, flags: flags, crc32: crc,
                compressedSize: compressed, uncompressedSize: uncompressed,
                localHeaderOffset: localOffset, dataOffset: 0, unixMode: mode))
            cursor = variableStart + nameLength + extraLength + commentLength
        }
        guard cursor == cd.count else { throw PackRejection(.layoutGap, "bytes after the last central header") }

        // 5. Local headers: identical to the central directory, laid out back to back from offset 0.
        var expectedOffset: UInt64 = 0
        var checked: [PackEntryRecord] = []
        checked.reserveCapacity(entries.count)
        for entry in entries {
            guard entry.localHeaderOffset == expectedOffset else {
                throw PackRejection(.layoutGap, "entry \(entry.index) does not start where the previous one ends")
            }
            guard entry.localHeaderOffset + UInt64(localHeaderSize) <= cdOffset else {
                throw PackRejection(.malformedStructure, "local header beyond the central directory")
            }
            let fixed = ByteReader(try Durability.readExactly(fd: fd, count: localHeaderSize, at: entry.localHeaderOffset))
            guard fixed.u32(0) == localHeaderSignature else { throw PackRejection(.malformedStructure, "local header signature") }
            let nameLength = Int(fixed.u16(26))
            let extraLength = Int(fixed.u16(28))
            let variable = ByteReader(try Durability.readExactly(fd: fd, count: nameLength + extraLength,
                                                                 at: entry.localHeaderOffset + UInt64(localHeaderSize)))
            guard fixed.u16(6) == entry.flags, fixed.u16(8) == entry.method, fixed.u32(14) == entry.crc32 else {
                throw PackRejection(.localHeaderMismatch, "entry \(entry.index) flags, method or CRC")
            }
            // Byte comparison: String == would accept a canonically equivalent but different name.
            guard variable.slice(0, nameLength).array == Array(entry.name.utf8) else {
                throw PackRejection(.localHeaderMismatch, "entry \(entry.index) name")
            }
            var localCompressed = UInt64(fixed.u32(18))
            var localUncompressed = UInt64(fixed.u32(22))
            if localCompressed == 0xFFFF_FFFF || localUncompressed == 0xFFFF_FFFF {
                // The local ZIP64 field must carry both sizes.
                let z = try zip64Fields(extra: variable.slice(nameLength, extraLength),
                                        needUncompressed: true, needCompressed: true, needOffset: false, needDisk: false)
                localUncompressed = z.uncompressed ?? 0
                localCompressed = z.compressed ?? 0
            } else {
                try checkExtraWellFormed(variable.slice(nameLength, extraLength))
            }
            guard localCompressed == entry.compressedSize, localUncompressed == entry.uncompressedSize else {
                throw PackRejection(.localHeaderMismatch, "entry \(entry.index) sizes")
            }
            let dataOffset = entry.localHeaderOffset + UInt64(localHeaderSize) + UInt64(nameLength + extraLength)
            let (dataEnd, overflow) = dataOffset.addingReportingOverflow(entry.compressedSize)
            guard !overflow, dataEnd <= cdOffset else {
                throw PackRejection(.malformedStructure, "entry \(entry.index) data runs past the central directory")
            }
            checked.append(PackEntryRecord(
                index: entry.index, name: entry.name, method: entry.method, flags: entry.flags, crc32: entry.crc32,
                compressedSize: entry.compressedSize, uncompressedSize: entry.uncompressedSize,
                localHeaderOffset: entry.localHeaderOffset, dataOffset: dataOffset, unixMode: entry.unixMode))
            expectedOffset = dataEnd
        }
        guard expectedOffset == cdOffset else {
            throw PackRejection(.layoutGap, "bytes between the last entry and the central directory")
        }
        return PackStructure(fileSize: fileSize, entries: checked, centralDirectoryOffset: cdOffset,
                             centralDirectorySize: cdSize, usesZIP64EndRecord: usesZIP64)
    }

    struct ZIP64Values {
        var uncompressed: UInt64?
        var compressed: UInt64?
        var offset: UInt64?
        var disk: UInt32?
    }

    /// Parses the extra-field list (must be well formed) and the ZIP64 field's present values.
    static func zip64Fields(extra: ByteReader, needUncompressed: Bool, needCompressed: Bool,
                            needOffset: Bool, needDisk: Bool) throws -> ZIP64Values {
        var values = ZIP64Values()
        var found = false
        var cursor = 0
        while cursor < extra.count {
            guard cursor + 4 <= extra.count else { throw PackRejection(.malformedStructure, "extra field header") }
            let id = extra.u16(cursor)
            let size = Int(extra.u16(cursor + 2))
            guard cursor + 4 + size <= extra.count else { throw PackRejection(.malformedStructure, "extra field length") }
            if id == 0x0001 {
                guard !found else { throw PackRejection(.malformedStructure, "two ZIP64 fields") }
                found = true
                var p = cursor + 4
                let end = p + size
                func take8() throws -> UInt64 {
                    guard p + 8 <= end else { throw PackRejection(.malformedStructure, "ZIP64 field too short") }
                    defer { p += 8 }
                    return extra.u64(p)
                }
                if needUncompressed { values.uncompressed = try take8() }
                if needCompressed { values.compressed = try take8() }
                if needOffset { values.offset = try take8() }
                if needDisk {
                    guard p + 4 <= end else { throw PackRejection(.malformedStructure, "ZIP64 field too short") }
                    values.disk = extra.u32(p)
                    p += 4
                }
                guard p == end else { throw PackRejection(.malformedStructure, "ZIP64 field has unexpected values") }
            }
            cursor += 4 + size
        }
        if (needUncompressed || needCompressed || needOffset || needDisk) && !found {
            throw PackRejection(.malformedStructure, "ZIP64 escape value without a ZIP64 field")
        }
        return values
    }

    static func checkExtraWellFormed(_ extra: ByteReader) throws {
        _ = try zip64Fields(extra: extra, needUncompressed: false, needCompressed: false, needOffset: false, needDisk: false)
    }

    static func decodeName(_ bytes: ByteReader, utf8Flag: Bool) throws -> String {
        let raw = bytes.array
        if !utf8Flag, raw.contains(where: { $0 >= 0x80 }) {
            throw PackRejection(.unsafePath, "non-ASCII name without the UTF-8 flag")
        }
        guard let name = String(validating: raw, as: UTF8.self) else {
            throw PackRejection(.unsafePath, "name is not valid UTF-8")
        }
        return name
    }

    /// Only regular, non-executable files. Returns the Unix mode when the entry carries one.
    static func checkEntryType(versionMadeBy: UInt16, externalAttributes: UInt32, name: String) throws -> UInt32? {
        // The last byte, not the last Character: after a prepended mark (U+0600) a final "/" is part of a Character
        // that is not "/" (report finding F18).
        if PathBytes.endsWithSeparator(name) { throw PackRejection(.specialEntry, "directory entry") }
        let host = versionMadeBy >> 8
        switch host {
        case 3, 19:  // Unix, OS X: st_mode in the high 16 bits
            let mode = externalAttributes >> 16
            let type = mode & 0o170000
            guard type == 0o100000 || type == 0 else {
                throw PackRejection(.specialEntry, type == 0o120000 ? "symbolic link" : type == 0o040000 ? "directory" : "device, FIFO or socket")
            }
            guard mode & 0o7111 == 0 else { throw PackRejection(.executableEntry) }
            if externalAttributes & 0x10 != 0 { throw PackRejection(.specialEntry, "directory attribute") }
            return mode
        case 0:      // MS-DOS attributes only
            if externalAttributes & 0x10 != 0 { throw PackRejection(.specialEntry, "directory attribute") }
            return nil
        default:
            throw PackRejection(.unsupportedFeature, "entry made by host \(host)")
        }
    }
}

/// Little-endian reads from a byte array.
struct ByteReader: Sendable {
    let array: [UInt8]
    let base: Int
    let count: Int

    init(_ array: [UInt8]) {
        self.array = array
        self.base = 0
        self.count = array.count
    }

    private init(array: [UInt8], base: Int, count: Int) {
        self.array = Array(array[base..<(base + count)])
        self.base = 0
        self.count = count
    }

    func u16(_ at: Int) -> UInt16 { UInt16(array[at]) | UInt16(array[at + 1]) << 8 }
    func u32(_ at: Int) -> UInt32 { UInt32(u16(at)) | UInt32(u16(at + 2)) << 16 }
    func u64(_ at: Int) -> UInt64 { UInt64(u32(at)) | UInt64(u32(at + 4)) << 32 }
    func slice(_ at: Int, _ length: Int) -> ByteReader { ByteReader(array: array, base: at, count: length) }
}
