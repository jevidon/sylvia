import Darwin
import Foundation

/// A failed system call. Carries the operation and errno only: file paths and names are never part of an
/// error description, because errors end up in logs (plan 18.1).
public struct IntakeIOError: Error, Equatable, CustomStringConvertible, Sendable {
    public let operation: String
    public let code: Int32

    public init(_ operation: String, code: Int32 = errno) {
        self.operation = operation
        self.code = code
    }

    public var isOutOfSpace: Bool { code == ENOSPC || code == EDQUOT }

    public var description: String {
        "\(operation) failed: \(String(cString: strerror(code))) (errno \(code))"
    }
}

/// Durable-write primitives. On Apple platforms fsync(2) hands data to the drive but does not flush the
/// drive's cache; F_FULLFSYNC does. Every "durable" step in this spike uses `fullSync`.
public enum Durability {
    public static func fullSync(fd: Int32) throws {
        if fcntl(fd, F_FULLFSYNC) == 0 { return }
        // Some file systems (for example network or FUSE mounts) do not support F_FULLFSYNC.
        let fullSyncErrno = errno
        guard fullSyncErrno == ENOTSUP || fullSyncErrno == EINVAL || fullSyncErrno == ENOTTY else {
            throw IntakeIOError("F_FULLFSYNC", code: fullSyncErrno)
        }
        guard fsync(fd) == 0 else { throw IntakeIOError("fsync") }
    }

    /// Makes a directory's entries (creations, renames, removals) durable.
    public static func syncDirectory(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw IntakeIOError("open directory") }
        defer { close(fd) }
        try fullSync(fd: fd)
    }

    /// Creates a directory that must not already exist (mode 0700), then makes its parent's entry durable.
    public static func createFreshDirectory(_ url: URL) throws {
        guard mkdir(url.path, 0o700) == 0 else { throw IntakeIOError("mkdir") }
        try syncDirectory(url.deletingLastPathComponent())
    }

    /// Renames without replacing an existing destination (renamex_np RENAME_EXCL), then syncs the parent.
    public static func renameNoReplace(_ from: URL, to: URL) throws {
        guard renamex_np(from.path, to.path, UInt32(RENAME_EXCL)) == 0 else { throw IntakeIOError("rename") }
        try syncDirectory(to.deletingLastPathComponent())
    }

    /// Writes all bytes, retrying on EINTR and short writes.
    public static func writeAll(fd: Int32, _ buffer: UnsafeRawBufferPointer) throws {
        var offset = 0
        while offset < buffer.count {
            let n = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
            if n < 0 {
                if errno == EINTR { continue }
                throw IntakeIOError("write")
            }
            offset += n
        }
    }

    /// Reads up to `buffer.count` bytes, retrying on EINTR. Returns 0 at end of file.
    public static func readSome(fd: Int32, into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        while true {
            let n = read(fd, buffer.baseAddress!, buffer.count)
            if n >= 0 { return n }
            if errno == EINTR { continue }
            throw IntakeIOError("read")
        }
    }

    /// Reads exactly `count` bytes at `offset` (pread), or throws if the file is shorter.
    public static func readExactly(fd: Int32, count: Int, at offset: UInt64) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        var done = 0
        while done < count {
            let n = bytes.withUnsafeMutableBytes { raw in
                pread(fd, raw.baseAddress! + done, count - done, off_t(offset) + off_t(done))
            }
            if n < 0 {
                if errno == EINTR { continue }
                throw IntakeIOError("pread")
            }
            if n == 0 { throw IntakeIOError("pread", code: EIO) }
            done += n
        }
        return bytes
    }

    /// Removes a directory tree without following symbolic links. Best effort; returns false if anything remained.
    @discardableResult
    public static func removeTree(_ url: URL) -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            return !FileManager.default.fileExists(atPath: url.path)
        }
    }

    /// lstat wrapper: nil when the path does not exist.
    public static func lstatInfo(_ url: URL) throws -> stat? {
        var info = stat()
        if lstat(url.path, &info) == 0 { return info }
        if errno == ENOENT { return nil }
        throw IntakeIOError("lstat")
    }
}

public extension stat {
    var isRegularFile: Bool { (st_mode & S_IFMT) == S_IFREG }
    var isDirectory: Bool { (st_mode & S_IFMT) == S_IFDIR }
    var isSymbolicLink: Bool { (st_mode & S_IFMT) == S_IFLNK }
    var modificationDate: Date {
        Date(timeIntervalSince1970: TimeInterval(st_mtimespec.tv_sec) + TimeInterval(st_mtimespec.tv_nsec) / 1e9)
    }
}
