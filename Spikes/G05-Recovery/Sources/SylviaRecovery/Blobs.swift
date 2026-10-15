import Foundation
import GRDB

/// Content-addressed store for retained excerpt audio (permanent knowledge, plan 17.1), with
/// retention leases so cleanup cannot remove a blob an export is copying (plan 17.4).
///
/// Every operation that creates, deletes or leases blob files runs inside the single database
/// writer, so "is this blob referenced or leased?" and "delete the file" are serialized with
/// lease acquisition and with the insert that references a new blob.
public struct BlobStore: Sendable {
    public let store: LibraryStore

    public init(_ store: LibraryStore) { self.store = store }

    public func url(sha256: String, fileExtension: String) -> URL {
        store.layout.excerptBlobsDirectory.appending(path: "\(sha256).\(fileExtension)", directoryHint: .notDirectory)
    }

    /// Writes `data` (if not already present) and inserts the RetainedExcerpt row in one writer
    /// access. The file is flushed before the row commits, so a committed row never points at a
    /// missing blob; a crash in between leaves an unreferenced file that `collectGarbage` removes.
    @discardableResult
    public func saveRetainedExcerpt(id: String = EntityID.make(), captureID: String, data: Data, mediaType: String,
                                    fileExtension: String, sourceRangesJSON: String, clipDurationMs: Int64) throws -> String {
        let sha = Digest.sha256Hex(data)
        let destination = url(sha256: sha, fileExtension: fileExtension)
        return try store.pool.write { db in
            if !FileManager.default.fileExists(atPath: destination.path) {
                try DurableFile.writeDurably(data, to: destination, staging: store.layout.stagingDirectory,
                                             protector: store.protector)
            }
            try store.insertJournaled(db, "retained_excerpt", id: id, [
                "id": id, "capture_id": captureID, "blob_sha256": sha, "byte_count": Int64(data.count),
                "media_type": mediaType, "file_extension": fileExtension, "source_ranges_json": sourceRangesJSON,
                "clip_duration_ms": clipDurationMs, "export_state": "preserved", "created_at_ms": store.clock.nowMillis(),
            ])
            return sha
        }
    }

    // MARK: Leases

    /// Leases every blob currently referenced by a RetainedExcerpt. Returns the leased digests.
    public func leaseAllReferenced(holder: String, ttlMs: Int64) throws -> Set<String> {
        try store.pool.write { db in
            let shas = try String.fetchAll(db, sql: "SELECT DISTINCT blob_sha256 FROM retained_excerpt")
            try insertLeases(db, shas: shas, holder: holder, ttlMs: ttlMs)
            return Set(shas)
        }
    }

    /// Leases `blobs` after checking each file still exists. Throws `.missingBlob` otherwise.
    public func lease(_ blobs: [(sha256: String, fileExtension: String)], holder: String, ttlMs: Int64) throws {
        try store.pool.write { db in
            for blob in blobs where !FileManager.default.fileExists(atPath: url(sha256: blob.sha256, fileExtension: blob.fileExtension).path) {
                throw BackupError.missingBlob(blob.sha256)
            }
            try insertLeases(db, shas: blobs.map(\.sha256), holder: holder, ttlMs: ttlMs)
        }
    }

    public func releaseLeases(holder: String) throws {
        try store.pool.write { db in
            try db.execute(sql: "DELETE FROM retention_lease WHERE holder = ?", arguments: [holder])
        }
    }

    private func insertLeases(_ db: Database, shas: [String], holder: String, ttlMs: Int64) throws {
        let now = store.clock.nowMillis()
        for sha in shas {
            try LibraryStore.insert(db, "retention_lease", [
                "id": EntityID.make(), "blob_sha256": sha, "holder": holder,
                "acquired_at_ms": now, "expires_at_ms": now + ttlMs,
            ])
        }
    }

    // MARK: Cleanup

    public struct CollectionResult: Sendable, Equatable {
        public var removed: [String] = []
        public var keptBecauseLeased: [String] = []
    }

    /// Removes blob files that no RetainedExcerpt references and no unexpired lease holds.
    @discardableResult
    public func collectGarbage() throws -> CollectionResult {
        try store.pool.write { db in
            let referenced = Set(try String.fetchAll(db, sql: "SELECT DISTINCT blob_sha256 FROM retained_excerpt"))
            let leased = Set(try String.fetchAll(db, sql: "SELECT DISTINCT blob_sha256 FROM retention_lease WHERE expires_at_ms > ?",
                                                 arguments: [store.clock.nowMillis()]))
            var result = CollectionResult()
            let files = try FileManager.default.contentsOfDirectory(at: store.layout.excerptBlobsDirectory,
                                                                    includingPropertiesForKeys: nil)
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let sha = String(file.lastPathComponent.prefix { $0 != "." })
                if referenced.contains(sha) { continue }
                if leased.contains(sha) { result.keptBecauseLeased.append(sha); continue }
                try FileManager.default.removeItem(at: file)
                result.removed.append(sha)
            }
            return result
        }
    }

    /// Explicit "Remove excerpt audio" (plan 17.2) for one capture's excerpts: deletes the rows;
    /// the files go at the next `collectGarbage` unless leased.
    public func deleteRetainedExcerpts(captureID: String) throws {
        try store.pool.write { db in
            let ids = try String.fetchAll(db, sql: "SELECT id FROM retained_excerpt WHERE capture_id = ?", arguments: [captureID])
            try db.execute(sql: "DELETE FROM retained_excerpt WHERE capture_id = ?", arguments: [captureID])
            for id in ids { try LibraryStore.journal(db, "retained_excerpt", id, "delete", at: store.clock.nowMillis()) }
        }
    }
}

/// Canonical cover thumbnails (plan 17.1, 17.3): one small image per edition, content-addressed
/// under `Library/Blobs/covers/<sha256>.<ext>` and referenced by
/// `edition.cover_thumbnail_sha256` / `cover_thumbnail_extension`. Kept with the knowledge and
/// included in every backup; removing original media never touches it. Larger or extra
/// thumbnails are rebuildable cache and not stored here.
public enum CoverStore {
    public static let allowedExtensions: Set<String> = ["jpg", "png", "heic"]

    public static func url(_ layout: LibraryLayout, sha256: String, fileExtension: String) -> URL {
        layout.coverBlobsDirectory.appending(path: "\(sha256).\(fileExtension)", directoryHint: .notDirectory)
    }

    /// Writes the thumbnail (if not already present) and points the edition at it in one writer
    /// access; the file is flushed before the row commits. Returns the digest.
    @discardableResult
    public static func setCoverThumbnail(_ store: LibraryStore, editionID: String, data: Data, fileExtension: String) throws -> String {
        guard allowedExtensions.contains(fileExtension), !data.isEmpty else {
            throw StoreError.invalid("cover thumbnail must be a non-empty jpg, png or heic")
        }
        let sha = Digest.sha256Hex(data)
        let destination = url(store.layout, sha256: sha, fileExtension: fileExtension)
        try store.pool.write { db in
            if !FileManager.default.fileExists(atPath: destination.path) {
                try DurableFile.writeDurably(data, to: destination, staging: store.layout.stagingDirectory,
                                             protector: store.protector)
            }
            try db.execute(sql: "UPDATE edition SET cover_thumbnail_sha256 = ?, cover_thumbnail_extension = ? WHERE id = ?",
                           arguments: [sha, fileExtension, editionID])
            guard db.changesCount == 1 else { throw StoreError.notFound(entity: "edition", id: editionID) }
            try LibraryStore.journal(db, "edition", editionID, "update", at: store.clock.nowMillis())
        }
        return sha
    }

    /// Distinct thumbnails referenced by editions, sorted by digest. Empty for a library whose
    /// schema predates `v2-edition-cover-thumbnail`.
    static func referenced(_ db: Database) throws -> [(sha256: String, fileExtension: String)] {
        guard try db.columns(in: "edition").contains(where: { $0.name == "cover_thumbnail_sha256" }) else { return [] }
        return try Row.fetchAll(db, sql: """
            SELECT DISTINCT cover_thumbnail_sha256, cover_thumbnail_extension FROM edition
            WHERE cover_thumbnail_sha256 IS NOT NULL ORDER BY cover_thumbnail_sha256
            """).map { ($0["cover_thumbnail_sha256"], $0["cover_thumbnail_extension"]) }
    }
}
