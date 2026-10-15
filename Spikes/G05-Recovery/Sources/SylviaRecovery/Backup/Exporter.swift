import Foundation
import GRDB

public struct ExportResult: Sendable {
    public let bundle: URL
    public let manifest: BackupManifest
    public let manifestSHA256: String
    /// Blobs leased during the export (blob digest list).
    public let leasedBlobs: [String]
}

/// Test hooks for T47 (edits and cleanup racing an export).
public struct ExportHooks: Sendable {
    /// Runs after the database snapshot is taken and before blobs are copied.
    public var afterSnapshot: (@Sendable () throws -> Void)?
    public init(afterSnapshot: (@Sendable () throws -> Void)? = nil) { self.afterSnapshot = afterSnapshot }
}

/// Builds a `.sylviabackup` (plan 17.3, 17.4):
/// 1. lease every referenced excerpt blob; 2. take a consistent snapshot with SQLite's backup API
/// from one read transaction while writes continue; 3. lease anything the snapshot references that
/// step 1 missed (failing if it is already gone); 4. copy blobs, verifying digests; 5. write the
/// portable JSON and Markdown from the snapshot, never from the live database; 6. write the
/// manifest; 7. validate the staged bundle like a restore would; 8. rename it into place; 9. release
/// leases and record an ExportRecord.
public struct BackupExporter: Sendable {
    public let store: LibraryStore
    public let container: any BackupContainer
    public var leaseTTLMs: Int64 = 60 * 60 * 1000

    public init(_ store: LibraryStore, container: any BackupContainer = DirectoryBundleContainer()) {
        self.store = store
        self.container = container
    }

    public func export(to destination: URL, hooks: ExportHooks = ExportHooks()) throws -> ExportResult {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else { throw BackupError.destinationExists(destination.lastPathComponent) }
        let backupID = EntityID.make()
        let holder = "export:\(backupID)"
        let blobs = BlobStore(store)
        let staging = destination.deletingLastPathComponent()
            .appending(path: ".\(destination.lastPathComponent).partial-\(backupID.prefix(8))", directoryHint: .isDirectory)
        var finalized = false
        defer {
            if !finalized { try? fm.removeItem(at: staging) }
            try? blobs.releaseLeases(holder: holder)
        }

        let leasedFirst = try blobs.leaseAllReferenced(holder: holder, ttlMs: leaseTTLMs)

        for sub in ["database", "export/markdown", "blobs/excerpts", "blobs/covers"] {
            try store.protector.ensureDirectory(staging.appending(path: sub, directoryHint: .isDirectory))
        }
        let databaseURL = staging.appending(path: "database/library.sqlite", directoryHint: .notDirectory)
        try Snapshot.take(from: store.pool, to: databaseURL, staging: databaseURL.deletingLastPathComponent(),
                          protector: store.protector)
        try hooks.afterSnapshot?()

        // Everything below reads the snapshot, so the bundle has one consistent boundary.
        let snapshot = try RecoveryAccess.openReadOnly(databaseURL)
        let facts = try snapshot.read { db in try SnapshotFacts(db) }
        try snapshot.close()

        let missed = facts.blobs.filter { !leasedFirst.contains($0.sha256) }
        if !missed.isEmpty { try blobs.lease(missed.map { ($0.sha256, $0.fileExtension) }, holder: holder, ttlMs: leaseTTLMs) }

        var entries: [BackupManifest.FileEntry] = []
        func add(_ path: String, role: BackupManifest.Role) throws {
            let (sha, size) = try Digest.sha256Hex(fileAt: staging.appending(path: path, directoryHint: .notDirectory))
            entries.append(.init(path: path, role: role, sha256: sha, byte_count: size))
        }
        try add("database/library.sqlite", role: .database_snapshot)

        // Copies a content-addressed blob from the library into the bundle and checks its digest.
        func copyBlob(_ source: URL, sha256: String, path: String, role: BackupManifest.Role) throws {
            let target = staging.appending(path: path, directoryHint: .notDirectory)
            guard fm.fileExists(atPath: source.path) else { throw BackupError.missingBlob(sha256) }
            try store.protector.copyFile(from: source, to: target)
            let (sha, size) = try Digest.sha256Hex(fileAt: target)
            guard sha == sha256 else { throw BackupError.digestMismatch(path: path) }
            try DurableFile.sync(target)
            entries.append(.init(path: path, role: role, sha256: sha, byte_count: size))
        }
        for blob in facts.blobs {
            try copyBlob(blobs.url(sha256: blob.sha256, fileExtension: blob.fileExtension), sha256: blob.sha256,
                         path: "blobs/excerpts/\(blob.sha256).\(blob.fileExtension)", role: .retained_excerpt)
        }
        // Cover thumbnails are never garbage-collected in the spike (a replaced cover leaves its old
        // blob in place), so the file a snapshot references cannot disappear during the export. A
        // product cleanup of covers must take the same retention leases as excerpts.
        for cover in facts.covers {
            try copyBlob(CoverStore.url(store.layout, sha256: cover.sha256, fileExtension: cover.fileExtension),
                         sha256: cover.sha256, path: "blobs/covers/\(cover.sha256).\(cover.fileExtension)",
                         role: .cover_thumbnail)
        }

        try store.protector.write(facts.json, to: staging.appending(path: "export/library.json", directoryHint: .notDirectory))
        try add("export/library.json", role: .portable_json)
        for (name, text) in facts.markdown.sorted(by: { $0.key < $1.key }) {
            let path = "export/markdown/\(name)"
            try store.protector.write(Data(text.utf8), to: staging.appending(path: path, directoryHint: .notDirectory))
            try add(path, role: .markdown)
        }

        let createdAt = store.clock.nowMillis()
        let manifest = BackupManifest(
            schema_version: BackupManifest.currentSchemaVersion,
            format: BackupManifest.formatName,
            backup_id: backupID,
            created_at: RFC3339.string(millis: createdAt),
            originating_device_id: store.deviceID,
            library: .init(schema_version: facts.schemaVersion, migrations: facts.migrations),
            snapshot: .init(change_journal_seq: facts.journalSeq, method: "sqlite_online_backup"),
            counts: facts.counts,
            included_classes: BackupManifest.includedClasses,
            excluded_classes: BackupManifest.standardExclusions,
            excluded_media: facts.excludedMedia,
            complete: facts.excludedMedia.isEmpty,
            encryption: "none",
            files: entries.sorted { $0.path < $1.path })
        let manifestData = try JSONEncoder.sortedPretty.encode(manifest)
        try store.protector.write(manifestData, to: staging.appending(path: BackupManifest.fileName, directoryHint: .notDirectory))
        for directory in ["database", "export/markdown", "export", "blobs/excerpts", "blobs/covers", "blobs", "."] {
            try DurableFile.syncDirectory(staging.appending(path: directory, directoryHint: .isDirectory))
        }

        // Verify before declaring success: the same validation a restore performs.
        let validated = try BackupValidator.validate(staging)
        try container.finalize(stagingDirectory: staging, destination: destination)
        finalized = true

        try store.pool.write { db in
            let id = EntityID.make()
            try store.insertJournaled(db, "export_record", id: id, [
                "id": id, "manifest_schema_version": manifest.schema_version,
                "library_schema_version": manifest.library.schema_version, "created_at_ms": createdAt,
                "snapshot_journal_seq": facts.journalSeq,
                "counts_json": String(decoding: try JSONEncoder.sorted.encode(facts.counts), as: UTF8.self),
                "manifest_sha256": validated.manifestSHA256, "status": "completed",
            ])
        }
        return ExportResult(bundle: destination, manifest: manifest, manifestSHA256: validated.manifestSHA256,
                            leasedBlobs: Array(leasedFirst.union(missed.map(\.sha256))).sorted())
    }
}

/// Everything the manifest and portable exports need, read from the snapshot in one transaction.
struct SnapshotFacts {
    var schemaVersion: Int
    var migrations: [String]
    var journalSeq: Int64
    var counts: [String: Int64]
    var blobs: [(sha256: String, fileExtension: String)]
    /// Cover thumbnails the snapshot's editions reference (none before migration v2-edition-cover-thumbnail).
    var covers: [(sha256: String, fileExtension: String)]
    var excludedMedia: [BackupManifest.ExcludedAsset]
    var json: Data
    var markdown: [String: String]

    init(_ db: Database) throws {
        let integrity = try LibraryChecks.integrity(db)
        guard integrity == ["ok"] else { throw StoreError.integrityCheckFailed(integrity) }
        let fk = try LibraryChecks.foreignKeyViolations(db)
        guard fk.isEmpty else { throw StoreError.foreignKeyViolations(fk) }
        migrations = try LibrarySchema.applied(db)
        guard let version = LibrarySchema.version(forApplied: Set(migrations)) else {
            throw StoreError.newerSchema(unknownMigrations: migrations.filter { !LibrarySchema.knownIdentifiers.contains($0) })
        }
        schemaVersion = version
        journalSeq = try Int64.fetchOne(db, sql: "SELECT coalesce(max(seq), 0) FROM change_journal") ?? 0
        counts = try LibraryChecks.counts(db)
        blobs = try Row.fetchAll(db, sql: """
            SELECT DISTINCT blob_sha256, file_extension FROM retained_excerpt WHERE export_state = 'preserved'
            ORDER BY blob_sha256
            """).map { ($0["blob_sha256"], $0["file_extension"]) }
        covers = try CoverStore.referenced(db)
        excludedMedia = try Row.fetchAll(db, sql: "SELECT id, sha256, byte_count, media_type FROM asset ORDER BY id").map {
            BackupManifest.ExcludedAsset(asset_id: $0["id"], sha256: $0["sha256"], byte_count: $0["byte_count"], media_type: $0["media_type"])
        }
        json = try PortableExport.json(db, librarySchemaVersion: version)
        markdown = try PortableExport.markdown(db)
    }
}

extension JSONEncoder {
    static var sortedPretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return encoder
    }
}
