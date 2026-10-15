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
    /// A copy of the snapshot is complete and flushed in `Staging/Persistence/`. The live files are untouched.
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
    /// Throws a synthetic I/O error (`ENOSPC`) instead of performing this put-back step, standing in
    /// for a full disk. Injected only before `staged`, `databaseMovedAside`, `snapshotMovedIn` and
    /// `intentRemoved`; `ioErrorAtOperation` reaches every other operation.
    public var ioErrorAt: PutBackStep?
    /// Throws a synthetic `ENOSPC` instead of the n-th fallible file-system operation of a put-back
    /// (1-based, counted in `operations`, which must be set): every copy, flush, rename, directory
    /// creation and removal in `stage`, `complete` and the intent's removal, including the `-wal` and
    /// `-shm` moves when those files exist and the removal of an earlier partial copy when an
    /// interrupted staging left one (20 hooked operations in all). A test fails each in turn.
    public var ioErrorAtOperation: Int?
    /// Records the name of every fallible operation a put-back reaches, in order.
    public var operations: PutBackOperationLog?
    /// Called after each step completes (the SIGKILL drill uses it to report where kills landed).
    public var afterStep: (@Sendable (PutBackStep) -> Void)?

    public init(crashAfter: PutBackStep? = nil, ioErrorAt: PutBackStep? = nil,
                afterStep: (@Sendable (PutBackStep) -> Void)? = nil,
                ioErrorAtOperation: Int? = nil, operations: PutBackOperationLog? = nil) {
        self.crashAfter = crashAfter
        self.ioErrorAt = ioErrorAt
        self.afterStep = afterStep
        self.ioErrorAtOperation = ioErrorAtOperation
        self.operations = operations
    }

    func completed(_ step: PutBackStep) throws {
        afterStep?(step)
        if crashAfter == step { throw StoreError.simulatedCrash(step.rawValue) }
    }

    func performing(_ step: PutBackStep) throws {
        if ioErrorAt == step { throw FileSystemError.posix("put-back \(step.rawValue)", "simulated", ENOSPC) }
    }

    /// Called just before each fallible file-system operation of a put-back.
    func operation(_ name: String) throws {
        guard let operations else { return }
        let number = operations.record(name)
        if number == ioErrorAtOperation {
            throw FileSystemError.posix("put-back operation \(number) (\(name))", "simulated", ENOSPC)
        }
    }
}

/// The fallible operations a put-back reached, in order (test hook; see `PutBackHooks`).
public final class PutBackOperationLog: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []

    public init() {}

    public var recorded: [String] { lock.withLock { names } }

    /// Appends `name` and returns its 1-based position.
    func record(_ name: String) -> Int {
        lock.withLock {
            names.append(name)
            return names.count
        }
    }
}

/// The record that a migration guarded by a recovery snapshot is in progress. Written durably to
/// `Library/migration-putback.json` before the first migration runs and removed only when the
/// migration has passed its checks or the snapshot is back in place. It lives inside `Library/`, so a
/// restore swap moves it with the library it describes.
struct PutBackIntent: Codable, Equatable {
    var id: String
    /// Root-relative path of the pre-migration snapshot: `Recovery/pre-migration-<ms>-<id8>.sqlite`.
    /// A retry from the same pre-state reuses an earlier snapshot (`RecoveryRetention`), so `<id8>`
    /// is the snapshot's own and need not match `id`.
    var snapshot: String
    /// The migrations that were about to run.
    var pending: [String]

    var isValid: Bool {
        guard EntityID.isValid(id), !pending.isEmpty else { return false }
        let parts = snapshot.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "Recovery" else { return false }
        return Self.isSnapshotName(String(parts[1]))
    }

    /// Exactly `pre-migration-<1 to 19 digits>-<8 lowercase hex>.sqlite`: no separators, dots or
    /// other characters that could name anything outside `Recovery/`.
    static func isSnapshotName(_ name: String) -> Bool {
        let prefix = "pre-migration-", suffix = ".sqlite"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return false }
        let middle = name.utf8.dropFirst(prefix.utf8.count).dropLast(suffix.utf8.count)
        let fields = middle.split(separator: UInt8(ascii: "-"), omittingEmptySubsequences: false)
        guard fields.count == 2 else { return false }
        let time = fields[0], id8 = fields[1]
        return (1...19).contains(time.count) && time.allSatisfy { (48...57).contains($0) }
            && id8.count == 8 && id8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

/// Puts the pre-migration snapshot back as the library after a failed migration, resumably.
///
/// Order: copy the snapshot into `Staging/Persistence/putback-<id>.sqlite.partial` (after removing
/// a partial copy an interrupted staging left), flush it and rename it to
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
/// never modified, so the put-back can be repeated until it succeeds. Removing the intent is the
/// last step: once the intent is gone the put-back is complete, even if flushing that removal
/// failed (a removal lost to a crash only makes the next open repeat a put-back that finds the
/// snapshot already in place).
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

    static func removeIntent(_ layout: LibraryLayout, hooks: PutBackHooks = PutBackHooks()) throws {
        try hooks.operation("remove the intent")
        try FileManager.default.removeItem(at: intentURL(layout))
        try hooks.operation("flush Library after removing the intent")
        try DurableFile.syncDirectory(layout.libraryDirectory)
    }

    /// Whether the intent is still on disk. After a failed `complete`, false means the put-back
    /// finished (its last step removed the intent) and only a flush after that failed.
    static func intentPending(_ layout: LibraryLayout) -> Bool {
        FileManager.default.fileExists(atPath: intentURL(layout).path)
    }

    /// Runs at every open, after restore reconciliation and before the database is opened. With no
    /// intent it clears abandoned files from `Staging/Persistence/` and returns nil. With a valid
    /// intent it clears `Staging/Persistence/` except that put-back's staged and partial copies,
    /// finishes putting the snapshot back and returns the intent. An intent that exists but cannot
    /// be read (for example before first unlock) or is not valid is never acted on and never
    /// ignored: the open fails with nothing changed, so the library is never opened half put back.
    /// The rest of `Staging/` (intake's, ADR-0010) is never touched (`StagingCleanup`).
    static func reconcile(_ layout: LibraryLayout, protector: FileProtector, hooks: PutBackHooks) throws -> PutBackIntent? {
        let url = intentURL(layout)
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Nothing in Staging/Persistence/ belongs to a live operation (StagingCleanup). This
            // includes staged copies of a library a restore has since replaced: its intent moved with
            // it into `Recovery/pre-restore-*`, and a put-back of that library would stage again.
            StagingCleanup.removeAbandoned(layout)
            return nil
        }
        let data: Data
        do { data = try Data(contentsOf: url) } catch {
            throw StoreError.invalid("migration put-back intent exists but cannot be read; nothing was changed")
        }
        guard let intent = try? JSONDecoder().decode(PutBackIntent.self, from: data), intent.isValid else {
            throw StoreError.invalid("migration put-back intent is not valid; nothing was changed")
        }
        // Abandoned files may be what filled the disk. This put-back's own files are left to it:
        // the staged copy is moved in without being copied again (removing it would also be safe:
        // `complete` stages again when it is missing), and a partial copy from an interrupted
        // staging is removed by `stage` before it copies again.
        StagingCleanup.removeAbandoned(layout, keeping: [stagedURL(layout, intent).lastPathComponent,
                                                         partialURL(layout, intent).lastPathComponent])
        do {
            try complete(intent, layout: layout, protector: protector, hooks: hooks)
        } catch let error as StoreError where error.isSimulatedCrash {
            throw error
        } catch {
            // Only a flush after the intent's removal failed: the snapshot is back in place.
            guard intentPending(layout) else { return intent }
            // For example the disk is still full. The intent stays, the library is not opened, and the
            // recovery screen can recognise this case instead of a raw file-system error.
            throw StoreError.migrationPutBackPending(reason: String(describing: error))
        }
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
            try hooks.operation("create failed-<id>")
            try protector.ensureDirectory(failed)
            for (url, step) in [(layout.databaseURL, PutBackStep.databaseMovedAside),
                                (layout.walURL, .walMovedAside), (layout.shmURL, .shmMovedAside)] {
                if fm.fileExists(atPath: url.path) {
                    if step == .databaseMovedAside { try hooks.performing(step) }
                    let target = failed.appending(path: url.lastPathComponent, directoryHint: .notDirectory)
                    guard !fm.fileExists(atPath: target.path) else {
                        throw StoreError.invalid("put-back: \(failed.lastPathComponent)/\(url.lastPathComponent) already exists; nothing more was changed")
                    }
                    try hooks.operation("move \(url.lastPathComponent) aside")
                    try DurableFile.rename(url, to: target)
                    try hooks.operation("flush failed-<id> after moving \(url.lastPathComponent)")
                    try DurableFile.syncDirectory(failed)
                    try hooks.operation("flush Library after moving \(url.lastPathComponent)")
                    try DurableFile.syncDirectory(layout.libraryDirectory)
                }
                try hooks.completed(step)
            }
            try hooks.performing(.snapshotMovedIn)
            try hooks.operation("move the staged copy into Library")
            try DurableFile.rename(staged, to: layout.databaseURL)
            try hooks.operation("flush Library after the move in")
            try DurableFile.syncDirectory(layout.libraryDirectory)
            try hooks.operation("flush Staging after the move in")
            try DurableFile.syncDirectory(layout.stagingDirectory)
            try hooks.completed(.snapshotMovedIn)
        }
        try hooks.performing(.intentRemoved)
        try removeIntent(layout, hooks: hooks)
        try hooks.completed(.intentRemoved)
        // Only now, with no intent left, apply the Recovery/ retention rule: keep this put-back's
        // snapshot and failed copy, remove older ones (best effort).
        RecoveryRetention.prune(layout, keepSnapshot: String(intent.snapshot.dropFirst("Recovery/".count)),
                                keepFailed: failed.lastPathComponent)
    }

    /// Copies the snapshot to `Staging/Persistence/putback-<id>.sqlite` (created with the protection
    /// class), checks its size, flushes it and publishes it with a rename. The live files are not
    /// touched. A partial copy left by an interrupted staging (a crash or an error during the copy
    /// or its flush) is removed first; the open's cleanup keeps it for this. The size check is
    /// defensive: `copyFile` throws on a failed read or write, so no test reaches it.
    static func stage(_ intent: PutBackIntent, layout: LibraryLayout, protector: FileProtector, hooks: PutBackHooks) throws {
        let fm = FileManager.default
        let snapshot = layout.root.appending(path: intent.snapshot, directoryHint: .notDirectory)
        guard fm.fileExists(atPath: snapshot.path) else {
            throw StoreError.invalid("put-back: the pre-migration snapshot \(snapshot.lastPathComponent) is missing; nothing was changed")
        }
        let partial = partialURL(layout, intent)
        if fm.fileExists(atPath: partial.path) {
            try hooks.operation("remove an earlier partial copy")
            try fm.removeItem(at: partial)
        }
        try hooks.performing(.staged)
        try hooks.operation("copy the snapshot into Staging")
        try protector.copyFile(from: snapshot, to: partial)
        guard fm.sizeOfFile(at: partial) == fm.sizeOfFile(at: snapshot) else {
            try? fm.removeItem(at: partial)
            throw StoreError.invalid("put-back: the staged copy of \(snapshot.lastPathComponent) is incomplete")
        }
        try hooks.operation("flush the staged copy")
        try DurableFile.sync(partial)
        try hooks.operation("publish the staged copy")
        try DurableFile.rename(partial, to: stagedURL(layout, intent))
        try hooks.operation("flush Staging after staging")
        try DurableFile.syncDirectory(layout.stagingDirectory)
        try hooks.completed(.staged)
    }
}
