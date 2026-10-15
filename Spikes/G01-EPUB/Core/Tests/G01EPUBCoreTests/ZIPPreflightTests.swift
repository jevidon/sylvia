import Foundation
@testable import G01EPUBCore
import Testing

/// Locations of the committed fixtures relative to this file.
enum FixturePaths {
    static let spikeRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let generated = spikeRoot.appendingPathComponent("Fixtures/generated")
    static let repoEPUB = spikeRoot.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/epub")

    static func generated(_ name: String) -> URL { generated.appendingPathComponent(name) }
}

/// Writes a STORED ZIP with arbitrary names, flags and attributes (test-only, for cases the generator does not cover).
struct StoredZipWriter {
    struct Entry { var name: String; var data: Data; var flags: UInt16 = 0; var external: UInt32 = 0o100644 << 16 }
    var entries: [Entry] = []

    func build() -> Data {
        var out = Data()
        var central = Data()
        func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        for e in entries {
            let name = Data(e.name.utf8)
            let crc = CRC32.checksum(e.data)
            let offset = UInt32(out.count)
            out += le32(0x0403_4B50) + le16(20) + le16(e.flags) + le16(0) + le16(0) + le16(0x21)
            out += le32(crc) + le32(UInt32(e.data.count)) + le32(UInt32(e.data.count)) + le16(UInt16(name.count)) + le16(0)
            out += name + e.data
            central += le32(0x0201_4B50) + le16(0x031E) + le16(20) + le16(e.flags) + le16(0) + le16(0) + le16(0x21)
            central += le32(crc) + le32(UInt32(e.data.count)) + le32(UInt32(e.data.count)) + le16(UInt16(name.count))
            central += le16(0) + le16(0) + le16(0) + le16(0) + le32(e.external) + le32(offset) + name
        }
        let cdOffset = UInt32(out.count)
        out += central
        out += le32(0x0605_4B50) + le16(0) + le16(0) + le16(UInt16(min(entries.count, 0xFFFF))) + le16(UInt16(min(entries.count, 0xFFFF)))
        out += le32(UInt32(central.count)) + le32(cdOffset) + le16(0)
        return out
    }
}

@Suite("ZIP preflight (plan 8.3)")
struct ZIPPreflightTests {
    @Test("Every committed real-world EPUB passes preflight", arguments: [
        "se-meditations.epub", "se-walden.epub", "se-middlemarch.epub", "pg-walden-epub2.epub", "pg-walden-epub3.epub",
    ])
    func realFixturesAccepted(name: String) throws {
        let report = ZIPPreflight.inspect(fileAt: FixturePaths.repoEPUB.appendingPathComponent(name))
        let maxRatio = report.entries.filter { $0.method == 8 && $0.compressedSize > 0 }
            .map { Double($0.uncompressedSize) / Double($0.compressedSize) }.max() ?? 0
        let largestMarkup = report.entries.filter(\.isMarkup).map(\.uncompressedSize).max() ?? 0
        print("PREFLIGHT \(name) entries=\(report.entries.count) expanded=\(report.totalUncompressedBytes) maxRatio=\(String(format: "%.1f", maxRatio)) largestMarkupBytes=\(largestMarkup) violations=\(report.violations.map(\.code))")
        #expect(largestMarkup < 1 << 20, "largest markup entry \(largestMarkup) bytes")
        #expect(report.isAcceptable, "\(report.violations)")
        #expect(report.entries.first?.name == "mimetype")
    }

    @Test("Archive-valid generated fixtures pass preflight", arguments: [
        "g01-unicode.epub", "g01-hostile.epub", "g01-font-obfuscated.epub", "g01-encrypted-chapter.epub",
        "g01-lcp-like.epub", "g01-adept-like.epub", "g01-deep-nesting.epub", "g01-nesting-limit.epub", "g01-nonhtml-active.epub",
    ])
    func generatedValidAccepted(name: String) {
        let report = ZIPPreflight.inspect(fileAt: FixturePaths.generated(name))
        print("PREFLIGHT \(name) entries=\(report.entries.count) violations=\(report.violations.map(\.code))")
        #expect(report.isAcceptable, "\(report.violations)")
    }

    @Test("Hostile archives are rejected with the expected reason", arguments: [
        ("g01-traversal.epub", ["path_traversal", "absolute_path"]),
        ("g01-symlink.epub", ["symlink"]),
        ("g01-bomb.epub", ["compression_ratio", "markup_too_large"]),
        ("g01-bomb-lying.epub", ["inconsistent_sizes"]),
        ("g01-truncated.epub", ["truncated"]),
    ])
    func hostileRejected(name: String, expected: [String]) {
        let report = ZIPPreflight.inspect(fileAt: FixturePaths.generated(name))
        let codes = Set(report.violations.map(\.code))
        print("PREFLIGHT \(name) violations=\(report.violations.map(\.description))")
        #expect(!report.isAcceptable)
        for code in expected { #expect(codes.contains(code), "missing \(code) in \(codes)") }
    }

    @Test("Entry-count limit (10,000) is enforced before entries are read")
    func tooManyEntries() {
        var w = StoredZipWriter()
        for i in 0 ..< 10_001 { w.entries.append(.init(name: "e\(i)", data: Data())) }
        let report = ZIPPreflight.inspect(data: w.build())
        #expect(report.violations == [.tooManyEntries(10_001)])
        #expect(report.entries.isEmpty)
    }

    @Test("Names: backslash, drive letter, control characters, duplicates, ZIP encryption flag")
    func nameAndFlagRules() {
        var w = StoredZipWriter()
        w.entries = [
            .init(name: "mimetype", data: Data("application/epub+zip".utf8)),
            .init(name: "OEBPS\\..\\evil.xhtml", data: Data()),
            .init(name: "C:/evil.xhtml", data: Data()),
            .init(name: "OEBPS/bad\u{0001}name", data: Data()),
            .init(name: "OEBPS/dup.xhtml", data: Data()),
            .init(name: "OEBPS/dup.xhtml", data: Data()),
            .init(name: "OEBPS/locked.xhtml", data: Data("x".utf8), flags: 0x0001),
        ]
        let codes = ZIPPreflight.inspect(data: w.build()).violations.map(\.code)
        #expect(codes.contains("invalid_name"))
        #expect(codes.contains("absolute_path"))
        #expect(codes.contains("duplicate_name"))
        #expect(codes.contains("zip_encryption"))
    }

    @Test("A markup entry larger than 16 MiB is rejected even at an innocent compression ratio")
    func markupSizeCap() {
        var w = StoredZipWriter()
        w.entries = [
            .init(name: "mimetype", data: Data("application/epub+zip".utf8)),
            .init(name: "OEBPS/huge.xhtml", data: Data(count: (16 << 20) + 1)),
            .init(name: "OEBPS/images/big.jpg", data: Data(count: (16 << 20) + 1)),
        ]
        let violations = ZIPPreflight.inspect(data: w.build()).violations
        #expect(violations == [.markupTooLarge("OEBPS/huge.xhtml", bytes: (16 << 20) + 1)], "\(violations)")
    }

    @Test("Not a ZIP at all")
    func notZip() {
        let report = ZIPPreflight.inspect(data: Data(repeating: 0x41, count: 4096))
        #expect(report.violations.map(\.code) == ["not_zip"])
    }

    @Test("Placeholder patch keeps a STORED archive valid and rewrites CRC-32")
    func patcher() throws {
        let original = try Data(contentsOf: FixturePaths.generated("g01-hostile.epub"))
        let (patched, names) = try StoredEntryPatcher.replace("127.0.0.1:00000", with: "127.0.0.1:54321", in: original)
        #expect(names.contains("OEBPS/c1.xhtml") && names.contains("OEBPS/evil.js") && names.contains("OEBPS/style.css"))
        #expect(patched.count == original.count)
        let report = ZIPPreflight.inspect(data: patched)
        #expect(report.isAcceptable)
        // Each patched entry's stored CRC matches its new bytes.
        for entry in report.entries where names.contains(entry.name) {
            let o = Int(entry.localHeaderOffset)
            let r = ByteReader(patched)
            let start = o + 30 + Int(r.u16(o + 26)) + Int(r.u16(o + 28))
            let body = patched.subdata(in: start ..< start + Int(entry.compressedSize))
            #expect(CRC32.checksum(body) == entry.crc32)
            #expect(body.range(of: Data("127.0.0.1:00000".utf8)) == nil)
        }
    }
}
