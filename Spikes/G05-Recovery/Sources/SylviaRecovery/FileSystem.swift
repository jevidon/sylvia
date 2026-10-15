import CryptoKit
import Darwin
import Foundation

/// File-system primitives with explicit flush and rename semantics.
public enum DurableFile {
    /// Flushes a file's contents to stable storage. Uses `F_FULLFSYNC` (Apple's fsync does not
    /// flush the drive cache); falls back to `fsync` if the file system rejects it.
    public static func sync(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw FileSystemError.posix("open", url.lastPathComponent, errno) }
        defer { close(fd) }
        if fcntl(fd, F_FULLFSYNC) != 0 {
            guard fsync(fd) == 0 else { throw FileSystemError.posix("fsync", url.lastPathComponent, errno) }
        }
    }

    /// Flushes a directory entry table so a completed `rename` survives (same fallback).
    public static func syncDirectory(_ url: URL) throws {
        try sync(url)
    }

    /// Atomic same-volume rename (`rename(2)`); fails if the destination is a non-empty directory.
    public static func rename(_ from: URL, to: URL) throws {
        guard Darwin.rename(from.path, to.path) == 0 else {
            throw FileSystemError.posix("rename", "\(from.lastPathComponent) -> \(to.lastPathComponent)", errno)
        }
    }

    /// Writes data to a new file with protection, flushes it, then renames it into place and
    /// flushes the parent directory. The temp file lives in `staging` (same volume).
    public static func writeDurably(_ data: Data, to destination: URL, staging: URL,
                                    protector: FileProtector) throws {
        let temp = staging.appending(path: "\(UUID().uuidString.lowercased()).tmp", directoryHint: .notDirectory)
        try protector.write(data, to: temp, atomic: false)
        do {
            try sync(temp)
            try rename(temp, to: destination)
            try syncDirectory(destination.deletingLastPathComponent())
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }
}

public enum FileSystemError: Error, CustomStringConvertible {
    case posix(String, String, Int32)

    public var description: String {
        switch self {
        case .posix(let op, let name, let code):
            return "\(op) \(name): \(String(cString: strerror(code))) (errno \(code))"
        }
    }
}

public enum Digest {
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256Hex(_ string: String) -> String {
        sha256Hex(Data(string.utf8))
    }

    public static func isHex64(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// Streams a file through SHA-256 in 1 MiB chunks; returns the digest and byte count.
    public static func sha256Hex(fileAt url: URL) throws -> (digest: String, byteCount: Int64) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var total: Int64 = 0
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            total += Int64(chunk.count)
        }
        return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), total)
    }
}

/// Free space available to this app, injectable so tests can simulate a full disk (plan 7.4).
public protocol StorageSpaceProbe: Sendable {
    func availableBytes(at url: URL) throws -> Int64
}

public struct SystemSpaceProbe: StorageSpaceProbe {
    public init() {}

    public func availableBytes(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let bytes = values.volumeAvailableCapacityForImportantUsage else {
            throw FileSystemError.posix("statfs", url.lastPathComponent, ENOTSUP)
        }
        return bytes
    }
}

public struct FixedSpaceProbe: StorageSpaceProbe {
    public let bytes: Int64
    public init(bytes: Int64) { self.bytes = bytes }
    public func availableBytes(at url: URL) throws -> Int64 { bytes }
}

extension FileManager {
    /// Byte size of a regular file, or 0 if it does not exist.
    func sizeOfFile(at url: URL) -> Int64 {
        guard let attributes = try? attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return 0 }
        return size.int64Value
    }
}
