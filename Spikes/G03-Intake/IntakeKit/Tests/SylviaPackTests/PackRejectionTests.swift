import CryptoKit
import Foundation
import SylviaIntakeCore
@testable import SylviaPack
import Testing

/// Each test changes exactly one thing relative to the accepted raw baseline and expects one rejection code.
@Suite("sylviapack reader: rejections (T13 archive half, T42)", .removesTemporaryFiles)
struct PackRejectionTests {
    let fixture = PackFixture.standard()

    func code(_ mutate: (inout RawZip) throws -> Void, limits: PackLimits = PackLimits()) async throws -> PackRejection.Code? {
        var zip = try fixture.rawZip()
        try mutate(&zip)
        return try await verdict(zip.build(), limits: limits)
    }

    func contentIndex(_ path: String) -> Int {
        2 + fixture.files.firstIndex { $0.path == path }!
    }

    // MARK: Paths

    @Test("path traversal, absolute paths and other unsafe names", arguments: [
        "content/../escape.txt", "/etc/passwd", "content/a\\b.txt", "content//double.txt", "content/./dot.txt",
        "content/tab\there.txt", "content/C:drive.txt", "content/" + String(repeating: "x", count: 300) + ".txt",
    ])
    func unsafeEntryNames(name: String) async throws {
        #expect(try await code { $0.entries[contentIndex("Walden/notes.md")].name = name } == .unsafePath)
    }

    @Test("a manifest path with traversal is rejected even when the entry name matches it")
    func manifestTraversal() async throws {
        var f = fixture
        f.files[0].path = "../../outside.md"
        #expect(try await verdict(f.rawZip().build()) == .unsafePath)
    }

    @Test("a name that is not Unicode NFC is rejected")
    func nonNFC() async throws {
        #expect(try await code { $0.entries[contentIndex("Walden/notes.md")].name = "content/Walden/cafe\u{0301}.md" } == .unsafePath)
    }

    @Test("duplicate names: exact, differing only in case, differing only in normalization")
    func duplicates() async throws {
        #expect(try await code { $0.entries.append($0.entries[contentIndex("Walden/notes.md")]) } == .duplicatePath)
        #expect(try await code { z in
            var copy = z.entries[contentIndex("Walden/notes.md")]
            copy.name = "content/WALDEN/NOTES.md"
            z.entries.append(copy)
        } == .duplicatePath)
        var f = fixture
        f.files.append(("Walden/Notes.MD", Data("other".utf8), .markdown, "text/markdown"))
        #expect(try await verdict(f.rawZip().build()) == .duplicatePath)
    }

    @Test("a path used both as a file and as a folder is rejected")
    func fileFolderConflict() async throws {
        var f = fixture
        f.files.append(("Walden", Data("file named like the folder".utf8), .text, "text/plain"))
        #expect(try await verdict(f.rawZip().build()) == .pathConflict)
    }

    // MARK: Entry types

    @Test("symbolic links, directories, FIFOs and devices are rejected", arguments: [
        (UInt32(0o120777), "symlink"), (UInt32(0o040755), "directory"), (UInt32(0o010644), "fifo"),
        (UInt32(0o020644), "char device"), (UInt32(0o060644), "block device"), (UInt32(0o140644), "socket"),
    ])
    func specialEntries(mode: UInt32, label: String) async throws {
        #expect(try await code { $0.entries[contentIndex("Walden/notes.md")].unixMode = mode } == .specialEntry, "\(label)")
    }

    @Test("a directory entry (trailing slash) is rejected")
    func directoryEntry() async throws {
        #expect(try await code { $0.entries.append(RawEntry("content/Walden/", Data())) } == .specialEntry)
    }

    @Test("executable and setuid bits are rejected", arguments: [UInt32(0o100755), 0o100744, 0o104644, 0o102644])
    func executable(mode: UInt32) async throws {
        #expect(try await code { $0.entries[contentIndex("Walden/notes.md")].unixMode = mode } == .executableEntry)
    }

    @Test("MS-DOS directory attribute is rejected")
    func dosDirectory() async throws {
        #expect(try await code {
            $0.entries[contentIndex("Walden/notes.md")].versionMadeBy = 0x0014
            $0.entries[contentIndex("Walden/notes.md")].externalOverride = 0x10
        } == .specialEntry)
    }

    // MARK: Manifest agreement

    @Test("an entry not listed in the manifest is rejected")
    func extraEntry() async throws {
        #expect(try await code { $0.entries.append(RawEntry("content/extra.caf", Data([1, 2, 3]))) } == .unexpectedEntry)
    }

    @Test("a manifest file without an entry is rejected")
    func missingEntry() async throws {
        #expect(try await code { $0.entries.removeLast() } == .missingEntry)
    }

    @Test("entries out of manifest order are rejected")
    func orderMismatch() async throws {
        #expect(try await code { $0.entries.swapAt(2, 3) } == .entryOrderMismatch)
    }

    @Test("an entry whose header size differs from the manifest is rejected")
    func declaredSizeMismatch() async throws {
        var m = fixture.manifest()
        m.files[2].size += 1
        m.totalSize += 1
        #expect(try await verdict(fixture.rawZip(manifestOverride: m.encoded()).build()) == .declaredSizeMismatch)
    }

    @Test("changed content with a recomputed CRC fails the SHA-256 check")
    func digestMismatch() async throws {
        #expect(try await code { z in
            let i = contentIndex("Meditations/part-01.caf")
            var data = z.entries[i].data
            data[100] ^= 0xFF
            z.entries[i].data = data   // CRC is recomputed by the builder; SHA-256 in the manifest is not
        } == .contentDigestMismatch)
    }

    @Test("changed content with the original CRC fails the CRC check")
    func crcMismatch() async throws {
        #expect(try await code { z in
            let i = contentIndex("Meditations/part-01.caf")
            z.entries[i].crcOverride = crc32(z.entries[i].data)
            var data = z.entries[i].data
            data[100] ^= 0xFF
            z.entries[i].data = data
        } == .crcMismatch)
    }

    @Test("manifest problems: digest, missing, too large, not JSON, wrong version")
    func manifestProblems() async throws {
        #expect(try await code { $0.entries[1].data = Data((String(repeating: "0", count: 64) + "\n").utf8) } == .manifestDigestMismatch)
        #expect(try await code { $0.entries.swapAt(0, 1) } == .missingManifest)
        #expect(try await code { $0.entries.remove(at: 0) } == .missingManifest)
        let junk = Data("{ not json".utf8)
        #expect(try await verdict(fixture.rawZip(manifestOverride: junk).build()) == .manifestInvalid)
        var m = fixture.manifest()
        m.schemaVersion = 2
        #expect(try await verdict(fixture.rawZip(manifestOverride: m.encoded()).build()) == .unsupportedVersion)
        var limits = PackLimits()
        limits.maxManifestBytes = 512
        #expect(try await code({ _ in }, limits: limits) == .manifestTooLarge)
    }

    // MARK: Sizes, expansion and bombs

    @Test("a deflated entry that produces more bytes than declared stops at the declared size")
    func sizeLie() async throws {
        let big = Data(repeating: 0x41, count: 4 << 20)
        var f = fixture
        f.files[0] = ("Walden/notes.md", Data(repeating: 0x41, count: 100), .markdown, "text/markdown")
        var zip = try f.rawZip()
        // Header and manifest say 100 bytes; the deflate stream really holds 4 MiB.
        zip.entries[2].compressedData = RawZip.deflate(big)
        #expect(try await verdict(zip.build()) == .actualSizeMismatch)
    }

    @Test("a deflated entry that produces fewer bytes than declared is rejected")
    func sizeLieShort() async throws {
        // Header and manifest say 512 KiB (below the ratio-check floor, so only the actual byte count can catch it);
        // the deflate stream really holds 100 bytes.
        let declared = Data(repeating: 0x41, count: 512 << 10)
        var f = fixture
        f.files[0] = ("Walden/notes.md", declared, .markdown, "text/markdown")
        var zip = try f.rawZip()
        zip.entries[2].compressedData = RawZip.deflate(Data(repeating: 0x41, count: 100))
        let verdictCode = try await verdict(zip.build())
        print("short deflate stream: rejection code \(verdictCode.map(\.rawValue) ?? "none (ACCEPTED)")")
        #expect(verdictCode == .actualSizeMismatch)
    }

    @Test("a stored entry whose compressed and uncompressed sizes differ is rejected")
    func storedSizeLie() async throws {
        #expect(try await code { z in
            let i = contentIndex("Meditations/part-02.caf")
            z.entries[i].uncompressedSizeOverride = UInt64(z.entries[i].data.count) + 10
        } == .storedSizeMismatch)
    }

    @Test("excessive expansion: a 64 MiB run of zeros deflated about 1000:1 is rejected before inflating")
    func expansionBomb() async throws {
        let zeros = Data(count: 64 << 20)
        var f = fixture
        f.files.append(("bomb.txt", zeros, .text, "text/plain"))
        let data = try f.rawZip().build()
        #expect(data.count < 2 << 20, "the bomb is small on disk")
        let started = ContinuousClock.now
        #expect(try await verdict(data) == .expansionLimit)
        #expect(ContinuousClock.now - started < .seconds(5), "rejected from headers, without inflating")
    }

    @Test("audio, EPUB, PDF and covers must be stored, not deflated")
    func audioMustBeStored() async throws {
        #expect(try await code { $0.entries[contentIndex("Meditations/part-01.caf")].method = 8 } == .unsupportedCompression)
    }

    @Test("more than 10,000 entries: a forged count is rejected before the directory is read")
    func forgedEntryCount() async throws {
        var zip = try fixture.rawZip()
        zip.forceZIP64 = true
        zip.entryCountOverride = 10_001
        #expect(try await verdict(zip.build()) == .tooManyEntries)
        zip.entryCountOverride = UInt64.max
        #expect(try await verdict(zip.build()) == .tooManyEntries)
    }

    @Test("more than 10,000 entries: a real 10,001-entry archive is rejected")
    func realEntryCount() async throws {
        var f = PackFixture(files: [])
        for i in 0..<9_999 { f.files.append(("f/\(i).txt", Data("\(i)".utf8), .text, "text/plain")) }
        var zip = try f.rawZip()
        for i in zip.entries.indices.dropFirst(2) { zip.entries[i].method = 0 }
        #expect(zip.entries.count == 10_001)
        #expect(try await verdict(zip.build()) == .tooManyEntries)
    }

    @Test("a manifest that lists more files than the entry limit allows is rejected")
    func manifestTooManyFiles() async throws {
        var limits = PackLimits()
        limits.maxEntries = 5
        #expect(try await code({ _ in }, limits: limits) == .tooManyEntries)
    }

    @Test("per-kind size limits and audio member limits apply")
    func limits() async throws {
        var limits = PackLimits()
        limits.maxAudioFile = 60_000
        #expect(try await code({ _ in }, limits: limits) == .limitExceeded)
        limits = PackLimits()
        limits.maxAudioMembersPerGroup = 1
        #expect(try await code({ _ in }, limits: limits) == .limitExceeded)
    }

    // MARK: Container structure

    @Test("an archive comment is rejected")
    func comment() async throws {
        #expect(try await code { $0.comment = Data("hi".utf8) } == .archiveComment)
    }

    @Test("bytes after the end record mean the end record is not at the end")
    func trailing() async throws {
        #expect(try await code { $0.trailing = Data([0, 1, 2]) } == .truncated)
    }

    @Test("bytes before the first entry or between entries are rejected")
    func gaps() async throws {
        #expect(try await code { $0.prefix = Data(repeating: 0, count: 16) } == .layoutGap)
        #expect(try await code { $0.gapAfterFirstEntry = 7 } == .layoutGap)
    }

    @Test("encryption, data descriptors, unknown methods and newer versions are rejected")
    func unsupportedFeatures() async throws {
        let i = contentIndex("Meditations/part-01.caf")
        #expect(try await code { $0.entries[i].flags |= 0x0001 } == .encryptedEntry)
        #expect(try await code { $0.entries[i].flags |= 0x0008 } == .unsupportedFeature)
        #expect(try await code { $0.entries[i].method = 12 } == .unsupportedCompression)
        #expect(try await code { $0.entries[i].versionNeeded = 63 } == .unsupportedFeature)
    }

    @Test("a local header that disagrees with the central directory is rejected")
    func localHeaderMismatch() async throws {
        #expect(try await code { $0.entries[contentIndex("Walden/notes.md")].localNameOverride = "content/Walden/other.md" } == .localHeaderMismatch)
    }

    @Test("a symbolic link to a valid pack is refused; the pack itself is accepted")
    func symlinkedPack() async throws {
        let dir = try temporaryDirectory()
        let real = dir.appendingPathComponent("real.sylviapack")
        try fixture.rawZip().build().write(to: real)
        let link = dir.appendingPathComponent("link.sylviapack")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        _ = try await PackReader().validate(real)
        await #expect(throws: PackRejection(.notARegularFile, "symbolic link")) { try await PackReader().validate(link) }
    }

    // MARK: Partial and truncated copies

    @Test("truncation at every byte offset of a small pack is rejected")
    func truncatedEverywhere() async throws {
        let data = try fixture.rawZip().build()
        let url = try temporaryDirectory().appendingPathComponent("sweep.sylviapack")
        try data.write(to: url)
        _ = try await PackReader().validate(url)   // control: the untruncated file is accepted
        var codes: [PackRejection.Code: Int] = [:]
        // Cut the same file shorter and shorter: each length is the prefix a partial copy would leave.
        for length in stride(from: data.count - 1, through: 0, by: -1) {
            #expect(truncate(url.path, off_t(length)) == 0)
            do {
                _ = try await PackReader().validate(url)
                Issue.record("a pack truncated to \(length) of \(data.count) bytes was accepted")
            } catch {
                codes[error.code, default: 0] += 1
            }
        }
        #expect(codes.values.reduce(0, +) == data.count)
        print("truncation sweep: \(data.count) lengths rejected; codes \(codes.map { "\($0.key.rawValue)=\($0.value)" }.sorted())")
    }

    @Test("a partial copy padded with zeros to the full length is rejected", arguments: [0.1, 0.5, 0.9, 0.99])
    func zeroPadded(fraction: Double) async throws {
        let data = try fixture.rawZip().build()
        let keep = Int(Double(data.count) * fraction)
        var padded = data.prefix(keep)
        padded.append(Data(count: data.count - keep))
        #expect(try await verdict(padded) != nil)
    }

    @Test("a complete-length copy with a zeroed range in the middle is rejected")
    func zeroedMiddle() async throws {
        var data = try fixture.rawZip().build()
        let start = data.count / 2
        data.replaceSubrange(start..<(start + 512), with: Data(count: 512))
        #expect(try await verdict(data) != nil)
    }

    @Test("a failed extraction leaves nothing behind; an existing destination is refused")
    func extractionCleanup() async throws {
        let dir = try temporaryDirectory()
        var zip = try fixture.rawZip()
        let i = contentIndex("Meditations/part-02.caf")
        var data = zip.entries[i].data
        data[10] ^= 1
        zip.entries[i].data = data    // last entry fails its digest after earlier files were written
        let bad = dir.appendingPathComponent("bad.sylviapack")
        try zip.build().write(to: bad)
        let out = dir.appendingPathComponent("out")
        await #expect(throws: PackRejection.self) { try await PackReader().extract(bad, to: out) }
        #expect(try Durability.lstatInfo(out) == nil)

        let good = dir.appendingPathComponent("good.sylviapack")
        try fixture.rawZip().build().write(to: good)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        await #expect(throws: PackRejection(.destinationExists)) { try await PackReader().extract(good, to: out) }
    }
}
