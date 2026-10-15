import Foundation
import Synchronization
import SylviaTransferClient
import SylviaTransferCore

/// Small durable JSON files: written to a temporary file, ordered to disk with F_BARRIERFSYNC, then
/// renamed over the old one, so a reader sees either the old or the new content, never a torn file.
///
/// On iOS every file and folder is created with `completeUntilFirstUserAuthentication`: authorized
/// background transfers must read and write job state while the phone is locked after its first unlock
/// (plan 18.1, ADR-0008). Before the first unlock nothing here is readable and the app shows an
/// unavailable state instead of downgrading protection.
public enum DurableFile {
    public static func createDirectory(_ url: URL) throws {
        var attributes: [FileAttributeKey: Any] = [:]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: attributes)
    }

    public static func write(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        var attributes: [FileAttributeKey: Any] = [:]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: attributes) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            let handle = try FileHandle(forWritingTo: temporary)
            defer { try? handle.close() }
            try handle.write(contentsOf: data)
            if fcntl(handle.fileDescriptor, F_BARRIERFSYNC) != 0 { try handle.synchronize() }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        guard rename(temporary.path, url.path) == 0 else {
            try? FileManager.default.removeItem(at: temporary)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    public static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try write(TransferJSON.encode(value), to: url)
    }

    /// Nil when the file does not exist; throws when it exists but cannot be read or decoded.
    public static func readJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try TransferJSON.decode(type, from: Data(contentsOf: url))
    }

    /// Whether a read failed because the file's contents are not accessible right now (data protection
    /// before the first unlock reports EPERM; a permission change EACCES) rather than because they are
    /// damaged. Such a failure must defer work, never count as "no data".
    public static func isAccessFailure(_ error: any Error) -> Bool {
        if error is DecodingError { return false }
        if let posix = error as? POSIXError { return posix.code == .EPERM || posix.code == .EACCES }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == CocoaError.fileReadNoPermission.rawValue { return true }
        if nsError.domain == NSPOSIXErrorDomain { return nsError.code == Int(EPERM) || nsError.code == Int(EACCES) }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError { return isAccessFailure(underlying) }
        return false
    }

    /// "not_accessible" or "damaged" (no paths or contents: this goes to the event log).
    public static func describeReadFailure(_ error: any Error) -> String {
        isAccessFailure(error) ? "not_accessible" : "damaged"
    }
}

/// A durable store whose file exists but could not be read (before the first unlock on iOS the file
/// system refuses class C files; or the file is damaged). Such a store is never treated as empty and
/// never written over: that would lose what the file holds (review finding R1-04).
public struct StoreUnreadable: Error, Equatable, Sendable {
    public var store: String
    public var reason: String
}

/// Paired sources: public data only (pin, endpoints, device ID). Tokens live in the Keychain.
public final class PairedSourceStore: Sendable {
    public let url: URL
    /// A failure while the file exists but cannot be read; then nothing is listed and nothing is written.
    private let sources: Mutex<Result<[PairedSource], StoreUnreadable>>

    public init(url: URL) throws {
        self.url = url
        try DurableFile.createDirectory(url.deletingLastPathComponent())
        sources = Mutex(Self.read(url))
    }

    private static func read(_ url: URL) -> Result<[PairedSource], StoreUnreadable> {
        do {
            return .success(try DurableFile.readJSON([PairedSource].self, from: url) ?? [])
        } catch {
            return .failure(StoreUnreadable(store: url.lastPathComponent, reason: DurableFile.describeReadFailure(error)))
        }
    }

    /// Reads the file again (after protected data became available). Returns whether it is readable now.
    @discardableResult
    public func reload() -> Bool {
        let fresh = Self.read(url)
        return sources.withLock { current in
            current = fresh
            if case .success = fresh { return true }
            return false
        }
    }

    public var unreadable: StoreUnreadable? {
        sources.withLock { if case .failure(let error) = $0 { error } else { nil } }
    }

    /// Every paired source; empty while the file cannot be read.
    public var all: [PairedSource] { sources.withLock { (try? $0.get()) ?? [] } }

    public func source(_ sourceID: String) -> PairedSource? { all.first { $0.sourceID == sourceID } }

    public func upsert(_ source: PairedSource) throws {
        try sources.withLock { current in
            var copy = try current.get()
            if let index = copy.firstIndex(where: { $0.sourceID == source.sourceID }) { copy[index] = source } else { copy.append(source) }
            try DurableFile.writeJSON(copy, to: url)
            current = .success(copy)
        }
    }

    public func remove(_ sourceID: String) throws {
        try sources.withLock { current in
            let copy = try current.get().filter { $0.sourceID != sourceID }
            try DurableFile.writeJSON(copy, to: url)
            current = .success(copy)
        }
    }
}

/// A persisted transfer job: one item version from one paired source (plan 6.4: jobs are persisted
/// before any work is scheduled).
public struct JobRecord: Codable, Hashable, Sendable {
    public enum State: String, Codable, Hashable, Sendable {
        /// Parts are being fetched by background download tasks.
        case downloading
        /// The version changed (412, 416, changed ETag): a new manifest is being fetched.
        case refreshing
        /// Stopped with a reason and a next step; verified parts are kept.
        case paused
        /// Every part verified; the full-file check and final rename are in progress (journalled).
        case assembling
        /// Every asset's full SHA-256 matched; waiting for the importer.
        case readyForImport = "ready_for_import"
        /// The importer recorded the import (exactly once).
        case imported
        /// The person cancelled; staging was deleted.
        case cancelled
    }

    public var formatVersion = 1
    public var jobID: String
    public var sourceID: String
    public var itemID: String
    /// Display only; never written to the event log.
    public var title: String
    public var itemVersionID: String
    public var state: State
    public var pauseReason: PauseReason?
    /// Index into the source's endpoints used for new tasks; advanced after transport failures.
    public var endpointIndex: Int
    /// Failed attempts per part ("<asset>:<index>") for the current version.
    public var failedAttempts: [String: Int]
    public var manifestRefreshes: Int
    public var createdAt: Date
    public var updatedAt: Date
    /// Idempotency keys of receipts sent to the Mac, by receipt state.
    public var receiptIDs: [String: String]
    /// The Mac acknowledged both receipts.
    public var receiptsAcknowledged = false
    /// The Mac's outbound queue entry this job delivers ("Send to device", read from /v1/device-inbox), or nil
    /// for an item the person picked from the catalog. Receipts name it, so the Mac's entry moves to
    /// "Downloaded to phone" and "Imported into Sylvia" (plan 15.1, 16.2).
    public var queueEntryID: String?

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case jobID = "job_id"
        case sourceID = "source_id"
        case itemID = "item_id"
        case title
        case itemVersionID = "item_version_id"
        case state
        case pauseReason = "pause_reason"
        case endpointIndex = "endpoint_index"
        case failedAttempts = "failed_attempts"
        case manifestRefreshes = "manifest_refreshes"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case receiptIDs = "receipt_ids"
        case receiptsAcknowledged = "receipts_acknowledged"
        case queueEntryID = "queue_entry_id"
    }

    public init(
        jobID: String, sourceID: String, itemID: String, title: String, itemVersionID: String, now: Date, queueEntryID: String? = nil
    ) {
        self.queueEntryID = queueEntryID
        self.jobID = jobID
        self.sourceID = sourceID
        self.itemID = itemID
        self.title = title
        self.itemVersionID = itemVersionID
        state = .downloading
        pauseReason = nil
        endpointIndex = 0
        failedAttempts = [:]
        manifestRefreshes = 0
        createdAt = now
        updatedAt = now
        receiptIDs = [:]
    }

    /// Jobs that still want bytes from the network.
    public var wantsParts: Bool { state == .downloading }
    public var isTerminal: Bool { state == .imported || state == .cancelled }
}

/// Job folders: `<root>/jobs/<job_id>/{job.json, manifest.json, staging/<asset_id>/...}`.
public struct JobStore: Sendable {
    public let root: URL

    public init(root: URL) throws {
        self.root = root
        try DurableFile.createDirectory(root.appendingPathComponent("jobs", isDirectory: true))
    }

    public func directory(_ jobID: String) -> URL {
        root.appendingPathComponent("jobs", isDirectory: true).appendingPathComponent(jobID, isDirectory: true)
    }

    public func stagingRoot(_ jobID: String) -> URL { directory(jobID).appendingPathComponent("staging", isDirectory: true) }

    public func save(_ job: JobRecord) throws {
        try DurableFile.createDirectory(directory(job.jobID))
        try DurableFile.writeJSON(job, to: directory(job.jobID).appendingPathComponent("job.json"))
    }

    public func saveManifest(_ manifest: TransferManifest, jobID: String) throws {
        try DurableFile.createDirectory(directory(jobID))
        try DurableFile.writeJSON(manifest, to: directory(jobID).appendingPathComponent("manifest.json"))
    }

    /// Reads the manifest back and validates it again (it decides which bytes are accepted).
    public func loadManifest(for job: JobRecord) throws -> TransferManifest {
        let data = try Data(contentsOf: directory(job.jobID).appendingPathComponent("manifest.json"))
        let manifest = try ManifestValidator.decodeAndValidate(data, expecting: .init(sourceID: job.sourceID, itemID: job.itemID))
        guard manifest.itemVersionID == job.itemVersionID else { throw ManifestError.malformed }
        return manifest
    }

    /// Every readable job. A folder whose job.json is missing or damaged is reported in `unreadable`, not
    /// deleted: it may hold verified bytes a later build can recover. A job.json (or the jobs folder) that
    /// exists but is not accessible right now (before the first unlock) is reported in `inaccessible`: the
    /// caller must not act on the jobs at all then, because the list is incomplete.
    public func loadAll() -> (jobs: [JobRecord], unreadable: [String], inaccessible: [String]) {
        let folder = root.appendingPathComponent("jobs", isDirectory: true)
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        } catch {
            return ([], [], ["jobs"])
        }
        var jobs: [JobRecord] = []
        var unreadable: [String] = []
        var inaccessible: [String] = []
        for name in names.sorted() where CanonicalID.isValid(name) {
            let url = folder.appendingPathComponent(name, isDirectory: true).appendingPathComponent("job.json")
            do {
                if let job = try DurableFile.readJSON(JobRecord.self, from: url), job.jobID == name {
                    jobs.append(job)
                } else {
                    unreadable.append(name)
                }
            } catch {
                if DurableFile.isAccessFailure(error) { inaccessible.append(name) } else { unreadable.append(name) }
            }
        }
        return (jobs, unreadable, inaccessible)
    }

    public func deleteStaging(_ jobID: String) {
        try? FileManager.default.removeItem(at: stagingRoot(jobID))
    }
}

/// Append-only evidence log (JSON lines). Holds identifiers, counts, codes and addresses only: never
/// tokens, invitation secrets, titles or file paths (plan 18.1).
public final class TransferEventLog: Sendable {
    public struct Entry: Codable, Hashable, Sendable {
        /// RFC 3339 UTC with milliseconds, to line events up with the source's request log.
        public var time: String
        public var event: String
        public var fields: [String: String]
    }

    public let url: URL
    private let recent = Mutex<[Entry]>([])
    private let writer = Mutex(())

    public init(url: URL) throws {
        self.url = url
        try DurableFile.createDirectory(url.deletingLastPathComponent())
        if !FileManager.default.fileExists(atPath: url.path) {
            var attributes: [FileAttributeKey: Any] = [:]
            #if os(iOS)
            attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
            #endif
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: attributes)
        }
    }

    public func record(_ event: String, _ fields: [String: String] = [:]) {
        let stamp = Date().formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: TimeZone(identifier: "UTC")!))
        let entry = Entry(time: stamp, event: event, fields: fields)
        recent.withLock { list in
            list.append(entry)
            if list.count > 500 { list.removeFirst(list.count - 500) }
        }
        guard var line = try? TransferJSON.encode(entry) else { return }
        line.append(0x0A)
        writer.withLock { _ in
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        }
    }

    public var recentEntries: [Entry] { recent.withLock { $0 } }

    /// Every entry on disk (tests and evidence export).
    public func allEntries() -> [Entry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return data.split(separator: 0x0A).compactMap { try? TransferJSON.decode(Entry.self, from: Data($0)) }
    }
}
