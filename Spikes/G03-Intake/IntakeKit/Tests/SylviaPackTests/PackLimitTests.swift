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
}
