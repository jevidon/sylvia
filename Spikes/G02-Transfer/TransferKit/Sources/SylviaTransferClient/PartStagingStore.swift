import CryptoKit
import Foundation
import SylviaTransferCore

/// Durable staging for one asset (plan 15.4, 15.5).
///
/// Layout under `<root>/<asset_id>/`:
///   staging.bin   sparse file of the asset's full length; verified parts are written at their offsets
///   journal.json  which parts are verified, for which bytes (index -> part SHA-256)
///   incoming/     part bodies being received; never read unless they passed validation
///   verified.bin  the finished file, present only after the full SHA-256 matched
///
/// A part is marked verified only after its bytes were re-hashed while being copied into
/// staging.bin and that write was ordered before the journal update (F_BARRIERFSYNC). Unverified
/// bytes are never appended to, or mixed into, verified ones. Storage need is the asset length
/// plus the parts in flight, not double the asset.
public struct PartStagingStore: Sendable {
    struct Journal: Codable, Equatable {
        var formatVersion = 1
        var itemVersionID: String
        var assetID: String
        var etag: String
        var sha256: String
        var length: Int64
        var partSize: Int64
        var verifiedParts: [String: String]
        var finalVerified: Bool

        enum CodingKeys: String, CodingKey {
            case formatVersion = "format_version"
            case itemVersionID = "item_version_id"
            case assetID = "asset_id"
            case etag
            case sha256
            case length
            case partSize = "part_size"
            case verifiedParts = "verified_parts"
            case finalVerified = "final_verified"
        }
    }

    public struct Reconciliation: Equatable, Sendable {
        public var keptParts: Int
        public var discardedParts: Int
    }

    public let directory: URL
    public private(set) var asset: TransferManifest.Asset
    private var journal: Journal

    public var stagingURL: URL { directory.appendingPathComponent("staging.bin") }
    public var verifiedURL: URL { directory.appendingPathComponent("verified.bin") }
    public var incomingDirectory: URL { directory.appendingPathComponent("incoming", isDirectory: true) }
    var journalURL: URL { directory.appendingPathComponent("journal.json") }

    public var isFinalVerified: Bool { journal.finalVerified }
    public func isVerified(_ index: Int) -> Bool { journal.verifiedParts[String(index)] != nil }
    public var verifiedPartCount: Int { journal.verifiedParts.count }
    public var verifiedBytes: Int64 {
        asset.parts.reduce(0) { $0 + (isVerified($1.index) ? $1.length : 0) }
    }

    /// Opens (or creates) staging for `asset`, keeping only previously verified parts whose bytes the
    /// new manifest describes identically (same index, offset, length and SHA-256). Parts from an older
    /// version that differ are discarded, so a version change can never produce a mixed file.
    public static func open(
        root: URL, asset: TransferManifest.Asset, itemVersionID: String, verifyExistingParts: Bool
    ) throws -> (PartStagingStore, Reconciliation) {
        let directory = root.appendingPathComponent(asset.assetID, isDirectory: true)
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directory.appendingPathComponent("incoming", isDirectory: true), withIntermediateDirectories: true)
        var store = PartStagingStore(
            directory: directory, asset: asset,
            journal: Journal(
                itemVersionID: itemVersionID, assetID: asset.assetID, etag: asset.etag, sha256: asset.sha256,
                length: asset.length, partSize: asset.partSize, verifiedParts: [:], finalVerified: false))
        // Bodies that were still arriving when the process stopped are unverified: drop them.
        for leftover in (try? fileManager.contentsOfDirectory(at: store.incomingDirectory, includingPropertiesForKeys: nil)) ?? [] {
            try? fileManager.removeItem(at: leftover)
        }

        let previous = try? TransferJSON.decode(Journal.self, from: Data(contentsOf: store.journalURL))
        var kept: [String: String] = [:]
        var previousCount = 0
        if let previous, previous.assetID == asset.assetID {
            previousCount = previous.verifiedParts.count
            if previous.finalVerified, previous.sha256 == asset.sha256, previous.length == asset.length,
                fileManager.fileExists(atPath: store.verifiedURL.path)
            {
                store.journal = previous
                store.journal.itemVersionID = itemVersionID
                store.journal.etag = asset.etag
                try store.writeJournal()
                return (store, Reconciliation(keptParts: previousCount, discardedParts: 0))
            }
            for (key, digest) in previous.verifiedParts {
                guard let index = Int(key), index >= 0, index < asset.parts.count else { continue }
                let part = asset.parts[index]
                let previousOffset = Int64(index) * previous.partSize
                let previousLength = min(previous.partSize, previous.length - previousOffset)
                if part.offset == previousOffset, part.length == previousLength, part.sha256 == digest {
                    kept[key] = digest
                }
            }
        }
        // A stop between moving staging.bin to verified.bin and recording that in the journal leaves the
        // bytes under the final name: move them back, so their parts are re-checked instead of lost.
        if !fileManager.fileExists(atPath: store.stagingURL.path), fileManager.fileExists(atPath: store.verifiedURL.path) {
            try? fileManager.moveItem(at: store.verifiedURL, to: store.stagingURL)
        }
        try? fileManager.removeItem(at: store.verifiedURL)

        // The staging file must exist with exactly the asset's length; otherwise nothing in it counts.
        let attributes = try? fileManager.attributesOfItem(atPath: store.stagingURL.path)
        if attributes == nil {
            kept = [:]
            guard fileManager.createFile(atPath: store.stagingURL.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let handle = try FileHandle(forUpdating: store.stagingURL)
        defer { try? handle.close() }
        if (attributes?[.size] as? NSNumber)?.int64Value != asset.length {
            try handle.truncate(atOffset: UInt64(asset.length))
        }
        store.journal.verifiedParts = kept
        if verifyExistingParts {
            for (key, digest) in kept {
                let part = asset.parts[Int(key)!]
                if try Self.hashRegion(handle: handle, offset: part.offset, length: part.length) != digest {
                    store.journal.verifiedParts.removeValue(forKey: key)
                }
            }
        }
        try store.writeJournal()
        let keptCount = store.journal.verifiedParts.count
        return (store, Reconciliation(keptParts: keptCount, discardedParts: max(0, previousCount - keptCount)))
    }

    private init(directory: URL, asset: TransferManifest.Asset, journal: Journal) {
        self.directory = directory
        self.asset = asset
        self.journal = journal
    }

    /// Copies a validated part body into place, re-hashing it on the way, then records it as verified.
    public mutating func commit(part: TransferManifest.Part, from incoming: URL) throws(StagingError) {
        defer { try? FileManager.default.removeItem(at: incoming) }
        guard asset.parts.indices.contains(part.index), asset.parts[part.index] == part else {
            throw .partNotInManifest
        }
        do {
            let source = try FileHandle(forReadingFrom: incoming)
            defer { try? source.close() }
            let destination = try FileHandle(forUpdating: stagingURL)
            defer { try? destination.close() }
            var hasher = SHA256()
            let (copied, extra) = try FileIO.copy(
                from: source.fileDescriptor, to: destination.fileDescriptor, at: part.offset, length: part.length, hasher: &hasher)
            guard copied == part.length, !extra, Hex.encode(hasher.finalize()) == part.sha256
            else { throw StagingError.digestMismatchOnCommit }
            try Self.barrier(destination)
        } catch let error as StagingError {
            throw error
        } catch {
            throw StagingError.classify(error, otherwise: .io(String(describing: type(of: error))))
        }
        journal.verifiedParts[String(part.index)] = part.sha256
        do { try writeJournal() } catch {
            journal.verifiedParts.removeValue(forKey: String(part.index))
            throw StagingError.classify(error, otherwise: .io("journal"))
        }
    }

    /// Re-hashes the whole staged file. On a match the file becomes `verified.bin`; on a mismatch every
    /// part is forgotten (the manifest was inconsistent) and nothing is handed off.
    public mutating func finalize() throws(StagingError) -> URL {
        guard journal.verifiedParts.count == asset.parts.count else { throw .incomplete }
        if journal.finalVerified { return verifiedURL }
        let digest: String
        do {
            let handle = try FileHandle(forReadingFrom: stagingURL)
            defer { try? handle.close() }
            digest = try Self.hashRegion(handle: handle, offset: 0, length: asset.length)
        } catch {
            throw .io("final hash")
        }
        guard constantTimeEquals(Array(digest.utf8), Array(asset.sha256.utf8)) else {
            journal.verifiedParts = [:]
            try? writeJournal()
            throw .finalDigestMismatch
        }
        do {
            try FileManager.default.moveItem(at: stagingURL, to: verifiedURL)
            journal.finalVerified = true
            try writeJournal()
        } catch {
            throw StagingError.classify(error, otherwise: .io("finalize"))
        }
        return verifiedURL
    }

    public func discard() throws { try FileManager.default.removeItem(at: directory) }

    private func writeJournal() throws {
        let data = try TransferJSON.encode(journal)
        let temporary = directory.appendingPathComponent("journal.json.tmp")
        // open(2) rather than FileManager.createFile, so a full disk surfaces as ENOSPC, not a generic error.
        let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try handle.write(contentsOf: data)
        try Self.barrier(handle)
        try handle.close()
        guard rename(temporary.path, journalURL.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    /// Orders earlier writes before later ones on Apple file systems without a full cache flush.
    static func barrier(_ handle: FileHandle) throws {
        if fcntl(handle.fileDescriptor, F_BARRIERFSYNC) != 0 {
            try handle.synchronize()
        }
    }

    static func hashRegion(handle: FileHandle, offset: Int64, length: Int64) throws -> String {
        try FileIO.sha256(of: handle.fileDescriptor, offset: offset, length: length) ?? ""
    }
}

/// Free space on the volume holding `url`, for the plan 15.4 reservation.
public enum VolumeSpace {
    /// The larger of "available for important usage" (on iOS it counts purgeable space the system frees
    /// for the app on demand, so it is the figure Apple recommends there) and the plain available capacity
    /// (a small macOS volume reports 0 for important usage while megabytes are free). Nil when unknown.
    /// A wrong estimate is still caught when a write fails with ENOSPC.
    public static func available(at url: URL) -> Int64? {
        // A URL caches resource values it has fetched once; a stored URL would keep reporting the free
        // space of its first query (found by the full-volume host test). Ask through a fresh URL every time.
        var fresh = URL(fileURLWithPath: url.path, isDirectory: true)
        fresh.removeAllCachedResourceValues()
        let values = try? fresh.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let important = values?.volumeAvailableCapacityForImportantUsage
        let plain = values?.volumeAvailableCapacity.map(Int64.init)
        switch (important, plain) {
        case (let a?, let b?): return max(a, b)
        case (let a?, nil): return a
        case (nil, let b?): return b
        case (nil, nil): return nil
        }
    }
}

public enum StagingError: Error, Equatable, Sendable {
    case partNotInManifest
    case digestMismatchOnCommit
    case incomplete
    case finalDigestMismatch
    /// The volume is full (ENOSPC or EDQUOT): retrying cannot help until space is freed.
    case noSpace
    case io(String)

    /// `.noSpace` when `error` (a POSIX error, or a Cocoa error with a POSIX underlying error) means the
    /// volume is full; `otherwise` for anything else.
    public static func classify(_ error: any Error, otherwise: StagingError) -> StagingError {
        isOutOfSpace(error) ? .noSpace : otherwise
    }

    public static func isOutOfSpace(_ error: any Error) -> Bool {
        if let posix = error as? POSIXError { return posix.code == .ENOSPC || posix.code == .EDQUOT }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == CocoaError.fileWriteOutOfSpace.rawValue { return true }
        if nsError.domain == NSPOSIXErrorDomain { return nsError.code == Int(ENOSPC) || nsError.code == Int(EDQUOT) }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError { return isOutOfSpace(underlying) }
        return false
    }
}

/// File reads and writes through one reused buffer with pread/pwrite.
///
/// FileHandle.read(upToCount:) returns a new autoreleased buffer per call; in a long-running task
/// without an autorelease pool drain those buffers accumulated to gigabytes during the 5 GiB test
/// (Docs/Stage0/evidence/G02-Transfer/faults/large-5GiB-transfer.log). These helpers allocate once.
enum FileIO {
    static let bufferSize = 1_048_576

    /// SHA-256 of `length` bytes at `offset`, or nil if the file is shorter.
    static func sha256(of descriptor: Int32, offset: Int64, length: Int64) throws -> String? {
        var hasher = SHA256()
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { buffer.deallocate() }
        var done: Int64 = 0
        while done < length {
            let want = Int(min(Int64(bufferSize), length - done))
            let read = pread(descriptor, buffer.baseAddress, want, off_t(offset + done))
            if read < 0 {
                if errno == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if read == 0 { return nil }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: buffer[0..<read]))
            done += Int64(read)
        }
        return Hex.encode(hasher.finalize())
    }

    /// Copies up to `length` bytes from the start of `source` to `offset` in `destination`, hashing
    /// them. Returns the bytes copied and whether `source` holds more than `length` bytes.
    static func copy(from source: Int32, to destination: Int32, at offset: Int64, length: Int64, hasher: inout SHA256) throws
        -> (copied: Int64, extra: Bool)
    {
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { buffer.deallocate() }
        var copied: Int64 = 0
        while copied < length {
            let want = Int(min(Int64(bufferSize), length - copied))
            let read = pread(source, buffer.baseAddress, want, off_t(copied))
            if read < 0 {
                if errno == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if read == 0 { break }
            let chunk = UnsafeRawBufferPointer(rebasing: buffer[0..<read])
            hasher.update(bufferPointer: chunk)
            var written = 0
            while written < read {
                let result = pwrite(destination, chunk.baseAddress! + written, read - written, off_t(offset + copied) + off_t(written))
                if result < 0 {
                    if errno == EINTR { continue }
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                written += result
            }
            copied += Int64(read)
        }
        var probe: UInt8 = 0
        let more = pread(source, &probe, 1, off_t(copied))
        return (copied, more > 0)
    }
}
