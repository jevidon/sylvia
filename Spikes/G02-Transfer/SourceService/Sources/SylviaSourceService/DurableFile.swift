import Foundation
import SylviaTransferCore

/// Atomic JSON persistence for the Mac's small state files (index, devices, queue).
///
/// Write a temporary file, order it to disk with F_FULLFSYNC (these files are small and rarely
/// written, so the full flush is affordable), then rename over the old file. A crash leaves either the
/// old or the new file, never a torn one.
enum DurableFile {
    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try TransferJSON.encode(value)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.write(contentsOf: data)
            if fcntl(handle.fileDescriptor, F_FULLFSYNC) != 0 { try handle.synchronize() }
            try handle.close()
            guard rename(temporary.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
            // Make the rename itself durable: flush the directory entry.
            let directoryDescriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            if directoryDescriptor >= 0 {
                defer { close(directoryDescriptor) }
                if fcntl(directoryDescriptor, F_FULLFSYNC) != 0 { fsync(directoryDescriptor) }
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try TransferJSON.decode(type, from: Data(contentsOf: url))
    }
}
