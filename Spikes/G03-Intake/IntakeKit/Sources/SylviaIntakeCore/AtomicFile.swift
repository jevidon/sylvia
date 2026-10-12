import Darwin
import Foundation

/// Small-file atomic writes: temporary file in the same directory, F_FULLFSYNC, rename, directory sync.
/// A reader sees either no file or the complete file, never a prefix.
public enum AtomicFile {
    public static let temporaryMarker = ".tmp-"

    public enum ReplacePolicy: Sendable {
        /// Fails if the destination exists (used for commit points such as handoff.json).
        case noReplace
        /// Atomically replaces an existing destination (used for journals).
        case replace
    }

    public struct Steps: Sendable {
        public let write: HandoffWriteStep
        public let sync: HandoffWriteStep
        public let rename: HandoffWriteStep
        public let syncDirectory: HandoffWriteStep
        public init(write: HandoffWriteStep, sync: HandoffWriteStep, rename: HandoffWriteStep, syncDirectory: HandoffWriteStep) {
            self.write = write
            self.sync = sync
            self.rename = rename
            self.syncDirectory = syncDirectory
        }
    }

    public static func write(
        _ data: Data,
        to destination: URL,
        policy: ReplacePolicy,
        faults: any FaultInjecting = NoFaults(),
        steps: Steps? = nil
    ) throws {
        let directory = destination.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(destination.lastPathComponent + temporaryMarker + UUID().uuidString)
        var fd: Int32 = -1
        do {
            if let steps { try faults.reach(steps.write) }
            fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw IntakeIOError("create temporary") }
            try data.withUnsafeBytes { try Durability.writeAll(fd: fd, $0) }
            if let steps { try faults.reach(steps.sync) }
            try Durability.fullSync(fd: fd)
            let closing = fd
            fd = -1
            guard close(closing) == 0 else { throw IntakeIOError("close temporary") }
            if let steps { try faults.reach(steps.rename) }
            switch policy {
            case .noReplace:
                guard renamex_np(temporary.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
                    throw IntakeIOError("rename")
                }
            case .replace:
                guard rename(temporary.path, destination.path) == 0 else { throw IntakeIOError("rename") }
            }
        } catch let death as SimulatedProcessDeath {
            // A killed process runs no cleanup; leave the temporary file exactly as it is.
            throw death
        } catch {
            if fd >= 0 { close(fd) }
            unlink(temporary.path)
            throw error
        }
        // The rename happened. A failure from here on leaves a complete file whose directory entry may not be
        // durable yet; the caller treats that as "not committed" and must not report success.
        if let steps { try faults.reach(steps.syncDirectory) }
        try Durability.syncDirectory(directory)
    }

    /// Reads a small file, refusing symbolic links, non-regular files and anything larger than `limit`.
    public static func readSmall(_ url: URL, limit: Int) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw IntakeIOError("open") }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw IntakeIOError("fstat") }
        guard info.isRegularFile else { throw CopyFailure.sourceNotRegularFile }
        guard info.st_size <= off_t(limit) else { throw CopyFailure.exceedsLimit(limit: UInt64(limit)) }
        let bytes = try Durability.readExactly(fd: fd, count: Int(info.st_size), at: 0)
        return Data(bytes)
    }
}
