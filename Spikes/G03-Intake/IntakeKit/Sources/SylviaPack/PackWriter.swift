import CryptoKit
import Darwin
import Foundation
import ReadiumZIPFoundation
import SylviaIntakeCore

/// One file to put in a pack.
public struct PackSource: Sendable {
    public var url: URL
    public var path: String
    public var kind: PackManifest.Kind
    public var mediaType: String
    public var groupID: String?
    public var order: Int?

    public init(url: URL, path: String, kind: PackManifest.Kind, mediaType: String, groupID: String? = nil, order: Int? = nil) {
        self.url = url
        self.path = path
        self.kind = kind
        self.mediaType = mediaType
        self.groupID = groupID
        self.order = order
    }
}

public enum PackWriterError: Error, Equatable, Sendable, CustomStringConvertible {
    case destinationExists
    case invalidInput(PackRejection)
    case sourceChanged(index: Int)
    case selfCheckFailed(PackRejection)
    case io(String)

    public var description: String {
        switch self {
        case .destinationExists: "destination exists"
        case let .invalidInput(r): "invalid input: \(r)"
        case let .sourceChanged(i): "source \(i) changed while it was being packed"
        case let .selfCheckFailed(r): "written pack failed validation: \(r)"
        case let .io(s): s
        }
    }
}

/// The Mac companion's .sylviapack v1 writer (plan 8.5, 16.4). Two passes over each source: the first computes
/// sizes and SHA-256 for the manifest (which is the first entry), the second streams the bytes into the archive
/// and hashes them again, so a source that changes while packing is caught. The archive is written under a
/// temporary name, synced, validated with `PackReader`, and only then renamed into place.
public struct PackWriter: Sendable {
    public var limits: PackLimits
    public var generator: PackManifest.Generator
    public var bufferSize: Int
    /// Test seam: runs after the hashing pass, before any archive bytes are written.
    var afterPassOne: (@Sendable () -> Void)?

    public init(limits: PackLimits = PackLimits(),
                generator: PackManifest.Generator = .init(name: "Sylvia G0.3 spike writer", version: "0.1"),
                bufferSize: Int = 1 << 20) {
        self.limits = limits
        self.generator = generator
        self.bufferSize = bufferSize
    }

    /// Text and Markdown are deflated; everything else (audio, EPUB, PDF, covers) is stored. With `storeText` (the
    /// fallback described in `write`) everything is stored.
    public static func compression(for kind: PackManifest.Kind, storeText: Bool = false) -> CompressionMethod {
        !storeText && (kind == .text || kind == .markdown) ? .deflate : .none
    }

    /// - Parameter fixedDate: entry timestamps and `created_at`; pass a constant for byte-identical output.
    ///
    /// Text so repetitive that deflating it exceeds the reader's expansion limits (per entry or in aggregate) would
    /// make a pack the reader refuses. The writer cannot know the deflated size before writing, so when its own
    /// validation refuses the deflated pack for expansion it writes the pack again with every entry stored. The
    /// result is deterministic: the same inputs always take the same path.
    @discardableResult
    public func write(sources: [PackSource], groups: [PackManifest.Group], packID: UUID = UUID(),
                      fixedDate: Date? = nil, to destination: URL) async throws(PackWriterError) -> ValidatedPack {
        do {
            return try await write(sources: sources, groups: groups, packID: packID, fixedDate: fixedDate, to: destination,
                                   storeText: false)
        } catch let .selfCheckFailed(rejection) where rejection.code == .expansionLimit {
            return try await write(sources: sources, groups: groups, packID: packID, fixedDate: fixedDate, to: destination,
                                   storeText: true)
        }
    }

    private func write(sources: [PackSource], groups: [PackManifest.Group], packID: UUID, fixedDate: Date?,
                       to destination: URL, storeText: Bool) async throws(PackWriterError) -> ValidatedPack {
        if (try? Durability.lstatInfo(destination)) != nil { throw .destinationExists }
        let createdAt = fixedDate ?? Date()

        // Pass 1: sizes and digests.
        var files: [PackManifest.File] = []
        for source in sources {
            let digest: CopyResult
            do { digest = try FileDigest.sha256(of: source.url, bufferSize: bufferSize) } catch {
                throw .io("reading a source: \(error)")
            }
            files.append(.init(path: source.path, size: digest.byteCount, sha256: digest.sha256,
                               mediaType: source.mediaType, kind: source.kind, groupID: source.groupID, order: source.order))
        }
        let manifest = PackManifest(packID: packID, createdAt: createdAt, generator: generator, files: files, groups: groups)
        do { try manifest.validate(limits: limits) } catch { throw .invalidInput(error) }
        let manifestBytes: Data
        do { manifestBytes = try manifest.encoded() } catch { throw .io("encoding the manifest") }
        // The reader's size limit, checked before anything is written (the self-check would refuse the pack anyway).
        guard manifestBytes.count <= limits.maxManifestBytes else {
            throw .invalidInput(PackRejection(.manifestTooLarge, "more than \(limits.maxManifestBytes) bytes"))
        }
        let digestBytes = Data((hex(SHA256.hash(data: manifestBytes)) + "\n").utf8)
        afterPassOne?()

        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).partial-\(UUID().uuidString)")
        do {
            let archive = try await Archive(url: temporary, accessMode: .create)
            try await addData(manifestBytes, path: PackLayout.manifestEntry, to: archive, date: createdAt)
            try await addData(digestBytes, path: PackLayout.manifestDigestEntry, to: archive, date: createdAt)

            // Pass 2: stream every source, hashing again.
            for (index, source) in sources.enumerated() {
                let reader = try SourceReader(url: source.url)
                try await archive.addEntry(
                    with: PackLayout.contentPrefix + source.path, type: .file,
                    uncompressedSize: Int64(files[index].size), modificationDate: createdAt, permissions: 0o644,
                    compressionMethod: PackWriter.compression(for: source.kind, storeText: storeText), bufferSize: bufferSize
                ) { position, size in
                    try reader.read(at: position, count: size)
                }
                guard try reader.finish() == (files[index].size, files[index].sha256) else {
                    throw PackWriterError.sourceChanged(index: index)
                }
            }
            try PackWriter.fullSync(temporary)
        } catch {
            Durability.removeTree(temporary)
            if let writerError = error as? PackWriterError { throw writerError }
            throw .io("writing the archive: \(error)")
        }

        // Self-check with the same reader the phone uses, then publish atomically.
        do {
            _ = try await PackReader(limits: limits, bufferSize: bufferSize).validate(temporary)
        } catch {
            Durability.removeTree(temporary)
            throw .selfCheckFailed(error)
        }
        do {
            try Durability.renameNoReplace(temporary, to: destination)
        } catch {
            Durability.removeTree(temporary)
            throw .io("publishing the pack: \(error)")
        }
        do {
            return try await PackReader(limits: limits, bufferSize: bufferSize).validate(destination)
        } catch {
            throw .selfCheckFailed(error)
        }
    }

    private func addData(_ data: Data, path: String, to archive: Archive, date: Date) async throws {
        try await archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), modificationDate: date,
                                   permissions: 0o644, compressionMethod: .none, bufferSize: bufferSize) { position, size in
            data.subdata(in: Int(position)..<Int(position) + size)
        }
    }

    static func fullSync(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw IntakeIOError("open") }
        defer { close(fd) }
        try Durability.fullSync(fd: fd)
    }
}

/// pread-based source for the library's provider closure, hashing what it hands out. The library asks for
/// consecutive ranges; anything else is treated as a changed source.
final class SourceReader: @unchecked Sendable {
    private let fd: Int32
    private var hasher = SHA256()
    private var next: Int64 = 0

    init(url: URL) throws {
        fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw IntakeIOError("open source") }
    }

    deinit { close(fd) }

    func read(at position: Int64, count: Int) throws -> Data {
        guard position == next else { throw PackWriterError.io("non-sequential read") }
        let bytes = try Durability.readExactly(fd: fd, count: count, at: UInt64(position))
        let data = Data(bytes)
        hasher.update(data: data)
        next += Int64(count)
        return data
    }

    func finish() throws -> (UInt64, String) {
        // A source that grew after pass 1 still has bytes left.
        var probe: UInt8 = 0
        let extra = pread(fd, &probe, 1, off_t(next))
        let size = extra > 0 ? UInt64(next) + 1 : UInt64(next)
        return (size, hex(hasher.finalize()))
    }
}
