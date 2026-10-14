import Darwin
import Foundation

public enum DurableFileError: Error, Equatable, Sendable {
    case open(path: String, errno: Int32)
    case write(path: String, errno: Int32)
    case sync(path: String, errno: Int32)
    case rename(errno: Int32)
    /// The file does not carry the requested protection class, or the class has no mapping (ADR-0015 TM-F2).
    case protection(path: String, expected: String, actual: String)
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
        _ = try urlFileProtection(protection, for: url) // an unmapped class is refused before anything is created
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: protection])
    }

    /// Sets the protection class of an existing file and reads it back (ADR-0015 TM-F2). The file protection resource
    /// key takes a URLFileProtection: a FileProtectionType passed there is accepted without error and ignored (shown on
    /// the host, Docs/Stage0/evidence/M0-threat-model/protection-key-probe.log), so the class is mapped explicitly, and
    /// a class with no mapping is an error, never a weaker class. The iOS Simulator ignores file protection (it logs
    /// "ignoring unsupported value" and reads back class C whatever was set), so only a device shows the class; a
    /// readback that names another class is an error everywhere.
    public static func applyProtection(_ protection: FileProtectionType, to url: URL) throws {
        let wanted = try urlFileProtection(protection, for: url)
        var values = URLResourceValues()
        values.fileProtection = wanted
        var item = url
        try item.setResourceValues(values)
        // A fresh URL, so the readback is not a cached resource value.
        let fresh = URL(fileURLWithPath: url.path)
        let actual = try fresh.resourceValues(forKeys: [.fileProtectionKey]).fileProtection
        guard actual == wanted || (actual == nil && platformIgnoresProtection) else {
            throw DurableFileError.protection(path: url.lastPathComponent, expected: wanted.rawValue,
                                              actual: actual?.rawValue ?? "none reported")
        }
    }

    /// The resource value for a class: A, B and C only (ADR-0015 TM-F2).
    static func urlFileProtection(_ protection: FileProtectionType, for url: URL) throws -> URLFileProtection {
        switch protection {
        case .complete: return .complete
        case .completeUnlessOpen: return .completeUnlessOpen
        case .completeUntilFirstUserAuthentication: return .completeUntilFirstUserAuthentication
        default:
            throw DurableFileError.protection(path: url.lastPathComponent, expected: "class A, B or C",
                                              actual: protection.rawValue)
        }
    }

    /// True only in the iOS Simulator, which may report no class at all.
    static var platformIgnoresProtection: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
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
