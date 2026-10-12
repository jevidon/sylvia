import Foundation
import SylviaIntakeCore

/// Stand-in for the product's ImportJob table (plan 8.2): a small JSON journal under the app's private
/// Application Support, replaced atomically on every change. The product keeps this in SQLite (GRDB); the
/// spike keeps it in a file so the extension package needs no database. The commit-intent sequence is the same.
public final class IntakeJournal: @unchecked Sendable {
    public enum Route: String, Codable, Sendable {
        case shareExtension = "share_extension"
        case openIn = "open_in"
        case documentsBundle = "documents_bundle"
        case documentPicker = "document_picker"
    }

    /// Spike subset of the plan 8.2 states that intake reaches.
    public enum State: String, Codable, Sendable {
        /// Commit intent recorded; bytes are being moved into private staging.
        case accepting
        /// Bytes are owned by Sylvia but not yet trusted (plan 8.2 `staged`).
        case staged
        /// Same bytes as an existing job: the user decides (plan 8.2 `needs_review`).
        case needsReview = "needs_review"
        /// Recovery found neither the source nor the destination (should not happen; reported, never hidden).
        case failedFinal = "failed_final"
    }

    public struct StagedItem: Codable, Equatable, Sendable {
        public var relativePath: String       // relative to the job's staged directory
        public var byteCount: UInt64
        public var sha256: String
        public var contentType: String?
        public var originalFilename: String?

        public init(relativePath: String, byteCount: UInt64, sha256: String, contentType: String?, originalFilename: String?) {
            self.relativePath = relativePath
            self.byteCount = byteCount
            self.sha256 = sha256
            self.contentType = contentType
            self.originalFilename = originalFilename
        }
    }

    public struct Job: Codable, Equatable, Sendable {
        public var jobID: UUID
        public var route: Route
        public var state: State
        public var handoffID: UUID?
        public var stagedDirectory: String    // relative to the staging root
        public var items: [StagedItem]
        public var duplicateOf: UUID?
        public var createdAt: Date

        public init(jobID: UUID, route: Route, state: State, handoffID: UUID?, stagedDirectory: String,
                    items: [StagedItem], duplicateOf: UUID?, createdAt: Date) {
            self.jobID = jobID
            self.route = route
            self.state = state
            self.handoffID = handoffID
            self.stagedDirectory = stagedDirectory
            self.items = items
            self.duplicateOf = duplicateOf
            self.createdAt = createdAt
        }
    }

    public struct CleanupRecord: Codable, Equatable, Sendable {
        public var directoryName: String
        public var reason: String
        public var byteCount: UInt64
        public var removedAt: Date
    }

    struct Contents: Codable {
        var schemaVersion = 1
        var jobs: [Job] = []
        var cleanups: [CleanupRecord] = []
    }

    public let url: URL
    private let lock = NSLock()
    private var contents: Contents

    public init(url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            contents = try decoder.decode(Contents.self, from: AtomicFile.readSmall(url, limit: 64 << 20))
        } else {
            contents = Contents()
        }
    }

    public var jobs: [Job] { lock.withLock { contents.jobs } }
    public var cleanups: [CleanupRecord] { lock.withLock { contents.cleanups } }

    public func job(id: UUID) -> Job? { lock.withLock { contents.jobs.first { $0.jobID == id } } }
    public func job(handoffID: UUID) -> Job? { lock.withLock { contents.jobs.first { $0.handoffID == handoffID } } }

    /// Inserts or replaces a job and makes the journal durable before returning.
    public func upsert(_ job: Job) throws {
        try mutate { contents in
            if let index = contents.jobs.firstIndex(where: { $0.jobID == job.jobID }) {
                contents.jobs[index] = job
            } else {
                contents.jobs.append(job)
            }
        }
    }

    public func recordCleanup(_ record: CleanupRecord) throws {
        try mutate { $0.cleanups.append(record) }
    }

    /// Moves a job out of `accepting`: `needs_review` if another job already holds any of the same bytes,
    /// otherwise `staged`. Every route uses this, so duplicate handling is identical across routes (T08).
    public func finishStaging(jobID: UUID) throws -> Job {
        try mutate { contents in
            guard let index = contents.jobs.firstIndex(where: { $0.jobID == jobID }) else {
                throw HandoffFailure.writeFailed("unknown job")
            }
            var job = contents.jobs[index]
            let digests = Set(job.items.map(\.sha256))
            let earlier = contents.jobs.first { other in
                other.jobID != jobID && (other.state == .staged || other.state == .needsReview)
                    && !digests.isDisjoint(with: other.items.map(\.sha256))
            }
            job.state = earlier == nil ? .staged : .needsReview
            job.duplicateOf = earlier?.jobID
            contents.jobs[index] = job
            return job
        }
    }

    @discardableResult
    private func mutate<T>(_ change: (inout Contents) throws -> T) throws -> T {
        try lock.withLock {
            var copy = contents
            let result = try change(&copy)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            encoder.dateEncodingStrategy = .iso8601
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try AtomicFile.write(try encoder.encode(copy), to: url, policy: .replace)
            contents = copy
            return result
        }
    }
}
