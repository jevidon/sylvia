import CryptoKit
import Darwin
import Foundation

public struct CopyResult: Sendable, Equatable {
    public let byteCount: UInt64
    public let sha256: String
}

public enum CopyFailure: Error, Equatable, CustomStringConvertible, Sendable {
    case sourceNotRegularFile
    /// A folder offered as a file, for example an EPUB stored unpacked as a package directory.
    case sourceIsFolder
    case sourceChangedDuringCopy
    case lengthMismatch(expected: UInt64, actual: UInt64)
    case exceedsLimit(limit: UInt64)
    case cancelled

    public var description: String {
        switch self {
        case .sourceNotRegularFile: "source is not a regular file"
        case .sourceIsFolder: "source is a folder, not a file"
        case .sourceChangedDuringCopy: "source changed while it was being copied"
        case let .lengthMismatch(expected, actual): "expected \(expected) bytes, copied \(actual)"
        case let .exceedsLimit(limit): "source exceeds the \(limit)-byte limit"
        case .cancelled: "cancelled"
        }
    }
}

/// Copies a file into a new destination with one fixed-size buffer, hashing as it goes. Memory use is
/// the buffer plus constant overhead whatever the file size; the file is never read into memory.
public struct StreamingCopier: Sendable {
    public static let defaultBufferSize = 1 << 20

    public let bufferSize: Int
    public let faults: any FaultInjecting

    public init(bufferSize: Int = StreamingCopier.defaultBufferSize, faults: any FaultInjecting = NoFaults()) {
        precondition(bufferSize > 0)
        self.bufferSize = bufferSize
        self.faults = faults
    }

    /// - Parameters:
    ///   - expectedLength: when known (for example from the provider), the copy must produce exactly this many bytes.
    ///   - limit: upper bound enforced while streaming when the size is not known in advance (plan 8.3).
    ///   - isCancelled: polled between chunks.
    ///   - progress: called after each chunk with the running byte count.
    public func copy(
        from source: URL,
        toNewFile destination: URL,
        expectedLength: UInt64? = nil,
        limit: UInt64 = .max,
        isCancelled: () -> Bool = { false },
        progress: (UInt64) -> Void = { _ in }
    ) throws -> CopyResult {
        try faults.reach(.openSource)
        // O_NONBLOCK so a FIFO or device cannot block the open; cleared again once it is known to be a regular file.
        let input = open(source.path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
        guard input >= 0 else { throw IntakeIOError("open source") }
        defer { close(input) }
        var before = stat()
        guard fstat(input, &before) == 0 else { throw IntakeIOError("fstat source") }
        guard !before.isDirectory else { throw CopyFailure.sourceIsFolder }
        guard before.isRegularFile else { throw CopyFailure.sourceNotRegularFile }
        let flags = fcntl(input, F_GETFL)
        guard flags >= 0, fcntl(input, F_SETFL, flags & ~O_NONBLOCK) == 0 else { throw IntakeIOError("fcntl source") }
        if UInt64(before.st_size) > limit { throw CopyFailure.exceedsLimit(limit: limit) }

        try faults.reach(.createDestination)
        let output = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard output >= 0 else { throw IntakeIOError("create destination") }
        var outputOpen = true
        defer { if outputOpen { close(output) } }

        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { buffer.deallocate() }
        var hasher = SHA256()
        var total: UInt64 = 0
        while true {
            if isCancelled() { throw CopyFailure.cancelled }
            try faults.reach(.readChunk)
            let n = try Durability.readSome(fd: input, into: buffer)
            if n == 0 { break }
            total += UInt64(n)
            if total > limit { throw CopyFailure.exceedsLimit(limit: limit) }
            if let expectedLength, total > expectedLength {
                throw CopyFailure.lengthMismatch(expected: expectedLength, actual: total)
            }
            let chunk = UnsafeRawBufferPointer(rebasing: buffer[0..<n])
            hasher.update(bufferPointer: chunk)
            try faults.reach(.writeChunk)
            try Durability.writeAll(fd: output, chunk)
            progress(total)
        }

        try faults.reach(.syncItem)
        try Durability.fullSync(fd: output)
        try faults.reach(.closeItem)
        outputOpen = false
        guard close(output) == 0 else { throw IntakeIOError("close destination") }

        try faults.reach(.verifyItem)
        if let expectedLength, total != expectedLength {
            throw CopyFailure.lengthMismatch(expected: expectedLength, actual: total)
        }
        var after = stat()
        guard fstat(input, &after) == 0 else { throw IntakeIOError("fstat source") }
        if after.st_size != before.st_size || UInt64(after.st_size) != total
            || after.st_mtimespec.tv_sec != before.st_mtimespec.tv_sec
            || after.st_mtimespec.tv_nsec != before.st_mtimespec.tv_nsec {
            throw CopyFailure.sourceChangedDuringCopy
        }
        return CopyResult(byteCount: total, sha256: hex(hasher.finalize()))
    }
}

/// Streams a file through SHA-256 with one fixed buffer.
public enum FileDigest {
    public static func sha256(of url: URL, bufferSize: Int = 1 << 20) throws -> CopyResult {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { throw IntakeIOError("open") }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw IntakeIOError("fstat") }
        guard info.isRegularFile else { throw CopyFailure.sourceNotRegularFile }
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { buffer.deallocate() }
        var hasher = SHA256()
        var total: UInt64 = 0
        while true {
            let n = try Durability.readSome(fd: fd, into: buffer)
            if n == 0 { break }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: buffer[0..<n]))
            total += UInt64(n)
        }
        return CopyResult(byteCount: total, sha256: hex(hasher.finalize()))
    }
}

public func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
    var out = ""
    out.reserveCapacity(64)
    for byte in bytes {
        out.append(hexDigits[Int(byte >> 4)])
        out.append(hexDigits[Int(byte & 0x0F)])
    }
    return out
}

private let hexDigits: [Character] = Array("0123456789abcdef")

public func isLowercaseSHA256Hex(_ s: String) -> Bool {
    s.utf8.count == 64 && s.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
}
