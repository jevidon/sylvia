import Foundation

/// Durable storage for captures and their retained excerpts.
public protocol CaptureStore: Sendable {
    /// Writes the record durably. Returns only after the write is on disk; throws otherwise.
    func commit(_ record: CaptureRecord) throws
    /// Atomically: returns the stored record with the same idempotency key, or durably writes `record` and returns
    /// it. Returns only after the write is on disk; throws otherwise.
    func insert(_ record: CaptureRecord) throws -> CaptureRecord
    func record(_ id: UUID) throws -> CaptureRecord?
    func all() throws -> [CaptureRecord]
    /// Where the retained excerpt of a capture lives (retained-knowledge storage, plan 10.2, 17.1).
    func excerptURL(for id: UUID) -> URL
}

/// One JSON file per capture, written with `DurableFile` (temporary file, full sync, rename).
public final class FileCaptureStore: CaptureStore, @unchecked Sendable {
    public let directory: URL
    private let lock = NSLock()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    public init(directory: URL) throws {
        self.directory = directory
        // Class C, as every file written inside them (ADR-0007 decision 4; review R5-04).
        try DurableFile.createDirectory(directory.appendingPathComponent("captures"))
        try DurableFile.createDirectory(directory.appendingPathComponent("excerpts"))
    }

    private func url(_ id: UUID) -> URL { directory.appendingPathComponent("captures/\(id.uuidString).json") }

    /// The file that holds a capture record (diagnostics: its file-protection class on the device).
    public func recordURL(for id: UUID) -> URL { url(id) }

    public func commit(_ record: CaptureRecord) throws {
        lock.lock()
        defer { lock.unlock() }
        try DurableFile.write(try encoder.encode(record), to: url(record.id))
    }

    public func insert(_ record: CaptureRecord) throws -> CaptureRecord {
        lock.lock()
        defer { lock.unlock() }
        // A linear scan is enough for the spike; the product store has a unique index on the key (plan 11.1).
        if let existing = try unlockedAll().first(where: { $0.idempotencyKey == record.idempotencyKey }) { return existing }
        try DurableFile.write(try encoder.encode(record), to: url(record.id))
        return record
    }

    public func record(_ id: UUID) throws -> CaptureRecord? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url(id)) else { return nil }
        return try decoder.decode(CaptureRecord.self, from: data)
    }

    public func all() throws -> [CaptureRecord] {
        lock.lock()
        defer { lock.unlock() }
        return try unlockedAll()
    }

    private func unlockedAll() throws -> [CaptureRecord] {
        let files = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("captures"), includingPropertiesForKeys: nil)
        return try files.filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".") }
            .map { try decoder.decode(CaptureRecord.self, from: Data(contentsOf: $0)) }
            .sorted { ($0.createdAtMs, $0.id.uuidString) < ($1.createdAtMs, $1.id.uuidString) }
    }

    public func excerptURL(for id: UUID) -> URL { directory.appendingPathComponent("excerpts/\(id.uuidString).m4a") }
}
