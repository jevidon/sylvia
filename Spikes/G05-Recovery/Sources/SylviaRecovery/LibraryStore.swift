import Foundation
import GRDB

public struct StoreOptions: Sendable {
    public var durability: DurabilityPolicy = .acknowledgedSaves
    public var clock: UTCClock = .system
    public var space: any StorageSpaceProbe = SystemSpaceProbe()
    public var faults: LibrarySchema.Faults = .none
    public var protector: FileProtector = .library
    /// Migrate only up to this identifier (used to build the v1 fixture). `nil` means latest.
    public var migrateUpTo: String?
    /// Free space kept in reserve on top of the estimated snapshot and rebuild size.
    public var spaceReserveBytes: Int64 = 16 << 20
    /// Test-only step hooks for a snapshot-guarded migration and its put-back (T45 drills).
    public var putBackHooks = PutBackHooks()

    public init() {}
}

/// What happened when the store was opened.
public struct OpenReport: Sendable {
    public var appliedBefore: [String] = []
    public var appliedNow: [String] = []
    public var recoverySnapshot: URL?
    /// True when the guarded migration reused an existing snapshot of the same pre-state.
    public var recoverySnapshotReused = false
    /// What the `Recovery/` retention rule removed after a successful guarded migration.
    public var recoveryPrune: RecoveryRetention.PruneReport?
    /// Protection class each SQLite file reported *before* `LibraryStore` set it explicitly, to show
    /// whether SQLite-created files inherit the directory's class.
    public var protectionBeforeExplicitSet: [String: String] = [:]
    public var durability: String = ""
    /// What the launch-time restore reconciliation did.
    public var restoreReconciliation: RestoreReconciler.Outcome = .nothingToDo
}

/// The library database plus its files. One serialized writer (GRDB `DatabasePool`), WAL, foreign
/// keys on, durability policy verified on open (plan 6.3, 7.4).
public final class LibraryStore: Sendable {
    public let layout: LibraryLayout
    public let pool: DatabasePool
    public let options: StoreOptions
    public let openReport: OpenReport
    public let deviceID: String

    public var clock: UTCClock { options.clock }
    public var protector: FileProtector { options.protector }

    private init(layout: LibraryLayout, pool: DatabasePool, options: StoreOptions, report: OpenReport,
                 deviceID: String) {
        self.layout = layout
        self.pool = pool
        self.options = options
        self.openReport = report
        self.deviceID = deviceID
    }

    /// Opens (creating if needed) the library at `layout`, reconciling any interrupted restore or
    /// migration put-back and running pending migrations under the safety rules of plan 7.4.
    ///
    /// Throws `migrationInterrupted` after finishing an interrupted put-back (the app shows the
    /// recovery screen once; the next open retries the migration), and `libraryMissing` when the
    /// database is gone from an installation that already had one: a new empty library is created
    /// only for a new installation.
    public static func open(_ layout: LibraryLayout, options: StoreOptions = StoreOptions()) throws -> LibraryStore {
        // Reconcile an interrupted restore before anything creates `Library/`: an empty directory
        // created first would look like a surviving active library and the restored one would be
        // discarded (found by RestoreTests.crashDuringSwap through this launch path).
        try options.protector.ensureDirectory(layout.root)
        let reconciliation = try RestoreReconciler.reconcile(layout, protector: options.protector)
        try prepareDirectories(layout, protector: options.protector)
        // With no restore intent left, anything in RestoreWork is an abandoned (crashed or
        // discarded) preparation. Restore is modal, so nothing can be preparing during open.
        for leftover in try FileManager.default.contentsOfDirectory(at: layout.restoreWorkDirectory, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: leftover)
        }
        // A migration whose snapshot was being put back (or that was interrupted) is finished
        // before SQLite can create a new file where the database should be.
        if let intent = try MigrationPutBack.reconcile(layout, protector: options.protector, hooks: options.putBackHooks) {
            throw StoreError.migrationInterrupted(pending: intent.pending)
        }
        try requireDatabaseOrNewInstallation(layout)

        // The database is created before the installation record, so a crash between the two never
        // leaves an installation record without a database (which `requireDatabaseOrNewInstallation`
        // treats as a lost library).
        let pool = try makePool(layout, options: options)
        var report = OpenReport()
        report.restoreReconciliation = reconciliation
        let deviceID: String
        do {
            deviceID = try Installation.deviceID(layout, protector: options.protector, clock: options.clock)
            report.durability = try pool.writeWithoutTransaction { db in
                try options.durability.apply(db)
                return try DurabilityPolicy.observe(db).description
            }
            report.protectionBeforeExplicitSet = try protectDatabaseFiles(layout, protector: options.protector)
            try MigrationSafety.run(pool: pool, layout: layout, options: options, report: &report)
            _ = try protectDatabaseFiles(layout, protector: options.protector)
        } catch {
            try? pool.close()
            throw error
        }
        return LibraryStore(layout: layout, pool: pool, options: options, report: report, deviceID: deviceID)
    }

    /// Refuses to let SQLite create a new, empty database when the installation already had a
    /// library: the installation record exists, or `Recovery/` holds copies of an earlier library.
    /// The user's data is then in `Recovery/` (or was lost outside Sylvia), and the app must show the
    /// recovery screen rather than an empty library (plan 7.4).
    static func requireDatabaseOrNewInstallation(_ layout: LibraryLayout) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: layout.databaseURL.path) else { return }
        let recovery = try fm.contentsOfDirectory(atPath: layout.recoveryDirectory.path).filter { !$0.hasPrefix(".") }.sorted()
        if fm.fileExists(atPath: layout.installationURL.path) || !recovery.isEmpty {
            throw StoreError.libraryMissing(recoveryItems: recovery)
        }
    }

    public func close() throws {
        try pool.close()
    }

    public var schemaVersion: Int {
        get throws {
            let applied = try pool.read { try LibrarySchema.applied($0) }
            return LibrarySchema.version(forApplied: Set(applied)) ?? -1
        }
    }

    static func makePool(_ layout: LibraryLayout, options: StoreOptions) throws -> DatabasePool {
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.busyMode = .timeout(10)
        config.label = "SylviaLibrary"
        return try DatabasePool(path: layout.databaseURL.path, configuration: config)
    }

    static func prepareDirectories(_ layout: LibraryLayout, protector: FileProtector) throws {
        for directory in layout.managedDirectories {
            try protector.ensureDirectory(directory)
        }
        // Staging, recovery copies and restore work are local safety nets that duplicate the
        // library; keep them out of device backups. The library itself stays backup-eligible
        // (plan 17.5: unique user knowledge).
        for directory in layout.backupExcludedDirectories {
            var url = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        }
    }

    /// Sets and verifies the protection class on the database, WAL and SHM files. Returns the class
    /// each file had before the explicit set.
    @discardableResult
    static func protectDatabaseFiles(_ layout: LibraryLayout, protector: FileProtector) throws -> [String: String] {
        var before: [String: String] = [:]
        for url in [layout.databaseURL, layout.walURL, layout.shmURL]
        where FileManager.default.fileExists(atPath: url.path) {
            before[url.lastPathComponent] = (try protector.protectionClass(of: url))?.rawValue ?? "none reported"
            try protector.protect(url)
        }
        return before
    }
}

/// Read-only access to a library that failed to open normally (the recovery screen of plan 7.4):
/// the user's data can still be viewed and exported.
public enum RecoveryAccess {
    public static func openReadOnly(_ databaseURL: URL) throws -> DatabaseQueue {
        var config = Configuration()
        config.readonly = true
        config.foreignKeysEnabled = true
        return try DatabaseQueue(path: databaseURL.path, configuration: config)
    }
}

/// The installation's originating device ID (plan 17.3 manifest field). Lives outside `Library/`,
/// so a restore never imports another device's identity.
public enum Installation {
    struct Record: Codable { var device_id: String; var created_at_ms: Int64 }

    /// Returns the stored ID, creating one only when the file does not exist. A file that exists but
    /// cannot be read (for example before first unlock, when class-C files are unavailable) or does
    /// not decode is an error: silently minting a new identity would make this installation look
    /// like another device in every later backup manifest.
    public static func deviceID(_ layout: LibraryLayout, protector: FileProtector, clock: UTCClock) throws -> String {
        let url = layout.installationURL
        if FileManager.default.fileExists(atPath: url.path) {
            let data: Data
            do { data = try Data(contentsOf: url) } catch {
                throw StoreError.invalid("installation.json exists but cannot be read: \(error.localizedDescription)")
            }
            guard let record = try? JSONDecoder().decode(Record.self, from: data), EntityID.isValid(record.device_id) else {
                throw StoreError.invalid("installation.json exists but is not a valid installation record")
            }
            return record.device_id
        }
        let record = Record(device_id: EntityID.make(), created_at_ms: clock.nowMillis())
        try DurableFile.writeDurably(try JSONEncoder().encode(record), to: url,
                                     staging: layout.stagingDirectory, protector: protector)
        return record.device_id
    }
}

/// Migration rules of plan 7.4: refuse newer schemas, check space and snapshot before a destructive
/// migration, verify integrity/foreign keys/row counts afterwards, and put the snapshot back on any
/// failure so the user never gets an empty or half-migrated library.
///
/// A snapshot-guarded migration writes `Library/migration-putback.json` before the first migration
/// runs and removes it only after the checks pass. If anything fails, or the process dies, while it
/// exists, the snapshot is put back (`MigrationPutBack`), in this run or at the next open.
enum MigrationSafety {
    static func run(pool: DatabasePool, layout: LibraryLayout, options: StoreOptions, report: inout OpenReport) throws {
        let migrator = LibrarySchema.migrator(faults: options.faults)
        let hooks = options.putBackHooks
        let applied = try pool.read { try LibrarySchema.applied($0) }
        report.appliedBefore = applied
        let unknown = applied.filter { !LibrarySchema.knownIdentifiers.contains($0) }
        guard unknown.isEmpty else { throw StoreError.newerSchema(unknownMigrations: unknown) }

        var target = LibrarySchema.migrations.map(\.identifier)
        if let upTo = options.migrateUpTo, let index = target.firstIndex(of: upTo) {
            target = Array(target[...index])
        }
        let pending = LibrarySchema.migrations.filter { target.contains($0.identifier) && !applied.contains($0.identifier) }
        guard !pending.isEmpty else {
            report.appliedNow = applied
            return
        }

        var intent: PutBackIntent?
        if !applied.isEmpty && pending.contains(where: \.destructive) {
            let fm = FileManager.default
            let databaseBytes = fm.sizeOfFile(at: layout.databaseURL) + fm.sizeOfFile(at: layout.walURL)
            // One copy for the snapshot, up to one more for a table rebuild or a put-back, plus a reserve.
            let required = databaseBytes * 2 + options.spaceReserveBytes
            let available = try options.space.availableBytes(at: layout.root)
            guard available >= required else {
                throw StoreError.insufficientSpace(required: required, available: available)
            }
            let id = EntityID.make()
            // A retry from the same pre-state (for example after a failed migration was put back)
            // reuses that snapshot instead of adding another copy of the library (RecoveryRetention).
            let name: String
            if let existing = try RecoveryRetention.reusableSnapshot(matching: pool, layout: layout) {
                name = existing
                report.recoverySnapshotReused = true
            } else {
                name = "pre-migration-\(options.clock.nowMillis())-\(id.prefix(8)).sqlite"
                try Snapshot.take(from: pool, to: layout.recoveryDirectory.appending(path: name, directoryHint: .notDirectory),
                                  staging: layout.stagingDirectory, protector: options.protector)
            }
            report.recoverySnapshot = layout.recoveryDirectory.appending(path: name, directoryHint: .notDirectory)
            let record = PutBackIntent(id: id, snapshot: "Recovery/\(name)", pending: pending.map(\.identifier))
            try MigrationPutBack.writeIntent(record, layout: layout, protector: options.protector)
            intent = record
            try hooks.completed(.intentWritten)
        }

        let before = try pool.read { try LibraryChecks.counts($0) }
        var failure: StoreError?
        do {
            if let last = target.last { try migrator.migrate(pool, upTo: last) }
        } catch {
            let nowApplied = (try? pool.read { try migrator.appliedIdentifiers($0) }) ?? []
            let failed = pending.first { !nowApplied.contains($0.identifier) }?.identifier
            failure = .migrationFailed(identifier: failed, reason: String(describing: error), restoredFromSnapshot: intent != nil)
        }
        if failure == nil {
            let problem: String? = try pool.read { db in
                let integrity = try LibraryChecks.integrity(db)
                if integrity != ["ok"] { return "integrity_check: \(integrity.prefix(3).joined(separator: "; "))" }
                let fk = try LibraryChecks.foreignKeyViolations(db)
                if !fk.isEmpty { return "foreign_key_check: \(fk.count) violations" }
                let after = try LibraryChecks.counts(db)
                for (table, count) in before.sorted(by: { $0.key < $1.key }) where after[table] != count {
                    return "row count of \(table) changed from \(count) to \(after[table].map(String.init) ?? "missing")"
                }
                return nil
            }
            if let problem { failure = .postMigrationCheckFailed(reason: problem, restoredFromSnapshot: intent != nil) }
        }

        if let failure {
            try pool.close()
            guard let intent else { throw failure }
            try hooks.completed(.migrationFailed)
            do {
                try MigrationPutBack.complete(intent, layout: layout, protector: options.protector, hooks: hooks)
            } catch let error as StoreError where error.isSimulatedCrash {
                throw error
            } catch {
                // Only a flush after the intent's removal failed: the snapshot is back in place.
                guard MigrationPutBack.intentPending(layout) else { throw failure }
                // The intent is still in place, so the next open finishes the put-back before SQLite
                // can open anything: the library is never used as it is now.
                throw failure.puttingBackFailed(String(describing: error))
            }
            throw failure
        }
        if let intent {
            try hooks.completed(.migrationChecked)
            try MigrationPutBack.removeIntent(layout)
            // Succeeded: keep only this migration's snapshot; earlier snapshots and failed copies go.
            report.recoveryPrune = RecoveryRetention.prune(layout, keepSnapshot: String(intent.snapshot.dropFirst("Recovery/".count)),
                                                           keepFailed: nil)
        }
        report.appliedNow = try pool.read { try LibrarySchema.applied($0) }
    }
}

/// Consistent single-file copies of the library made with SQLite's online backup API through GRDB
/// (plan 7.4: never copy a live SQLite file while ignoring its WAL).
public enum Snapshot {
    /// Copies `pool` to `destination` from one read transaction, converts the copy to a rollback
    /// journal so it is a single self-contained file, checks it, flushes it and renames it into place.
    public static func take(from pool: DatabasePool, to destination: URL, staging: URL,
                            protector: FileProtector) throws {
        let temp = staging.appending(path: "\(EntityID.make()).sqlite", directoryHint: .notDirectory)
        defer { removeSQLiteFiles(temp) }
        let queue = try DatabaseQueue(path: temp.path)
        try pool.backup(to: queue)
        try queue.writeWithoutTransaction { db in
            _ = try String.fetchOne(db, sql: "PRAGMA journal_mode = DELETE")
            let integrity = try LibraryChecks.integrity(db)
            guard integrity == ["ok"] else { throw StoreError.integrityCheckFailed(integrity) }
        }
        try queue.close()
        try protector.protect(temp)
        try DurableFile.sync(temp)
        try DurableFile.rename(temp, to: destination)
        try DurableFile.syncDirectory(destination.deletingLastPathComponent())
    }

    static func removeSQLiteFiles(_ url: URL) {
        for suffix in ["", "-wal", "-shm", "-journal"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
}
