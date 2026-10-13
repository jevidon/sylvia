import Darwin
import Foundation

public enum DurableFileError: Error, Equatable, Sendable {
    case open(path: String, errno: Int32)
    case write(path: String, errno: Int32)
    case sync(path: String, errno: Int32)
    case rename(errno: Int32)
}

/// Durable writes for the spike's small stores: write a temporary file, F_FULLFSYNC it, rename it over the target
/// and sync the directory. A save is acknowledged only after this returns (I-03). The product uses GRDB with WAL
/// (G0.5); this is the minimum the G0.4 capture prototype needs to make "Saved" honest.
public enum DurableFile {
    /// File protection for every store on the capture path (capture records, checkpoints, retained excerpts and the
    /// directories that hold them; ADR-0007 decision 4, the class ADR-0012 sets for every persistent file): class C,
    /// encrypted until the first unlock after a restart and writable while locked afterwards. Applied explicitly, never
    /// left to the platform default, and never weaker (plan 18.1, T50; review R5-04).
    public static let lockedCaptureProtection: FileProtectionType = .completeUntilFirstUserAuthentication

    /// Creates `url` (and any missing parent) with the protection class, so files created inside it start with it.
    public static func createDirectory(_ url: URL, protection: FileProtectionType = lockedCaptureProtection) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: protection])
    }

    /// Sets the protection class of an existing file (the iOS Simulator ignores it: it logs "ignoring unsupported
    /// value" and reads back class C whatever was set, so only a device shows the class).
    public static func applyProtection(_ protection: FileProtectionType, to url: URL) throws {
        try (url as NSURL).setResourceValue(protection, forKey: .fileProtectionKey)
    }

    public static func write(_ data: Data, to url: URL, protection: FileProtectionType = lockedCaptureProtection) throws {
        let dir = url.deletingLastPathComponent()
        try createDirectory(dir, protection: protection)
        let temp = dir.appendingPathComponent(".tmp-\(UUID().uuidString)-\(url.lastPathComponent)")
        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { throw DurableFileError.open(path: temp.lastPathComponent, errno: errno) }
        var ok = false
        defer {
            close(fd)
            if !ok { unlink(temp.path) }
        }
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw DurableFileError.write(path: temp.lastPathComponent, errno: errno)
                }
                offset += n
            }
        }
        guard fcntl(fd, F_FULLFSYNC) == 0 || fsync(fd) == 0 else { throw DurableFileError.sync(path: temp.lastPathComponent, errno: errno) }
        try applyProtection(protection, to: temp)
        guard rename(temp.path, url.path) == 0 else { throw DurableFileError.rename(errno: errno) }
        ok = true
        try syncDirectory(dir)
    }

    public static func sync(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw DurableFileError.open(path: url.lastPathComponent, errno: errno) }
        defer { close(fd) }
        guard fcntl(fd, F_FULLFSYNC) == 0 || fsync(fd) == 0 else { throw DurableFileError.sync(path: url.lastPathComponent, errno: errno) }
    }

    public static func syncDirectory(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw DurableFileError.open(path: url.lastPathComponent, errno: errno) }
        defer { close(fd) }
        _ = fsync(fd)
    }
}
