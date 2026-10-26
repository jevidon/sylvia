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

/// Absolute paths with every symbolic link resolved by realpath(3), whether or not the path exists yet: the form
/// every containment check in this package compares (`BackupValidator.isInside` and `checkTree`,
/// `FileProtector.copyTree`).
///
/// Never Foundation's `standardizedFileURL` or `resolvingSymlinksInPath` for that: they drop a leading /private, but
/// only from a path that exists. Under /private/var (an iPhone's container and temporary folders, and the Mac's
/// temporary folder when it is named that way) an existing folder and a path inside it that does not exist then
/// have different prefixes (device run of 26 October 2026: a missing backup file reported as an unsafe path; review of
/// the same day, findings F1 and F3: a copy into its own source not refused, a dangling link reported as an unsafe
/// path). realpath(3) gives /private/var/... for a folder named either way.
enum CanonicalPath {
    /// realpath(3) of the deepest part of `url`'s path that exists, followed by the components below it that do not
    /// exist, as they are. nil if no part of the path resolves, or if a component that does not exist is `.` or `..`:
    /// where that leads depends on what is created later, so no containment check may place such a path.
    static func of(_ url: URL) -> String? {
        var existing = url.path.split(separator: "/").map(String.init)
        var missing: [String] = []
        while true {
            if let resolved = realPath("/" + existing.joined(separator: "/")) {
                guard !missing.contains(where: { $0 == "." || $0 == ".." }) else { return nil }
                return missing.reversed().reduce(resolved) { ($0.hasSuffix("/") ? $0 : $0 + "/") + $1 }
            }
            guard let last = existing.popLast() else { return nil }
            missing.append(last)
        }
    }

    /// The part of `path` below `root`, both canonical (`of`), or nil when `path` is not strictly below `root`.
    /// Compared byte by byte, as the file system names them: Swift's `String.hasPrefix` compares characters, and a
    /// name that begins with a combining mark joins the `/` before it into one character.
    static func relative(_ path: String, to root: String) -> String? {
        let prefix = Array(root.utf8) + (root.utf8.last == UInt8(ascii: "/") ? [] : [UInt8(ascii: "/")])
        let bytes = Array(path.utf8)
        guard bytes.count > prefix.count, bytes.starts(with: prefix) else { return nil }
        return String(decoding: bytes[prefix.count...], as: UTF8.self)
    }

    static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
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
