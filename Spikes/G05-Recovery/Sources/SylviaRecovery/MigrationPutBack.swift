import Foundation

/// Steps of a migration guarded by a recovery snapshot (plan 7.4, T45), in order. The failure path
/// puts the snapshot back; every step after `intentWritten` can be interrupted and is finished by
/// the next open.
public enum PutBackStep: String, Sendable, CaseIterable {
    /// The snapshot is in `Recovery/` and `Library/migration-putback.json` names it. No migration has run.
    case intentWritten
    /// Success path only: migrated and checked; the intent is not yet removed.
    case migrationChecked
    /// Failure path only: a migration or a post-migration check failed and the pool is closed.
    case migrationFailed
    /// A copy of the snapshot is complete and flushed in `Staging/`. The live files are untouched.
    case staged
    /// `library.sqlite`, then `-wal`, then `-shm` moved to `Recovery/failed-<id>/` (each is reported
    /// even when that file did not exist).
    case databaseMovedAside
    case walMovedAside
    case shmMovedAside
    /// The staged copy is `Library/library.sqlite`.
    case snapshotMovedIn
    /// The intent is removed: the put-back is complete.
    case intentRemoved
}

public struct PutBackHooks: Sendable {
    /// Stops right after this step by throwing `StoreError.simulatedCrash`, leaving files exactly as
    /// a crash would (no cleanup runs).
    public var crashAfter: PutBackStep?
    /// Throws an I/O error (`ENOSPC`) instead of performing this put-back step, as a full disk would.
    /// Only `staged`, `databaseMovedAside` and `snapshotMovedIn` can fail this way.
    public var ioErrorAt: PutBackStep?
    /// Called after each step completes (the SIGKILL drill uses it to report where kills landed).
    public var afterStep: (@Sendable (PutBackStep) -> Void)?

    public init(crashAfter: PutBackStep? = nil, ioErrorAt: PutBackStep? = nil,
                afterStep: (@Sendable (PutBackStep) -> Void)? = nil) {
        self.crashAfter = crashAfter
        self.ioErrorAt = ioErrorAt
        self.afterStep = afterStep
    }

    func completed(_ step: PutBackStep) throws {
        afterStep?(step)
        if crashAfter == step { throw StoreError.simulatedCrash(step.rawValue) }
    }

    func performing(_ step: PutBackStep) throws {
        if ioErrorAt == step { throw FileSystemError.posix("put-back \(step.rawValue)", "simulated", ENOSPC) }
    }
}

/// The record that a migration guarded by a recovery snapshot is in progress. Written durably to
/// `Library/migration-putback.json` before the first migration runs and removed only when the
/// migration has passed its checks or the snapshot is back in place. It lives inside `Library/`, so a
/// restore swap moves it with the library it describes.
struct PutBackIntent: Codable, Equatable {
    var id: String
    /// Root-relative path of the pre-migration snapshot: `Recovery/pre-migration-<ms>-<id8>.sqlite`.
    var snapshot: String
    /// The migrations that were about to run.
    var pending: [String]

    var isValid: Bool {
        guard EntityID.isValid(id), !pending.isEmpty else { return false }
        let parts = snapshot.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "Recovery" else { return false }
        let name = parts[1]
        return name.hasPrefix("pre-migration-") && name.hasSuffix("-\(id.prefix(8)).sqlite")
            && name.utf8.allSatisfy { (48...57).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 46 }
            && !name.contains("..")
    }
}

/// Puts the pre-migration snapshot back as the library after a failed migration, resumably.
///
/// Order: copy the snapshot into `Staging/putback-<id>.sqlite.partial`, flush it and rename it to
/// `putback-<id>.sqlite`; only then move `library.sqlite`, `-wal` and `-shm` to `Recovery/failed-<id>/`,
/// rename the staged copy to `Library/library.sqlite`, and remove the intent. Each rename is followed
/// by a directory flush. Which files exist tells how far an interrupted put-back got:
///
/// * staged copy present: the live files (if any) are the failed ones; move them aside, move it in;
/// * no staged copy and `failed-<id>/library.sqlite` present: the staged copy was moved in;
/// * neither: staging had not finished (or the migration itself was interrupted); stage again from
///   the snapshot.
///
/// No state leaves `Library/` without a database once the put-back finishes, and the snapshot is
/// never modified, so the put-back can be repeated until it succeeds.
public enum MigrationPutBack {
    static func intentURL(_ layout: LibraryLayout) -> URL { layout.migrationPutBackIntentURL }
    static func stagedURL(_ layout: LibraryLayout, _ intent: PutBackIntent) -> URL {
        layout.stagingDirectory.appending(path: "putback-\(intent.id).sqlite", directoryHint: .notDirectory)
    }
    static func partialURL(_ layout: LibraryLayout, _ intent: PutBackIntent) -> URL {
        layout.stagingDirectory.appending(path: "putback-\(intent.id).sqlite.partial", directoryHint: .notDirectory)
    }
    static func failedDirectory(_ layout: LibraryLayout, _ intent: PutBackIntent) -> URL {
        layout.recoveryDirectory.appending(path: "failed-\(intent.id)", directoryHint: .isDirectory)
    }

    static func writeIntent(_ intent: PutBackIntent, layout: LibraryLayout, protector: FileProtector) throws {
        try DurableFile.writeDurably(try JSONEncoder.sorted.encode(intent), to: intentURL(layout),
                                     staging: layout.stagingDirectory, protector: protector)
    }

    static func removeIntent(_ layout: LibraryLayout) throws {
        try FileManager.default.removeItem(at: intentURL(layout))
        try DurableFile.syncDirectory(layout.libraryDirectory)
    }

    /// Runs at every open, after restore reconciliation and before the database is opened. With no
    /// intent it does nothing and returns nil. With a valid intent it finishes putting the snapshot
    /// back and returns the intent. An intent that exists but cannot be read (for example before
    /// first unlock) or is not valid is never acted on and never ignored: the open fails with
    /// nothing changed, so the library is never opened half put back.
    static func reconcile(_ layout: LibraryLayout, protector: FileProtector, hooks: PutBackHooks) throws -> PutBackIntent? {
        let url = intentURL(layout)
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Staged copies without an intent belong to a library a restore has since replaced (its
            // intent moved with it into `Recovery/pre-restore-*`, which can stage again from the
            // snapshot), so they are only wasted space.
            for name in try FileManager.default.contentsOfDirectory(atPath: layout.stagingDirectory.path) where name.hasPrefix("putback-") {
                try FileManager.default.removeItem(at: layout.stagingDirectory.appending(path: name, directoryHint: .notDirectory))
            }
            return nil
        }
        let data: Data
        do { data = try Data(contentsOf: url) } catch {
            throw StoreError.invalid("migration put-back intent exists but cannot be read; nothing was changed")
        }
        guard let intent = try? JSONDecoder().decode(PutBackIntent.self, from: data), intent.isValid else {
            throw StoreError.invalid("migration put-back intent is not valid; nothing was changed")
        }
        try complete(intent, layout: layout, protector: protector, hooks: hooks)
        return intent
    }

    /// Puts the snapshot named by `intent` back as `Library/library.sqlite` and removes the intent.
    /// The database must be closed. Safe to repeat from any interrupted state.
    static func complete(_ intent: PutBackIntent, layout: LibraryLayout, protector: FileProtector, hooks: PutBackHooks) throws {
        let fm = FileManager.default
        let staged = stagedURL(layout, intent)
        let failed = failedDirectory(layout, intent)
        let movedDatabase = failed.appending(path: layout.databaseURL.lastPathComponent, directoryHint: .notDirectory)

        let snapshotInPlace = !fm.fileExists(atPath: staged.path) && fm.fileExists(atPath: movedDatabase.path)
            && fm.fileExists(atPath: layout.databaseURL.path)
        if !snapshotInPlace {
            if !fm.fileExists(atPath: staged.path) {
                try stage(intent, layout: layout, protector: protector, hooks: hooks)
            }
            try protector.ensureDirectory(failed)
            for (url, step) in [(layout.databaseURL, PutBackStep.databaseMovedAside),
                                (layout.walURL, .walMovedAside), (layout.shmURL, .shmMovedAside)] {
                if fm.fileExists(atPath: url.path) {
                    if step == .databaseMovedAside { try hooks.performing(step) }
                    let target = failed.appending(path: url.lastPathComponent, directoryHint: .notDirectory)
                    guard !fm.fileExists(atPath: target.path) else {
                        throw StoreError.invalid("put-back: \(failed.lastPathComponent)/\(url.lastPathComponent) already exists; nothing more was changed")
                    }
                    try DurableFile.rename(url, to: target)
                    try DurableFile.syncDirectory(failed)
                    try DurableFile.syncDirectory(layout.libraryDirectory)
                }
                try hooks.completed(step)
            }
            try hooks.performing(.snapshotMovedIn)
            try DurableFile.rename(staged, to: layout.databaseURL)
            try DurableFile.syncDirectory(layout.libraryDirectory)
            try DurableFile.syncDirectory(layout.stagingDirectory)
            try hooks.completed(.snapshotMovedIn)
        }
        try removeIntent(layout)
        try hooks.completed(.intentRemoved)
    }

    /// Copies the snapshot to `Staging/putback-<id>.sqlite` (created with the protection class),
    /// checks its size, flushes it and publishes it with a rename. The live files are not touched.
    static func stage(_ intent: PutBackIntent, layout: LibraryLayout, protector: FileProtector, hooks: PutBackHooks) throws {
        let fm = FileManager.default
        let snapshot = layout.root.appending(path: intent.snapshot, directoryHint: .notDirectory)
        guard fm.fileExists(atPath: snapshot.path) else {
            throw StoreError.invalid("put-back: the pre-migration snapshot \(snapshot.lastPathComponent) is missing; nothing was changed")
        }
        let partial = partialURL(layout, intent)
        if fm.fileExists(atPath: partial.path) { try fm.removeItem(at: partial) }
        try hooks.performing(.staged)
        try protector.copyFile(from: snapshot, to: partial)
        guard fm.sizeOfFile(at: partial) == fm.sizeOfFile(at: snapshot) else {
            try? fm.removeItem(at: partial)
            throw StoreError.invalid("put-back: the staged copy of \(snapshot.lastPathComponent) is incomplete")
        }
        try DurableFile.sync(partial)
        try DurableFile.rename(partial, to: stagedURL(layout, intent))
        try DurableFile.syncDirectory(layout.stagingDirectory)
        try hooks.completed(.staged)
    }
}
