import Foundation
import GRDB

/// A restore that has been fully built and validated in a temporary library and is waiting for the
/// user's confirmation to replace the active library.
public struct RestorePlan: Sendable {
    public let id: String
    public let workDirectory: URL
    public let workLibrary: URL
    public let manifest: BackupManifest
    /// Library schema version after supported migrations ran on the temporary copy.
    public let librarySchemaVersion: Int
    public let countsAfterMigration: [String: Int64]
    /// Assets with no on-device location after restore (every asset: format v1 never includes
    /// originals); each is shown as "Record only" or "Not on this device · from {source}".
    public let unavailableAssets: Int
}

/// The explicit confirmation restore requires (plan 17.4: replace with confirmation, never merge).
public enum RestoreConfirmation: Sendable {
    case replaceExistingLibrary
}

public enum RestoreStep: String, Sendable, CaseIterable {
    case intentWritten, activeMovedAside, restoredMovedIn
}

public struct RestoreHooks: Sendable {
    /// Stops the commit right after this step, leaving files exactly as a crash would.
    public var crashAfter: RestoreStep?
    /// Called after each step completes (the SIGKILL drill uses it to report where kills landed).
    public var afterStep: (@Sendable (RestoreStep) -> Void)?
    public init(crashAfter: RestoreStep? = nil, afterStep: (@Sendable (RestoreStep) -> Void)? = nil) {
        self.crashAfter = crashAfter
        self.afterStep = afterStep
    }
}

public struct RestoreResult: Sendable {
    public let store: LibraryStore
    /// The library that was replaced, kept under `Recovery/` (nil for a fresh install).
    public let preRestoreCopy: URL?
}

/// Restore from a `.sylviabackup` (plan 17.4, T35, T46, T47).
///
/// `prepare` never touches the active library: it validates the bundle, copies it into
/// `RestoreWork/<id>/Library`, re-verifies digests on the copies, opens the database defensively,
/// requires its schema to equal this build's schema for its migrations, checks integrity, foreign
/// keys, the row values the schema does not constrain (`RowCheck`: effective dates, the journal
/// sequence), counts and the excluded-media list, runs supported migrations, marks original media
/// unavailable, and repeats the schema, integrity, foreign-key, row and count checks after that last
/// write. `commit` then
/// swaps directories with two same-volume renames recorded in `restore-intent.json`, keeping the
/// replaced library as a recovery copy; `RestoreReconciler` finishes or rolls back an interrupted swap.
public struct BackupRestorer: Sendable {
    public let layout: LibraryLayout
    public let options: StoreOptions
    public let container: any BackupContainer

    public init(layout: LibraryLayout, options: StoreOptions = StoreOptions(), container: any BackupContainer = DirectoryBundleContainer()) {
        self.layout = layout
        self.options = options
        self.container = container
    }

    public func prepare(bundle: URL) throws -> RestorePlan {
        let fm = FileManager.default
        try LibraryStore.prepareDirectories(layout, protector: options.protector)
        let id = EntityID.make()
        let work = layout.restoreWorkDirectory.appending(path: id, directoryHint: .isDirectory)
        var succeeded = false
        defer { if !succeeded { try? fm.removeItem(at: work) } }
        try options.protector.ensureDirectory(work)

        let root = try container.open(bundle, workDirectory: work.appending(path: "unpacked", directoryHint: .isDirectory))
        let validated = try BackupValidator.validate(root)
        let manifest = validated.manifest

        let needed = manifest.files.reduce(Int64(0)) { $0 + $1.byte_count } * 2 + options.spaceReserveBytes
        let available = try options.space.availableBytes(at: layout.root)
        guard available >= needed else { throw BackupError.insufficientSpace(required: needed, available: available) }

        let workLayout = LibraryLayout(root: work)
        for directory in [workLayout.libraryDirectory, workLayout.blobsDirectory, workLayout.excerptBlobsDirectory,
                          workLayout.coverBlobsDirectory, workLayout.mediaDirectory] {
            try options.protector.ensureDirectory(directory)
        }

        // Copy, then verify the copy against the manifest (the bundle could change after validation).
        // The copy is created with the library's protection class and never follows a link.
        func copyVerified(_ entry: BackupManifest.FileEntry, to target: URL) throws {
            let source = try BackupValidator.resolve(entry.path, in: root)
            try BackupValidator.requireRegularFile(source, display: entry.path, missing: .missingFile(entry.path))
            do { try options.protector.copyFile(from: source, to: target) } catch let error as FileSystemError {
                throw BackupError.notARegularFile("\(entry.path) (\(error))")
            }
            let (sha, size) = try Digest.sha256Hex(fileAt: target)
            guard size == entry.byte_count, sha == entry.sha256 else { throw BackupError.digestMismatch(path: entry.path) }
            try DurableFile.sync(target)
        }
        let databaseEntry = manifest.files.first { $0.role == .database_snapshot }!
        try copyVerified(databaseEntry, to: workLayout.databaseURL)

        // The database is untrusted input (plan 18.1). Open it in SQLite's defensive mode with
        // trusted_schema off, and prove its schema is exactly the one this build's migrations
        // produce for its migration list before reading counts, migrating or writing anything:
        // a trigger, view, extra table or altered table (no STRICT, no CHECK, other foreign-key
        // actions) is rejected here.
        let queue: DatabaseQueue
        do { queue = try DatabaseQueue(path: workLayout.databaseURL.path, configuration: SchemaCheck.untrustedConfiguration()) } catch {
            throw BackupError.corruptDatabase(String(describing: error))
        }
        defer { try? queue.close() }
        let migrator = LibrarySchema.migrator(faults: options.faults)
        do {
            try queue.read { db in
                let integrity = try LibraryChecks.integrity(db)
                guard integrity == ["ok"] else { throw BackupError.corruptDatabase(integrity.prefix(3).joined(separator: "; ")) }
            }
        } catch let error as BackupError { throw error } catch {
            throw BackupError.corruptDatabase(String(describing: error))
        }
        let applied = try queue.read { try LibrarySchema.applied($0) }
        let unknown = applied.filter { !LibrarySchema.knownIdentifiers.contains($0) }
        guard unknown.isEmpty, let version = LibrarySchema.version(forApplied: Set(applied)) else {
            throw BackupError.newerLibrarySchema(found: manifest.library.schema_version,
                                                 supported: LibrarySchema.currentVersion, unknownMigrations: unknown)
        }
        guard version == manifest.library.schema_version, applied == manifest.library.migrations else {
            throw BackupError.corruptDatabase("database migrations do not match the manifest")
        }
        try queue.read { db in try SchemaCheck.requireReference(db, applied: applied) }

        try queue.read { db in
            try Self.requireCounts(try LibraryChecks.counts(db), equal: manifest.counts)
            let fk = try LibraryChecks.foreignKeyViolations(db)
            guard fk.isEmpty else { throw BackupError.foreignKeyViolations(fk.count) }
            try RowCheck.require(db)
            // I-09: the manifest must name exactly the originals that are not in the backup. Format v1
            // never includes original media, so that is every asset of the snapshot.
            let assets = try Row.fetchAll(db, sql: "SELECT id, sha256, byte_count, media_type FROM asset ORDER BY id").map {
                BackupManifest.ExcludedAsset(asset_id: $0["id"], sha256: $0["sha256"], byte_count: $0["byte_count"],
                                             media_type: $0["media_type"])
            }
            let listed = manifest.excluded_media.sorted { $0.asset_id < $1.asset_id }
            guard listed == assets else {
                let missing = Set(assets.map(\.asset_id)).subtracting(listed.map(\.asset_id)).count
                let extra = Set(listed.map(\.asset_id)).subtracting(assets.map(\.asset_id)).count
                throw BackupError.excludedMediaMismatch("snapshot has \(assets.count) assets, manifest lists \(listed.count) (\(missing) unlisted, \(extra) not in the snapshot, or details differ)")
            }
            guard manifest.complete == assets.isEmpty else {
                throw BackupError.excludedMediaMismatch("complete is \(manifest.complete) but \(assets.count) originals are excluded")
            }
        }

        // Supported migrations on the copy, then the same checks against the current schema.
        do { try migrator.migrate(queue) } catch {
            throw BackupError.corruptDatabase("migration failed: \(error)")
        }
        let migratedApplied = try queue.read { try LibrarySchema.applied($0) }
        let migratedCounts: [String: Int64] = try queue.read { db in
            try SchemaCheck.requireReference(db, applied: migratedApplied)
            guard try LibraryChecks.isIntact(db) else { throw BackupError.corruptDatabase("integrity after migration") }
            let fk = try LibraryChecks.foreignKeyViolations(db)
            guard fk.isEmpty else { throw BackupError.foreignKeyViolations(fk.count) }
            try RowCheck.require(db)
            let counts = try LibraryChecks.counts(db)
            try Self.requireCounts(counts, equal: manifest.counts)
            return counts
        }

        // Blobs: exactly the preserved excerpts and the cover thumbnails the snapshot references.
        let (referencedExcerpts, referencedCovers) = try queue.read { db in
            (Dictionary(try Row.fetchAll(db, sql: "SELECT DISTINCT blob_sha256, file_extension FROM retained_excerpt WHERE export_state = 'preserved'")
                .map { ($0["blob_sha256"] as String, $0["file_extension"] as String) }, uniquingKeysWith: { a, _ in a }),
             Dictionary(try CoverStore.referenced(db).map { ($0.sha256, $0.fileExtension) }, uniquingKeysWith: { a, _ in a }))
        }
        for (role, referenced, directory) in [(BackupManifest.Role.retained_excerpt, referencedExcerpts, workLayout.excerptBlobsDirectory),
                                              (.cover_thumbnail, referencedCovers, workLayout.coverBlobsDirectory)] {
            let entries = manifest.files.filter { $0.role == role }
            for entry in entries {
                let name = entry.path.split(separator: "/").last!
                let sha = String(name.prefix(64))
                guard let ext = referenced[sha], name == "\(sha).\(ext)", sha == entry.sha256 else {
                    throw BackupError.unreferencedBlob(sha)
                }
                try copyVerified(entry, to: directory.appending(path: String(name), directoryHint: .notDirectory))
            }
            for sha in referenced.keys.sorted() where !entries.contains(where: { $0.sha256 == sha }) {
                throw BackupError.missingBlob(sha)
            }
        }

        // Media are not in the bundle: every on-device location becomes unavailable (or at source),
        // leases from the source device are dropped, and the restore is journaled.
        let journaled: Int = try queue.write { db in
            let now = options.clock.nowMillis()
            try db.execute(sql: "DELETE FROM retention_lease")
            let rows = try Row.fetchAll(db, sql: "SELECT id, source_id FROM asset_location WHERE availability = 'on_device'")
            for row in rows {
                try db.execute(sql: """
                    UPDATE asset_location SET availability = ?, local_relative_path = NULL, last_verified_at_ms = ? WHERE id = ?
                    """, arguments: [(row["source_id"] as String?) == nil ? "unavailable" : "at_source", now, row["id"] as String])
                try LibraryStore.journal(db, "asset_location", row["id"], "update", at: now)
            }
            try LibraryStore.journal(db, "library", manifest.backup_id, "restore", at: now)
            return rows.count + 1
        }
        try queue.writeWithoutTransaction { db in _ = try String.fetchOne(db, sql: "PRAGMA journal_mode = DELETE") }

        // Final checks on the library exactly as it will be swapped in, after the last write.
        let (finalVersion, unavailable) = try queue.read { db -> (Int, Int) in
            let finalApplied = try LibrarySchema.applied(db)
            try SchemaCheck.requireReference(db, applied: finalApplied)
            guard try LibraryChecks.isIntact(db) else { throw BackupError.corruptDatabase("integrity after marking media unavailable") }
            let fk = try LibraryChecks.foreignKeyViolations(db)
            guard fk.isEmpty else { throw BackupError.foreignKeyViolations(fk.count) }
            try RowCheck.require(db)
            var expected = migratedCounts
            expected["change_journal"] = (migratedCounts["change_journal"] ?? 0) + Int64(journaled)
            expected["retention_lease"] = 0
            try Self.requireCounts(try LibraryChecks.counts(db), equal: expected)
            guard try Int.fetchOne(db, sql: "SELECT count(*) FROM asset_location WHERE availability = 'on_device'") == 0 else {
                throw BackupError.corruptDatabase("an original is still marked on this device")
            }
            let unavailable = try Int.fetchOne(db, sql: """
                SELECT count(*) FROM asset a WHERE NOT EXISTS
                  (SELECT 1 FROM asset_location l WHERE l.asset_id = a.id AND l.availability = 'on_device')
                """) ?? 0
            return (LibrarySchema.version(forApplied: Set(finalApplied)) ?? -1, unavailable)
        }
        try queue.close()
        try DurableFile.sync(workLayout.databaseURL)
        for directory in [workLayout.excerptBlobsDirectory, workLayout.coverBlobsDirectory, workLayout.blobsDirectory,
                          workLayout.libraryDirectory, work] {
            try DurableFile.syncDirectory(directory)
        }
        succeeded = true
        return RestorePlan(id: id, workDirectory: work, workLibrary: workLayout.libraryDirectory, manifest: manifest,
                           librarySchemaVersion: finalVersion,
                           countsAfterMigration: migratedCounts, unavailableAssets: unavailable)
    }

    /// Every library table's count equals `expected`, and no table is missing from either side.
    static func requireCounts(_ counts: [String: Int64], equal expected: [String: Int64]) throws {
        for (table, wanted) in expected.sorted(by: { $0.key < $1.key }) where counts[table] != wanted {
            throw BackupError.countMismatch(table: table, expected: wanted, actual: counts[table] ?? -1)
        }
        for table in counts.keys.sorted() where expected[table] == nil {
            throw BackupError.countMismatch(table: table, expected: -1, actual: counts[table]!)
        }
    }

    /// Replaces the active library with the prepared one. The caller must have stopped playback and
    /// writes; `activeStore` is closed here. Returns the opened restored library.
    public func commit(_ plan: RestorePlan, confirmation: RestoreConfirmation?, activeStore: LibraryStore?,
                       hooks: RestoreHooks = RestoreHooks()) throws -> RestoreResult {
        guard confirmation == .replaceExistingLibrary else { throw BackupError.confirmationRequired }
        try activeStore?.close()
        let fm = FileManager.default
        let hadLibrary = fm.fileExists(atPath: layout.libraryDirectory.path)
        let preRestore = layout.recoveryDirectory.appending(path: "pre-restore-\(plan.id)", directoryHint: .isDirectory)
        let intent = RestoreIntent(id: plan.id,
                                   work_library: "RestoreWork/\(plan.id)/Library",
                                   pre_restore_library: "Recovery/pre-restore-\(plan.id)/Library")
        try DurableFile.writeDurably(try JSONEncoder.sorted.encode(intent), to: layout.restoreIntentURL,
                                     staging: layout.stagingDirectory, protector: options.protector)
        hooks.afterStep?(.intentWritten)
        if hooks.crashAfter == .intentWritten { throw BackupError.simulatedCrash(RestoreStep.intentWritten.rawValue) }

        if hadLibrary {
            try options.protector.ensureDirectory(preRestore)
            try DurableFile.rename(layout.libraryDirectory, to: preRestore.appending(path: "Library", directoryHint: .isDirectory))
            try DurableFile.syncDirectory(layout.root)
            try DurableFile.syncDirectory(preRestore)
        }
        hooks.afterStep?(.activeMovedAside)
        if hooks.crashAfter == .activeMovedAside { throw BackupError.simulatedCrash(RestoreStep.activeMovedAside.rawValue) }

        try DurableFile.rename(plan.workLibrary, to: layout.libraryDirectory)
        try DurableFile.syncDirectory(layout.root)
        hooks.afterStep?(.restoredMovedIn)
        if hooks.crashAfter == .restoredMovedIn { throw BackupError.simulatedCrash(RestoreStep.restoredMovedIn.rawValue) }

        try RestoreReconciler.finish(layout, intent: intent)
        let store = try LibraryStore.open(layout, options: options)
        return RestoreResult(store: store, preRestoreCopy: hadLibrary ? preRestore.appending(path: "Library", directoryHint: .isDirectory) : nil)
    }

    /// Abandons a prepared restore without touching the active library.
    public func discard(_ plan: RestorePlan) throws {
        try FileManager.default.removeItem(at: plan.workDirectory)
    }
}

struct RestoreIntent: Codable, Equatable {
    var id: String
    var work_library: String
    var pre_restore_library: String
}

/// Runs before the library opens. With a restore intent on disk, the swap is completed when the
/// validated restored library is already in place or can be moved in, and rolled back to the
/// pre-restore copy otherwise. The library is never left empty or mixed.
public enum RestoreReconciler {
    public enum Outcome: Sendable, Equatable {
        case nothingToDo
        case completedRestore
        case keptExistingLibrary
        case rolledBackToPreRestoreCopy
    }

    @discardableResult
    public static func reconcile(_ layout: LibraryLayout, protector: FileProtector) throws -> Outcome {
        let fm = FileManager.default
        guard fm.fileExists(atPath: layout.restoreIntentURL.path) else { return .nothingToDo }
        // An intent that exists but cannot be read (for example before first unlock) or does not
        // decode is never acted on and never ignored: ignoring it would let the open continue, create
        // an empty `Library/` and clear `RestoreWork/`, which could discard a validated restored
        // library mid-swap. The open fails, nothing is changed, and the recovery screen takes over.
        let data: Data
        do { data = try Data(contentsOf: layout.restoreIntentURL) } catch {
            throw StoreError.invalid("restore intent exists but cannot be read; nothing was changed")
        }
        guard let intent = try? JSONDecoder().decode(RestoreIntent.self, from: data), EntityID.isValid(intent.id),
              intent.work_library == "RestoreWork/\(intent.id)/Library",
              intent.pre_restore_library == "Recovery/pre-restore-\(intent.id)/Library" else {
            throw StoreError.invalid("restore intent is not valid; nothing was changed")
        }
        let active = layout.libraryDirectory
        let work = layout.root.appending(path: intent.work_library, directoryHint: .isDirectory)
        let preRestore = layout.root.appending(path: intent.pre_restore_library, directoryHint: .isDirectory)
        let activeExists = fm.fileExists(atPath: active.path)
        let workExists = fm.fileExists(atPath: work.path)
        let preExists = fm.fileExists(atPath: preRestore.path)

        let outcome: Outcome
        switch (activeExists, workExists) {
        case (true, false):
            // Restored library already moved in.
            outcome = .completedRestore
        case (false, true):
            // Active moved aside (or fresh install); the validated restored library moves in.
            try DurableFile.rename(work, to: active)
            try DurableFile.syncDirectory(layout.root)
            outcome = .completedRestore
        case (true, true):
            // Crashed before the active library was moved: keep it; the user can retry.
            try fm.removeItem(at: work.deletingLastPathComponent())
            outcome = .keptExistingLibrary
        case (false, false):
            guard preExists else { throw StoreError.invalid("restore intent found but neither the restored nor the pre-restore library exists; nothing was changed") }
            try DurableFile.rename(preRestore, to: active)
            try DurableFile.syncDirectory(layout.root)
            outcome = .rolledBackToPreRestoreCopy
        }
        try finish(layout, intent: intent)
        return outcome
    }

    static func finish(_ layout: LibraryLayout, intent: RestoreIntent) throws {
        let fm = FileManager.default
        let workDir = layout.restoreWorkDirectory.appending(path: intent.id, directoryHint: .isDirectory)
        if fm.fileExists(atPath: workDir.path) { try fm.removeItem(at: workDir) }
        try fm.removeItem(at: layout.restoreIntentURL)
        try DurableFile.syncDirectory(layout.root)
    }
}
