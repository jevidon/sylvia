import CryptoKit
import Foundation
import SylviaIntakeCore
@testable import SylviaPack
import Testing

/// Expansion across many entries, free space before extraction, and the path limits at their boundaries
/// (G0.3 review round 1: R1-01, R1-02).
@Suite("sylviapack reader: aggregate expansion, free space and path boundaries", .removesTemporaryFiles)
struct PackLimitTests {
    /// `count` deflated text entries of exactly 1 MiB of zeros each: each is at the per-entry ratio floor, so only the
    /// aggregate limit can catch them. The bytes, deflate stream, CRC-32 and SHA-256 are computed once and shared.
    func manySmallZeroEntries(_ count: Int) throws -> Data {
        let zeros = Data(count: 1 << 20)
        let deflated = RawZip.deflate(zeros)
        let crc = crc32(zeros)
        let digest = hex(SHA256.hash(data: zeros))
        var fixture = PackFixture(files: [])
        for i in 0..<count { fixture.files.append(("bomb/\(i).txt", zeros, .text, "text/plain")) }
        let manifest = PackManifest(
            packID: UUID(uuidString: "6F1A0C2E-3B4D-4E5F-8A9B-0C1D2E3F4A5B")!, createdAt: Date(timeIntervalSince1970: 1_790_000_000),
            generator: .init(name: "raw test builder", version: "1"),
            files: fixture.files.map { .init(path: $0.path, size: 1 << 20, sha256: digest, mediaType: $0.mediaType, kind: $0.kind) },
            groups: [])
        var zip = try fixture.rawZip(manifestOverride: manifest.encoded())
        for i in zip.entries.indices.dropFirst(PackLayout.reservedEntryCount) {
            zip.entries[i].compressedData = deflated
            zip.entries[i].crcOverride = crc
        }
        return zip.build()
    }

    @Test("many deflated entries at or below the per-entry floor cannot add up to a bomb")
    func aggregateExpansion() async throws {
        let count = 2_000
        let data = try manySmallZeroEntries(count)
        let declared = UInt64(count) << 20
        let started = ContinuousClock.now
        let code = try await verdict(data)
        let elapsed = ContinuousClock.now - started
        print("aggregate expansion: \(count) deflated entries of 1 MiB, archive \(data.count) bytes, declares \(declared) bytes (\(declared / UInt64(data.count)):1): rejection code \(code.map(\.rawValue) ?? "none (ACCEPTED)") in \(elapsed)")
        #expect(code == .expansionLimit)
        #expect(elapsed < .seconds(10), "rejected from the headers, without inflating")
    }

    @Test("the aggregate limit is the ratio times the deflated bytes plus a fixed allowance")
    func aggregateBoundary() async throws {
        // 8 MiB of zeros in 8 entries is within the 16 MiB allowance: accepted (and extracted in full).
        let small = try manySmallZeroEntries(8)
        #expect(try await verdict(small) == nil)
        // With no allowance the same pack exceeds 100 x its deflated bytes.
        var strict = PackLimits()
        strict.aggregateExpansionAllowance = 0
        #expect(try await verdict(small, limits: strict) == .expansionLimit)
        // Ordinary text (the standard fixture) is far inside the limit even with no allowance.
        #expect(try await verdict(PackFixture.standard().rawZip().build(), limits: strict) == nil)
    }

    @Test("extraction checks free space first, names the shortfall and writes nothing")
    func insufficientSpace() async throws {
        let dir = try temporaryDirectory()
        let pack = dir.appendingPathComponent("p.sylviapack")
        try PackFixture.standard().rawZip().build().write(to: pack)
        let total = PackFixture.standard().manifest().totalSize
        let margin = PackLimits().extractionSpaceMargin
        let available: UInt64 = 10_000
        let reader = PackReader(availableCapacity: { _ in available })
        let out = dir.appendingPathComponent("out")
        do {
            _ = try await reader.extract(pack, to: out)
            Issue.record("extraction proceeded without space")
        } catch {
            #expect(error.code == .insufficientSpace)
            #expect(error.additionalBytesNeeded == total + margin - available)
        }
        #expect(try Durability.lstatInfo(out) == nil, "nothing was created")
        // Validation alone writes nothing and needs no space.
        _ = try await reader.validate(pack)
        // Exactly enough space: extraction proceeds.
        let enough = PackReader(availableCapacity: { _ in total + margin })
        _ = try await enough.extract(pack, to: out)
        // Unknown capacity does not block extraction (a write that runs out of space still fails and cleans up).
        _ = try await PackReader(availableCapacity: { _ in nil }).extract(pack, to: dir.appendingPathComponent("out2"))
    }

    @Test("manifest paths: 15 components and 512 bytes are the limits, so every accepted path makes a readable pack")
    func pathBoundaries() async throws {
        let fifteen = (1...14).map { "d\($0)" }.joined(separator: "/") + "/f.txt"
        let sixteen = (1...15).map { "d\($0)" }.joined(separator: "/") + "/f.txt"
        // 512 bytes: two components of 250 bytes and one of 10 (component limit 255).
        let longest = String(repeating: "a", count: 250) + "/" + String(repeating: "c", count: 250) + "/bbbbbb.txt"
        #expect(longest.utf8.count == 512)
        let tooLong = longest.replacingOccurrences(of: "/bbbbbb.txt", with: "/bbbbbbb.txt")
        #expect(tooLong.utf8.count == 513)

        #expect(throws: Never.self) { try PackPath.validateManifestPath(fifteen) }
        #expect(throws: Never.self) { try PackPath.validateManifestPath(longest) }
        #expect(throws: PackRejection(.unsafePath, "too deep")) { try PackPath.validateManifestPath(sixteen) }
        #expect(throws: PackRejection(.unsafePath, "length")) { try PackPath.validateManifestPath(tooLong) }

        // The writer and the reader agree at the boundary: both boundary paths make a pack that validates and extracts.
        let dir = try temporaryDirectory()
        var sources: [PackSource] = []
        for (i, path) in [fifteen, longest].enumerated() {
            let url = dir.appendingPathComponent("src-\(i).txt")
            try Data("boundary \(i)\n".utf8).write(to: url)
            sources.append(PackSource(url: url, path: path, kind: .text, mediaType: "text/plain"))
        }
        let pack = dir.appendingPathComponent("boundary.sylviapack")
        try await PackWriter().write(sources: sources, groups: [], to: pack)
        let out = dir.appendingPathComponent("out")
        let extracted = try await PackReader().extract(pack, to: out)
        #expect(extracted.manifest.files.map(\.path) == [fifteen, longest])
        #expect(try Data(contentsOf: out.appendingPathComponent(longest)) == Data("boundary 1\n".utf8))

        // One component or one byte more is refused by the manifest rules, so the writer refuses it up front.
        for path in [sixteen, tooLong] {
            let url = dir.appendingPathComponent("src-x.txt")
            try? FileManager.default.removeItem(at: url)
            try Data("x".utf8).write(to: url)
            await #expect(throws: PackWriterError.invalidInput(PackRejection(.unsafePath, path == sixteen ? "too deep" : "length"))) {
                try await PackWriter().write(sources: [PackSource(url: url, path: path, kind: .text, mediaType: "text/plain")],
                                             groups: [], to: dir.appendingPathComponent("refused-\(path.count).sylviapack"))
            }
        }
    }

    /// G0.3 review R2-04. The schema's `maxLength` (512) and component pattern (`{1,255}`) count code points; the reader
    /// counts UTF-8 bytes, because the file system does (PATH_MAX, NAME_MAX). For ASCII they agree; for non-ASCII the
    /// reader is stricter, which the schema's description and ADR-0010 section 2 state with the example below.
    @Test("non-ASCII manifest paths: the limits are UTF-8 bytes (512 in total, 255 per component), stricter than the schema's code points")
    func nonASCIIPathBoundaries() async throws {
        let e = "\u{E9}"                                          // é (NFC): one code point, two UTF-8 bytes
        let c255 = String(repeating: e, count: 127) + "a"         // 255 bytes, 128 code points
        let c256 = String(repeating: e, count: 128)               // 256 bytes, 128 code points
        let c254 = String(repeating: e, count: 127)               // 254 bytes
        let at512 = c255 + "/" + c254 + "/a"                       // 255 + 1 + 254 + 1 + 1 bytes
        let at513 = c255 + "/" + c255 + "/a"
        #expect(at512.utf8.count == 512 && at513.utf8.count == 513)
        #expect(at512.unicodeScalars.count == 258 && at513.unicodeScalars.count == 259, "far inside the schema's 512 code points")
        #expect(throws: Never.self) { try PackPath.validateManifestPath(at512) }
        #expect(throws: PackRejection(.unsafePath, "length")) { try PackPath.validateManifestPath(at513) }
        #expect(throws: Never.self) { try PackPath.validateManifestPath("Book/" + c255) }
        #expect(throws: PackRejection(.unsafePath, "component length")) { try PackPath.validateManifestPath("Book/" + c256) }

        // The documented examples: valid against the schema (Spikes/G03-Intake/scripts/check-contract-instances.sh
        // checks that side), refused by the reader.
        let hundred = String(repeating: e, count: 100)
        let example = hundred + "/" + hundred + "/" + hundred + ".epub"   // 307 code points, 607 bytes
        #expect(example.unicodeScalars.count == 307 && example.utf8.count == 607)
        #expect(throws: PackRejection(.unsafePath, "length")) { try PackPath.validateManifestPath(example) }
        let wideComponent = "Walden/" + String(repeating: e, count: 200) + ".epub"   // one component of 405 bytes
        #expect(throws: PackRejection(.unsafePath, "component length")) { try PackPath.validateManifestPath(wideComponent) }

        // Writer and reader agree at the non-ASCII boundary: the 512-byte path packs, validates and extracts; one byte
        // more is refused by the writer before it writes anything.
        let dir = try temporaryDirectory()
        let source = dir.appendingPathComponent("src.txt")
        try Data("non-ASCII boundary\n".utf8).write(to: source)
        let pack = dir.appendingPathComponent("non-ascii.sylviapack")
        try await PackWriter().write(sources: [PackSource(url: source, path: at512, kind: .text, mediaType: "text/plain")],
                                     groups: [], to: pack)
        let out = dir.appendingPathComponent("out")
        let extracted = try await PackReader().extract(pack, to: out)
        #expect(extracted.manifest.files.map(\.path) == [at512])
        #expect(try Data(contentsOf: out.appendingPathComponent(at512)) == Data("non-ASCII boundary\n".utf8))
        for path in [at513, example] {
            await #expect(throws: PackWriterError.invalidInput(PackRejection(.unsafePath, "length"))) {
                try await PackWriter().write(sources: [PackSource(url: source, path: path, kind: .text, mediaType: "text/plain")],
                                             groups: [], to: dir.appendingPathComponent("refused-\(path.utf8.count).sylviapack"))
            }
        }
        print("non-ASCII paths: 512 bytes (258 code points) accepted and extracted; 513 bytes and the 607-byte, 307-code-point example refused (length); a 256-byte component refused")
    }

    @Test("text too repetitive to deflate within the limits is written stored, and the pack validates")
    func writerStoresRepetitiveText() async throws {
        let dir = try temporaryDirectory()
        var sources: [PackSource] = []
        for i in 0..<24 {
            let url = dir.appendingPathComponent("log-\(i).txt")
            try Data(String(repeating: "the same line again\n", count: 52_000).utf8).write(to: url)   // ~1 MiB each
            sources.append(PackSource(url: url, path: "logs/\(i).txt", kind: .text, mediaType: "text/plain"))
        }
        let pack = dir.appendingPathComponent("repetitive.sylviapack")
        let written = try await PackWriter().write(sources: sources, groups: [], to: pack)
        #expect(written.manifest.files.count == 24)
        let structure = try withFD(pack) { fd, size in try PackStructure.parse(fd: fd, fileSize: size, limits: PackLimits()) }
        #expect(structure.entries.allSatisfy { $0.method == 0 }, "fell back to stored entries")
        _ = try await PackReader().validate(pack)
        // Ordinary text is still deflated.
        let standard = try await PackWriter().write(
            sources: [PackSource(url: sources[0].url, path: "one.txt", kind: .text, mediaType: "text/plain")],
            groups: [], to: dir.appendingPathComponent("one.sylviapack"))
        let one = try withFD(dir.appendingPathComponent("one.sylviapack")) { fd, size in try PackStructure.parse(fd: fd, fileSize: size, limits: PackLimits()) }
        #expect(standard.manifest.files.count == 1)
        #expect(one.entries.last?.method == 8, "a single 1 MiB file is within the allowance and stays deflated")
    }

    /// The manifest of `count` one-byte audio files whose paths are each exactly 512 bytes (the limit), whose media types
    /// are 128 characters (the schema's limit), in audiobook groups of 500 members (the limit) with 64-character ids,
    /// 1024-character titles, a 512-character creator, a 35-character language and one identifier at its limits.
    static func entryLimitManifest(files count: Int) -> PackManifest {
        let digest = hex(SHA256.hash(data: Data([0x55])))
        let mediaType = "audio/" + String(repeating: "m", count: 122)
        func groupID(_ group: Int) -> String {
            let head = "audiobook-\(group)-"
            return head + String(repeating: "x", count: 64 - head.utf8.count)
        }
        let files = (0..<count).map { index in
            let tail = String(format: "%05d", index) + "ccccc"                    // 10 bytes
            let path = String(repeating: "a", count: 250) + "/" + String(repeating: "b", count: 250) + "/" + tail
            return PackManifest.File(path: path, size: 1, sha256: digest, mediaType: mediaType, kind: .audio,
                                     groupID: groupID(index / 500), order: index % 500 + 1)
        }
        let groups = (0..<((count + 499) / 500)).map { group in
            PackManifest.Group(groupID: groupID(group), kind: .audiobook, title: String(repeating: "t", count: 1024),
                               creators: [String(repeating: "c", count: 512)], language: String(repeating: "l", count: 35),
                               identifiers: [.init(scheme: String(repeating: "s", count: 64), value: String(repeating: "v", count: 512))],
                               memberOrderBasis: .userConfirmed)
        }
        return PackManifest(packID: UUID(uuidString: "6F1A0C2E-3B4D-4E5F-8A9B-0C1D2E3F4A5B")!,
                            createdAt: Date(timeIntervalSince1970: 1_790_000_000),
                            generator: .init(name: String(repeating: "n", count: 128), version: String(repeating: "v", count: 64)),
                            files: files, groups: groups)
    }

    /// G0.3 review R4-02: with a 1 MiB manifest limit at most about 5,800 files fitted even with 4-byte paths, so the
    /// schema's `maxItems` 9998 (the 10,000-entry limit less the two manifest entries) could not be reached.
    @Test("the entry limit is reachable: 9,998 files with every path at its 512-byte limit, in 20 audiobook groups at their metadata limits, make a pack the reader accepts")
    func entryLimitReachable() async throws {
        let limits = PackLimits()
        let count = limits.maxEntries - PackLayout.reservedEntryCount
        let manifest = Self.entryLimitManifest(files: count)
        let manifestBytes = try manifest.encoded()
        #expect(manifestBytes.count <= limits.maxManifestBytes)
        #expect(manifestBytes.count > 1 << 20, "the former 1 MiB limit would have refused it")
        var zip = RawZip()
        zip.entries.append(RawEntry(PackLayout.manifestEntry, manifestBytes))
        zip.entries.append(RawEntry(PackLayout.manifestDigestEntry, Data((hex(SHA256.hash(data: manifestBytes)) + "\n").utf8)))
        for file in manifest.files { zip.entries.append(RawEntry(PackLayout.contentPrefix + file.path, Data([0x55]))) }
        let archive = zip.build()
        let dir = try temporaryDirectory()
        let url = dir.appendingPathComponent("entry-limit.sylviapack")
        try archive.write(to: url)
        let started = ContinuousClock.now
        let validated = try await PackReader().validate(url)
        let elapsed = ContinuousClock.now - started
        print("entry limit: \(validated.manifest.files.count) files in \(validated.entryCount) entries, manifest \(manifestBytes.count) bytes (limit \(limits.maxManifestBytes)), archive \(archive.count) bytes, validated in \(elapsed) (debug build, tests running in parallel: indicative)")
        #expect(validated.entryCount == limits.maxEntries)
        // One file more is refused by the entry limit, before the manifest is read.
        zip.entries.append(RawEntry(PackLayout.contentPrefix + "one-more.mp3", Data([0x55])))
        #expect(try await verdict(zip.build()) == .tooManyEntries)
    }

    @Test("manifest size: exactly the limit is read, one byte more is refused as manifest_too_large, whitespace included")
    func manifestSizeBoundary() throws {
        let limits = PackLimits()
        let text = try PackFixture.standard().manifest().encoded()
        let atLimit = text + Data(repeating: 0x20, count: limits.maxManifestBytes - text.count)
        #expect(atLimit.count == 16 << 20)
        let started = ContinuousClock.now
        #expect(throws: Never.self) { _ = try PackManifest.decode(atLimit, limits: limits) }
        let elapsed = ContinuousClock.now - started
        #expect(throws: PackRejection(.manifestTooLarge, "more than \(16 << 20) bytes")) {
            _ = try PackManifest.decode(atLimit + Data([0x20]), limits: limits)
        }
        print("manifest size limit: \(atLimit.count) bytes read in \(elapsed) (debug build: indicative); one byte more refused")
    }

    @Test("the writer refuses a manifest over the reader's limit before writing anything")
    func writerRefusesOversizedManifest() async throws {
        let dir = try temporaryDirectory()
        let fixture = PackFixture.standard()
        var sources: [PackSource] = []
        for file in fixture.files {
            let url = dir.appendingPathComponent("src-\(sources.count)")
            try file.data.write(to: url)
            sources.append(PackSource(url: url, path: file.path, kind: file.kind, mediaType: file.mediaType,
                                      groupID: fixture.groupOf[file.path]?.0, order: fixture.groupOf[file.path]?.1))
        }
        var limits = PackLimits()
        limits.maxManifestBytes = 600
        await #expect(throws: PackWriterError.invalidInput(PackRejection(.manifestTooLarge, "more than 600 bytes"))) {
            try await PackWriter(limits: limits).write(sources: sources, groups: fixture.groups,
                                                       to: dir.appendingPathComponent("small-limit.sylviapack"))
        }
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { !$0.hasPrefix("src-") }
        #expect(left.isEmpty, "nothing written: \(left)")
    }
}
