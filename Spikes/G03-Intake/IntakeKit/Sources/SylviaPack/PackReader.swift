import CryptoKit
import Darwin
import Foundation
import ReadiumZIPFoundation
import SylviaIntakeCore

/// The result of a successful validation. Only `PackReader` creates one.
public struct ValidatedPack: Sendable {
    public let manifest: PackManifest
    public let manifestSHA256: String
    public let archiveSize: UInt64
    public let entryCount: Int
    public let usesZIP64: Bool
    /// The directory holding the extracted content, when extraction was requested.
    public let extractedRoot: URL?
}

/// Validates a .sylviapack v1 and, optionally, extracts it while validating. One pass over the bytes:
/// every content entry is streamed through SHA-256 (and the library's CRC-32) with a fixed buffer, so memory
/// does not grow with the bundle size. A bundle that fails any check leaves nothing behind.
///
/// Order of checks (each one bounded before the next reads more):
///  1. regular file (not a symlink), strict structure (PackStructure: end record at the end, entry count and
///     central-directory size limits, back-to-back layout, local headers equal to central headers);
///  2. entry types, permissions and names;
///  3. manifest entry (size-limited) and its SHA-256 entry; manifest semantics and limits;
///  4. entry list equals the manifest (same order, no extras, nothing missing, declared sizes agree,
///     compression rules, per-entry expansion ratio and the aggregate expansion limit over all deflated entries);
///  5. the archive library's own reading of the entries agrees with ours;
///  6. when extracting: the destination volume has room for the declared content plus a margin (the shortfall is
///     named, plan 8.4), checked before anything is written;
///  7. content: bytes produced never exceed the declared size, final size, CRC-32 and SHA-256 all match.
public struct PackReader: Sendable {
    public let limits: PackLimits
    public let bufferSize: Int
    /// Available bytes on the volume of a path (nil when unknown). Injectable for tests.
    public let availableCapacity: @Sendable (URL) -> UInt64?

    public init(limits: PackLimits = PackLimits(), bufferSize: Int = 1 << 20,
                availableCapacity: @escaping @Sendable (URL) -> UInt64? = VolumeSpace.availableCapacity) {
        self.limits = limits
        self.bufferSize = bufferSize
        self.availableCapacity = availableCapacity
    }

    public func validate(_ url: URL) async throws(PackRejection) -> ValidatedPack {
        try await run(url, extractTo: nil)
    }

    /// `destination` must not exist; it is created, filled and synced, and removed again on any failure.
    public func extract(_ url: URL, to destination: URL) async throws(PackRejection) -> ValidatedPack {
        try await run(url, extractTo: destination)
    }

    private func run(_ url: URL, extractTo destination: URL?) async throws(PackRejection) -> ValidatedPack {
        var createdDestination = false
        do {
            let result = try await runUnchecked(url, extractTo: destination, created: &createdDestination)
            return result
        } catch {
            if createdDestination, let destination { Durability.removeTree(destination) }
            if let rejection = error as? PackRejection { throw rejection }
            throw PackRejection(.ioError, String(describing: error))
        }
    }

    private func runUnchecked(_ url: URL, extractTo destination: URL?, created: inout Bool) async throws -> ValidatedPack {
        // 1. Open without following a symbolic link, and require a regular file.
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            throw errno == ELOOP ? PackRejection(.notARegularFile, "symbolic link") : PackRejection(.ioError, IntakeIOError("open").description)
        }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw PackRejection(.ioError, "fstat") }
        guard info.isRegularFile else { throw PackRejection(.notARegularFile) }
        let fileSize = UInt64(info.st_size)
        let structure = try PackStructure.parse(fd: fd, fileSize: fileSize, limits: limits)

        // 2. Names: path rules and collisions, before anything is read from entry data.
        let entries = structure.entries
        guard entries.count >= PackLayout.reservedEntryCount + 1 else {
            throw PackRejection(.missingManifest, "fewer entries than a manifest needs")
        }
        var seen = Set<String>()
        for entry in entries {
            try PackPath.validate(entry.name)
            guard seen.insert(PackPath.collisionKey(entry.name)).inserted else {
                throw PackRejection(.duplicatePath, "entry \(entry.index)")
            }
        }

        // 3. Manifest and its digest: fixed names, first two entries, stored, size-limited. Names are compared byte for
        //    byte here and below (G0.3 review R4-01): String's == treats canonically equivalent names as equal.
        guard PathBytes.equal(entries[0].name, PackLayout.manifestEntry),
              PathBytes.equal(entries[1].name, PackLayout.manifestDigestEntry) else {
            throw PackRejection(.missingManifest, "the first two entries are not the manifest and its digest")
        }
        for entry in entries.prefix(2) where entry.method != 0 {
            throw PackRejection(.unsupportedCompression, "manifest entries must be stored")
        }
        guard entries[0].uncompressedSize <= UInt64(limits.maxManifestBytes) else {
            throw PackRejection(.manifestTooLarge, "more than \(limits.maxManifestBytes) bytes")
        }
        guard entries[1].uncompressedSize == 65 else { throw PackRejection(.manifestDigestMismatch, "digest entry size") }
        let manifestBytes = try readStoredEntry(fd: fd, entries[0])
        let digestBytes = try readStoredEntry(fd: fd, entries[1])
        let manifestSHA = hex(SHA256.hash(data: manifestBytes))
        guard digestBytes == Data((manifestSHA + "\n").utf8) else { throw PackRejection(.manifestDigestMismatch) }
        let manifest: PackManifest
        do {
            manifest = try PackManifest.decode(manifestBytes, limits: limits)
        } catch let rejection as PackRejection {
            throw rejection
        } catch let violation as StrictJSON.Violation {
            throw PackRejection(.manifestInvalid, "not strict JSON (\(violation.kind.rawValue))")
        } catch {
            throw PackRejection(.manifestInvalid, "not a v1 manifest")
        }
        try manifest.validate(limits: limits)

        // 4. Content entries equal the manifest's files, in order.
        let content = Array(entries.dropFirst(PackLayout.reservedEntryCount))
        if content.count > manifest.files.count { throw PackRejection(.unexpectedEntry, "\(content.count - manifest.files.count) entries not in the manifest") }
        if content.count < manifest.files.count { throw PackRejection(.missingEntry, "\(manifest.files.count - content.count) manifest files missing") }
        let byName = Dictionary(manifest.files.map { (PackLayout.contentPrefix + $0.path, $0) }, uniquingKeysWith: { a, _ in a })
        // Sums over deflated entries for the aggregate expansion limit (saturating, so no sum can wrap to a small value).
        var deflatedUncompressed: UInt64 = 0
        var deflatedCompressed: UInt64 = 0
        for (entry, file) in zip(content, manifest.files) {
            guard PathBytes.equal(entry.name, PackLayout.contentPrefix + file.path) else {
                if byName[entry.name] == nil { throw PackRejection(.unexpectedEntry, "entry \(entry.index) is not in the manifest") }
                throw PackRejection(.entryOrderMismatch, "entry \(entry.index)")
            }
            guard entry.uncompressedSize == file.size else {
                throw PackRejection(.declaredSizeMismatch, "entry \(entry.index): header \(entry.uncompressedSize), manifest \(file.size)")
            }
            if file.kind == .audio || file.kind == .epub || file.kind == .pdf || file.kind == .cover, entry.method != 0 {
                throw PackRejection(.unsupportedCompression, "\(file.kind.rawValue) must be stored")
            }
            if entry.method == 8 {
                if entry.uncompressedSize > limits.ratioCheckFloor {
                    let ratio = entry.uncompressedSize / max(entry.compressedSize, 1)
                    guard ratio <= limits.maxCompressionRatio else {
                        throw PackRejection(.expansionLimit, "entry \(entry.index) expands \(ratio)x")
                    }
                }
                deflatedUncompressed = saturatingAdd(deflatedUncompressed, entry.uncompressedSize)
                deflatedCompressed = saturatingAdd(deflatedCompressed, entry.compressedSize)
            }
        }
        // Aggregate expansion: many deflated entries at or below the per-entry floor must not add up to a bomb.
        let scaled = limits.maxCompressionRatio.multipliedReportingOverflow(by: deflatedCompressed)
        let allowed = scaled.overflow ? UInt64.max : saturatingAdd(scaled.partialValue, limits.aggregateExpansionAllowance)
        guard deflatedUncompressed <= allowed else {
            throw PackRejection(.expansionLimit,
                                "deflated entries together expand to \(deflatedUncompressed) bytes from \(deflatedCompressed)")
        }

        // 5. The archive library must read the same entries we parsed.
        let archive: Archive
        do {
            archive = try await Archive(url: url, accessMode: .read)
        } catch {
            throw PackRejection(.libraryDisagreement, "library could not open a structurally valid pack")
        }
        let libraryEntries = try await archive.entries()
        guard libraryEntries.count == entries.count else { throw PackRejection(.libraryDisagreement, "entry count") }
        for (ours, theirs) in zip(entries, libraryEntries) {
            guard PathBytes.equal(theirs.path, ours.name), theirs.type == .file,
                  theirs.uncompressedSize == ours.uncompressedSize, theirs.compressedSize == ours.compressedSize,
                  theirs.checksum == ours.crc32 else {
                throw PackRejection(.libraryDisagreement, "entry \(ours.index)")
            }
        }

        // 6. Space for the extracted content (plan 8.4), before anything is written. The declared sizes are binding:
        //    step 7 stops any entry at its declared size, so they bound what extraction can write.
        if let destination {
            guard (try? Durability.lstatInfo(destination)) == nil else { throw PackRejection(.destinationExists) }
            let required = saturatingAdd(manifest.totalSize, limits.extractionSpaceMargin)
            if let shortfall = VolumeSpace.shortfall(needed: required, available: availableCapacity(destination)) {
                throw PackRejection(.insufficientSpace, "\(shortfall) more bytes needed to extract \(manifest.totalSize) bytes",
                                    additionalBytesNeeded: shortfall)
            }
        }

        // 7. Content: stream, bound, hash, optionally write.
        if let destination {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Durability.createFreshDirectory(destination)
            created = true
        }
        for (index, file) in manifest.files.enumerated() {
            let ours = content[index]
            let theirs = libraryEntries[ours.index]
            var output: URL?
            if let destination {
                let target = destination.appendingPathComponent(file.path)
                // Defense in depth (report F18): the path rules already refuse anything that leaves the directory, and
                // extraction refuses it again, comparing the standardized target with the directory byte for byte.
                guard PathBytes.isInside(target, directory: destination) else {
                    throw PackRejection(.unsafePath, "entry \(ours.index) would be written outside the extraction directory")
                }
                output = target
            }
            let sink = try ContentSink(declaredSize: file.size, output: output)
            let crc: CRC32
            do {
                crc = try await archive.extract(theirs, bufferSize: bufferSize, skipCRC32: false) { chunk in
                    try sink.consume(chunk)
                }
            } catch let rejection as PackRejection {
                sink.abandon()
                throw rejection
            } catch {
                sink.abandon()
                throw PackRejection(.ioError, "reading entry \(ours.index): \(type(of: error))")
            }
            let (count, digest) = try sink.finish()
            guard count == file.size else {
                throw PackRejection(.actualSizeMismatch, "entry \(ours.index): \(count) of \(file.size) bytes")
            }
            guard crc == ours.crc32 else { throw PackRejection(.crcMismatch, "entry \(ours.index)") }
            guard PathBytes.equal(digest, file.sha256) else { throw PackRejection(.contentDigestMismatch, "entry \(ours.index)") }
        }
        if let destination { try ContentSink.syncTree(destination) }

        return ValidatedPack(manifest: manifest, manifestSHA256: manifestSHA, archiveSize: fileSize,
                             entryCount: entries.count, usesZIP64: structure.usesZIP64EndRecord,
                             extractedRoot: destination)
    }

    /// Reads a small stored entry directly (sizes were bounded before this is called) and checks its CRC-32.
    private func readStoredEntry(fd: Int32, _ entry: PackEntryRecord) throws -> Data {
        let bytes = try Durability.readExactly(fd: fd, count: Int(entry.uncompressedSize), at: entry.dataOffset)
        let data = Data(bytes)
        guard crc32(data) == entry.crc32 else { throw PackRejection(.crcMismatch, "entry \(entry.index)") }
        return data
    }
}

/// Receives one entry's bytes from the library: counts them (stopping at the first byte beyond the declared
/// size), hashes them, and writes them to a new file when extracting.
final class ContentSink: @unchecked Sendable {
    private let declaredSize: UInt64
    private var count: UInt64 = 0
    private var hasher = SHA256()
    private var fd: Int32 = -1
    private let output: URL?

    init(declaredSize: UInt64, output: URL?) throws {
        self.declaredSize = declaredSize
        self.output = output
        if let output {
            try ContentSink.makeParents(of: output)
            fd = open(output.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw PackRejection(.ioError, IntakeIOError("create").description) }
        }
    }

    func consume(_ chunk: Data) throws {
        let (next, overflow) = count.addingReportingOverflow(UInt64(chunk.count))
        guard !overflow, next <= declaredSize else {
            throw PackRejection(.actualSizeMismatch, "more bytes than declared")
        }
        count = next
        try chunk.withUnsafeBytes { raw in
            hasher.update(bufferPointer: raw)
            if fd >= 0 { try Durability.writeAll(fd: fd, raw) }
        }
    }

    func finish() throws -> (UInt64, String) {
        if fd >= 0 {
            try Durability.fullSync(fd: fd)
            let closing = fd
            fd = -1
            guard close(closing) == 0 else { throw PackRejection(.ioError, "close") }
        }
        return (count, hex(hasher.finalize()))
    }

    func abandon() {
        if fd >= 0 { close(fd); fd = -1 }
    }

    deinit { if fd >= 0 { close(fd) } }

    /// Creates missing parent directories one level at a time with mkdir (never following links). The
    /// destination tree is new and private, and every path was validated, so nothing can point outside it.
    static func makeParents(of url: URL) throws {
        let parent = url.deletingLastPathComponent()
        if let info = try Durability.lstatInfo(parent) {
            guard info.isDirectory else { throw PackRejection(.pathConflict) }
            return
        }
        try makeParents(of: parent)
        guard mkdir(parent.path, 0o700) == 0 else { throw PackRejection(.ioError, IntakeIOError("mkdir").description) }
    }

    static func syncTree(_ root: URL) throws {
        try Durability.syncDirectory(root)
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) {
            for case let url as URL in enumerator {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    try Durability.syncDirectory(url)
                }
            }
        }
        try Durability.syncDirectory(root.deletingLastPathComponent())
    }
}

func saturatingAdd(_ a: UInt64, _ b: UInt64) -> UInt64 {
    let (sum, overflow) = a.addingReportingOverflow(b)
    return overflow ? .max : sum
}

/// CRC-32 (IEEE) for the small manifest entries read without the library.
func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    data.withUnsafeBytes { raw in
        for byte in raw {
            crc = crc32Table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
    }
    return ~crc
}

private let crc32Table: [UInt32] = (0..<256).map { n in
    var c = UInt32(n)
    for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
    return c
}
