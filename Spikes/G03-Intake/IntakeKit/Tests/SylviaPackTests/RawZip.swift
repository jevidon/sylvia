import Compression
import CryptoKit
import Foundation
@testable import SylviaPack
import SylviaIntakeCore

/// A deliberately permissive ZIP builder for hostile test archives: every header field can be set or forged.
/// It writes the plain (non-ZIP64) layout unless `forceZIP64` is set.
struct RawEntry {
    var name: String
    var data: Data
    var method: UInt16 = 0
    var flags: UInt16 = 0x0800
    var versionMadeBy: UInt16 = 0x0315          // Unix, 2.1 (what ZIPFoundation writes)
    var versionNeeded: UInt16 = 20
    var unixMode: UInt32 = 0o100644
    var externalOverride: UInt32?
    var crcOverride: UInt32?
    var uncompressedSizeOverride: UInt64?
    var compressedSizeOverride: UInt64?
    var localNameOverride: String?
    var compressedData: Data?                   // used when method == 8; computed from `data` if nil

    init(_ name: String, _ data: Data, method: UInt16 = 0) {
        self.name = name
        self.data = data
        self.method = method
    }
}

struct RawZip {
    var entries: [RawEntry] = []
    var comment = Data()
    var prefix = Data()            // bytes before the first local header (offsets are NOT adjusted)
    var gapAfterFirstEntry = 0     // filler bytes inserted after entry 0's data
    var trailing = Data()          // bytes after the end record
    var forceZIP64 = false
    var entryCountOverride: UInt64?

    func build() -> Data {
        var out = Data()
        out.append(prefix)
        var central = Data()
        var offsets: [UInt64] = []
        for (index, entry) in entries.enumerated() {
            let payload: Data = entry.method == 8 ? (entry.compressedData ?? RawZip.deflate(entry.data)) : entry.data
            let crc = entry.crcOverride ?? crc32(entry.data)
            let usize = entry.uncompressedSizeOverride ?? UInt64(entry.data.count)
            let csize = entry.compressedSizeOverride ?? UInt64(payload.count)
            let offset = UInt64(out.count - prefix.count)
            offsets.append(offset)
            let localName = Data((entry.localNameOverride ?? entry.name).utf8)
            var local = Data()
            local.le32(0x0403_4B50); local.le16(entry.versionNeeded); local.le16(entry.flags); local.le16(entry.method)
            local.le16(0); local.le16(0x21)   // DOS time and date
            local.le32(crc); local.le32(UInt32(csize)); local.le32(UInt32(usize))
            local.le16(UInt16(localName.count)); local.le16(0)
            local.append(localName)
            out.append(local)
            out.append(payload)
            if index == 0 && gapAfterFirstEntry > 0 { out.append(Data(repeating: 0xAB, count: gapAfterFirstEntry)) }

            let name = Data(entry.name.utf8)
            var cd = Data()
            cd.le32(0x0201_4B50); cd.le16(entry.versionMadeBy); cd.le16(entry.versionNeeded); cd.le16(entry.flags)
            cd.le16(entry.method); cd.le16(0); cd.le16(0x21)
            cd.le32(crc); cd.le32(UInt32(csize)); cd.le32(UInt32(usize))
            cd.le16(UInt16(name.count)); cd.le16(0); cd.le16(0); cd.le16(0); cd.le16(0)
            cd.le32(entry.externalOverride ?? (entry.unixMode << 16)); cd.le32(UInt32(offset))
            cd.append(name)
            central.append(cd)
        }
        let cdOffset = UInt64(out.count - prefix.count)
        out.append(central)
        let count = entryCountOverride ?? UInt64(entries.count)
        if forceZIP64 {
            let recordOffset = UInt64(out.count - prefix.count)
            var record = Data()
            record.le32(0x0606_4B50); record.le64(44); record.le16(0x0315); record.le16(45)
            record.le32(0); record.le32(0); record.le64(count); record.le64(count)
            record.le64(UInt64(central.count)); record.le64(cdOffset)
            out.append(record)
            var locator = Data()
            locator.le32(0x0706_4B50); locator.le32(0); locator.le64(recordOffset); locator.le32(1)
            out.append(locator)
        }
        var end = Data()
        end.le32(0x0605_4B50); end.le16(0); end.le16(0)
        end.le16(forceZIP64 ? 0xFFFF : UInt16(truncatingIfNeeded: count)); end.le16(forceZIP64 ? 0xFFFF : UInt16(truncatingIfNeeded: count))
        end.le32(forceZIP64 ? 0xFFFF_FFFF : UInt32(central.count)); end.le32(forceZIP64 ? 0xFFFF_FFFF : UInt32(cdOffset))
        end.le16(UInt16(comment.count))
        out.append(end)
        out.append(comment)
        out.append(trailing)
        return out
    }

    /// Raw DEFLATE (RFC 1951), as ZIP method 8 stores it.
    static func deflate(_ data: Data) -> Data {
        let capacity = data.count + 4096
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        precondition(written > 0, "deflate failed")
        return output.prefix(written)
    }
}

extension Data {
    mutating func le16(_ v: UInt16) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
    mutating func le32(_ v: UInt32) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
    mutating func le64(_ v: UInt64) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
}

/// Builds a manifest plus the two manifest entries for a set of content files.
struct PackFixture {
    var files: [(path: String, data: Data, kind: PackManifest.Kind, mediaType: String)]
    var groups: [PackManifest.Group] = []
    var groupOf: [String: (String, Int?)] = [:]

    func manifest() -> PackManifest {
        PackManifest(
            packID: UUID(uuidString: "6F1A0C2E-3B4D-4E5F-8A9B-0C1D2E3F4A5B")!,
            createdAt: Date(timeIntervalSince1970: 1_790_000_000),
            generator: .init(name: "raw test builder", version: "1"),
            files: files.map {
                PackManifest.File(path: $0.path, size: UInt64($0.data.count), sha256: hex(SHA256.hash(data: $0.data)),
                                  mediaType: $0.mediaType, kind: $0.kind,
                                  groupID: groupOf[$0.path]?.0, order: groupOf[$0.path]?.1)
            },
            groups: groups
        )
    }

    /// Manifest entries + content entries, all stored, in the v1 order.
    func rawZip(manifestOverride: Data? = nil) throws -> RawZip {
        let manifestBytes = try manifestOverride ?? manifest().encoded()
        let digest = Data((hex(SHA256.hash(data: manifestBytes)) + "\n").utf8)
        var zip = RawZip()
        zip.entries.append(RawEntry(PackLayout.manifestEntry, manifestBytes))
        zip.entries.append(RawEntry(PackLayout.manifestDigestEntry, digest))
        for file in files {
            let method: UInt16 = (file.kind == .text || file.kind == .markdown) ? 8 : 0
            zip.entries.append(RawEntry(PackLayout.contentPrefix + file.path, file.data, method: method))
        }
        return zip
    }

    static func standard() -> PackFixture {
        PackFixture(files: [
            ("Walden/notes.md", Data("# Walden\n\nTest notes for the G0.3 pack.\n".utf8), .markdown, "text/markdown"),
            ("Walden/chapter.txt", Data(String(repeating: "Simplify, simplify. ", count: 200).utf8), .text, "text/plain"),
            ("Meditations/part-01.caf", DeterministicBytes(seed: 7).data(offset: 0, count: 70_000), .audio, "audio/x-caf"),
            ("Meditations/part-02.caf", DeterministicBytes(seed: 8).data(offset: 0, count: 50_001), .audio, "audio/x-caf"),
        ], groups: [
            .init(groupID: "meditations", kind: .audiobook, title: "Meditations", creators: ["Marcus Aurelius"],
                  language: "en", memberOrderBasis: .filename),
        ], groupOf: [
            "Meditations/part-01.caf": ("meditations", 1),
            "Meditations/part-02.caf": ("meditations", 2),
        ])
    }
}
