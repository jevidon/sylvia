import Foundation
import GRDB
import Testing
@testable import SylviaRecovery

/// The failed-migration put-back is resumable (plan 7.4 "a failed migration opens a recovery screen,
/// not an empty replacement library"; T45). Each test interrupts it at a step, the way a crash or a
/// full disk would, and reopens through the launch path.
@Suite("Migration put-back (plan 7.4, T45)")
struct PutBackTests {
    let migrations = MigrationTests()

    /// Nothing of an interrupted put-back is left once the library is open again.
    func expectNoPutBackLeftovers(_ layout: LibraryLayout) throws {
        #expect(!FileManager.default.fileExists(atPath: layout.migrationPutBackIntentURL.path), "put-back intent left behind")
        let staged = try FileManager.default.contentsOfDirectory(atPath: layout.stagingDirectory.path).filter { $0.hasPrefix("putback-") }
        #expect(staged.isEmpty, "staged put-back copies left behind: \(staged)")
    }

    /// The next opens after an interruption: the first finishes the put-back (and says so) unless
    /// the put-back had already finished, and the library is then the complete v1 library; the
    /// following open migrates it with every row intact.
    func expectRecovered(_ layout: LibraryLayout, before: (applied: [String], dump: String, all: String),
                         putBackPending: Bool, label: String) throws {
        if putBackPending {
            #expect(throws: StoreError.migrationInterrupted(pending: ["v2-rating-review-note", "v2-recommendation-date-precision", "v2-edition-cover-thumbnail"])) {
                _ = try LibraryStore.open(layout)
            }
            let shown = try migrations.readOnly(layout)
            #expect(shown.applied == ["v1-initial"] && shown.all == before.all, "\(label): the put-back library is not the v1 library")
        }
        let store = try LibraryStore.open(layout)
        defer { try? store.close() }
        #expect(try store.schemaVersion == 2)
        #expect(try store.pool.read { try MigrationTests.preservedDump($0) } == before.dump, "\(label): rows changed")
        try store.pool.read { (db: Database) throws in
            #expect(try LibraryChecks.integrity(db) == ["ok"])
            #expect(try LibraryChecks.foreignKeyViolations(db).isEmpty)
        }
        try expectNoPutBackLeftovers(layout)
    }

    @Test("a crash after any step of a guarded migration or its put-back never leaves an empty or partial library",
          arguments: PutBackStep.allCases)
    func crashAfterStep(step: PutBackStep) throws {
        let scratch = try Scratch()
        let layout = try migrations.installV1(scratch)
        let before = try migrations.readOnly(layout)
        var options = StoreOptions()
        // `migrationChecked` is on the success path; every other step after `intentWritten` is on the
        // failure path, reached with a migration that throws.
        if step != .migrationChecked && step != .intentWritten { options.faults.throwDuringRecommendationRebuild = true }
        options.putBackHooks = PutBackHooks(crashAfter: step)
        #expect(throws: StoreError.simulatedCrash(step.rawValue)) { _ = try LibraryStore.open(layout, options: options) }
        let intentLeft = FileManager.default.fileExists(atPath: layout.migrationPutBackIntentURL.path)
        let databaseLeft = FileManager.default.fileExists(atPath: layout.databaseURL.path)
        evidence("put-back crash after \(step.rawValue): intent on disk \(intentLeft), library.sqlite present \(databaseLeft)")
        #expect(intentLeft == (step != .intentRemoved))
        try expectRecovered(layout, before: before, putBackPending: step != .intentRemoved, label: step.rawValue)
    }

    #if os(macOS)
    @Test("SIGKILL at every put-back step and at random times never leaves an empty or partial library (short run; CI runs 240)")
    func migrationCrashDrillShort() throws {
        let scratch = try Scratch()
        let executable = toolExecutable()
        #expect(FileManager.default.isExecutableFile(atPath: executable.path), "tool not built at \(executable.path)")
        let drill = MigrationCrashDrillParent(executable: executable, workDirectory: scratch.dir("migration-crash"), iterations: 24, seed: 12)
        let report = try drill.run()
        evidence("migration put-back crash drill (short)\n\(report)")
        #expect(report.failures.isEmpty)
        #expect(report.killsByPlan.keys.filter { $0.hasPrefix("pause ") }.count == MigrationCrashDrill.failurePathSteps.count,
                "every put-back step must be killed at least once")
        #expect((report.firstReopen["put back, then migrated at the next open"] ?? 0) > 0)
    }
    #endif

    @Test("an injected ENOSPC during the put-back fails the open with the intent kept; the next open finishes it",
          arguments: [PutBackStep.staged, .databaseMovedAside, .snapshotMovedIn, .intentRemoved])
    func ioErrorDuringPutBack(step: PutBackStep) throws {
        let scratch = try Scratch()
        let layout = try migrations.installV1(scratch)
        let before = try migrations.readOnly(layout)
        var options = StoreOptions()
        options.faults.throwDuringRecommendationRebuild = true
        options.putBackHooks = PutBackHooks(ioErrorAt: step)
        #expect {
            _ = try LibraryStore.open(layout, options: options)
        } throws: { error in
            guard case StoreError.migrationFailed(let id, let reason, false) = error else { return false }
            evidence("put-back I/O error at \(step.rawValue): \(error)")
            return id == "v2-recommendation-date-precision" && reason.contains("No space left on device")
                && reason.contains("the next open finishes it")
        }
        #expect(FileManager.default.fileExists(atPath: layout.migrationPutBackIntentURL.path))
        // At `snapshotMovedIn` the failed files are already aside, so `Library/` has no database
        // until the next open finishes the put-back; it must not create an empty one.
        #expect(FileManager.default.fileExists(atPath: layout.databaseURL.path) == (step != .snapshotMovedIn))
        try expectRecovered(layout, before: before, putBackPending: true, label: step.rawValue)
    }

    @Test("a put-back that still cannot finish at the next open (the disk is still full) fails with the typed migrationPutBackPending error",
          arguments: [PutBackStep.staged, .databaseMovedAside, .snapshotMovedIn, .intentRemoved])
    func putBackStillFailingAtNextOpen(step: PutBackStep) throws {
        let scratch = try Scratch()
        let layout = try migrations.installV1(scratch)
        let before = try migrations.readOnly(layout)
        var options = StoreOptions()
        options.faults.throwDuringRecommendationRebuild = true
        options.putBackHooks = PutBackHooks(ioErrorAt: step)
        #expect(throws: StoreError.self) { _ = try LibraryStore.open(layout, options: options) }
        // The next launch: no migration fault, but the same put-back step still fails.
        var stillFull = StoreOptions()
        stillFull.putBackHooks = PutBackHooks(ioErrorAt: step)
        #expect {
            _ = try LibraryStore.open(layout, options: stillFull)
        } throws: { error in
            guard case StoreError.migrationPutBackPending(let reason) = error else { return false }
            evidence("put-back still failing at the next open (\(step.rawValue)): \(error)")
            return reason.contains("No space left on device") && reason.contains(step.rawValue)
        }
        #expect(FileManager.default.fileExists(atPath: layout.migrationPutBackIntentURL.path), "the intent must be kept")
        #expect(FileManager.default.fileExists(atPath: layout.databaseURL.path) == (step != .snapshotMovedIn))
        // Once space is back, the next opens finish the put-back and migrate.
        try expectRecovered(layout, before: before, putBackPending: true, label: "\(step.rawValue), still failing once")
    }

    static let pendingMigrations = ["v2-rating-review-note", "v2-recommendation-date-precision", "v2-edition-cover-thumbnail"]

    /// Leaves the failed library's real `-wal`, holding a committed frame that is not in the database
    /// file, and its `-shm` beside it, as a process killed after a commit would. Paired with the
    /// snapshot, that frame would be applied to the wrong database. Returns the files' bytes by name.
    func plantWALAndSHM(_ layout: LibraryLayout) throws -> [String: Data] {
        let fm = FileManager.default
        let saved = layout.root.appending(path: "database-before-frame.sqlite")
        try fm.copyItem(at: layout.databaseURL, to: saved)
        let queue = try DatabaseQueue(path: layout.databaseURL.path)
        #expect(try queue.read { try String.fetchOne($0, sql: "PRAGMA journal_mode") } == "wal")
        try queue.write { try $0.execute(sql: "UPDATE work SET title = 'only in the old -wal'") }
        let wal = try Data(contentsOf: layout.walURL)
        let shm = try Data(contentsOf: layout.shmURL)
        try queue.close()
        try fm.removeItem(at: layout.databaseURL)
        try fm.moveItem(at: saved, to: layout.databaseURL)
        try wal.write(to: layout.walURL)
        try shm.write(to: layout.shmURL)
        #expect(wal.count > 32, "the -wal must hold a frame, not only its header")
        return [layout.walURL.lastPathComponent: wal, layout.shmURL.lastPathComponent: shm]
    }

    /// Fails each fallible file operation of a put-back in turn with an injected `ENOSPC`: every copy,
    /// flush, rename, directory creation and removal (the step hooks above cover four of them; review
    /// round 3 noted that the others were not exercised). "in the failing open": the put-back runs in
    /// the open whose migration failed, after its pool closed. "at the next open, with -wal and -shm":
    /// the process died right after the migration failed (simulated) and left the failed library's
    /// real `-wal` and `-shm`, and the next launch puts the snapshot back. "..., and an earlier partial
    /// copy": the same, plus a partial staged copy (the snapshot's first pages) that a staging
    /// interrupted mid-copy leaves, so the put-back's 20th hooked operation, removing it, is reached
    /// too (review round 4 found it unreached). After every injected failure the following opens must
    /// finish the put-back, never leave the old `-wal` beside the snapshot, and then migrate with
    /// every row intact.
    @Test("an injected ENOSPC at each fallible file operation of a put-back leaves a state the next open finishes",
          arguments: ["in the failing open", "at the next open, with -wal and -shm",
                      "at the next open, with -wal, -shm and an earlier partial copy"])
    func ioErrorAtEveryOperation(path: String) throws {
        let fm = FileManager.default
        let atNextOpen = path != "in the failing open"
        let withPartial = path.hasSuffix("an earlier partial copy")
        var operations: [String] = []
        var completeDespiteError: [String] = []
        var number = 1
        while true {
            let scratch = try Scratch()
            let layout = try migrations.installV1(scratch)
            let before = try migrations.readOnly(layout)
            var injected = StoreOptions()
            var planted: [String: Data] = [:]
            var failedCopy: URL?
            if atNextOpen {
                var dying = StoreOptions()
                dying.faults.throwDuringRecommendationRebuild = true
                dying.putBackHooks = PutBackHooks(crashAfter: .migrationFailed)
                #expect(throws: StoreError.simulatedCrash("migrationFailed")) { _ = try LibraryStore.open(layout, options: dying) }
                let intent = try JSONDecoder().decode(PutBackIntent.self, from: Data(contentsOf: layout.migrationPutBackIntentURL))
                failedCopy = MigrationPutBack.failedDirectory(layout, intent)
                planted = try plantWALAndSHM(layout)
                if withPartial {
                    // What a staging killed mid-copy leaves: the snapshot's first pages under the partial name.
                    let snapshot = try Data(contentsOf: layout.root.appending(path: intent.snapshot))
                    try snapshot.prefix(snapshot.count / 3).write(to: MigrationPutBack.partialURL(layout, intent))
                }
            } else {
                injected.faults.throwDuringRecommendationRebuild = true
            }
            let log = PutBackOperationLog()
            injected.putBackHooks = PutBackHooks(ioErrorAtOperation: number, operations: log)
            var thrown: (any Error)?
            do { _ = try LibraryStore.open(layout, options: injected) } catch { thrown = error }
            guard log.recorded.count >= number else {
                // Past the last operation: this put-back ran without an injected error.
                operations = log.recorded
                if atNextOpen {
                    #expect(thrown as? StoreError == .migrationInterrupted(pending: Self.pendingMigrations), "\(String(describing: thrown))")
                } else {
                    #expect(thrown as? StoreError == .migrationFailed(identifier: "v2-recommendation-date-precision",
                                                                      reason: "injected fault during v2-recommendation-date-precision",
                                                                      restoredFromSnapshot: true), "\(String(describing: thrown))")
                }
                break
            }
            let failed = log.recorded[number - 1]
            let label = "\(path), operation \(number) (\(failed))"
            let pending = fm.fileExists(atPath: layout.migrationPutBackIntentURL.path)
            // What the app is told.
            switch (thrown as? StoreError, pending, atNextOpen) {
            case (.migrationFailed(let id, let reason, false)?, true, false):
                #expect(id == "v2-recommendation-date-precision" && reason.contains("No space left on device")
                        && reason.contains(failed) && reason.contains("the next open finishes it"), "\(label): \(reason)")
            case (.migrationPutBackPending(let reason)?, true, true):
                #expect(reason.contains("No space left on device") && reason.contains(failed), "\(label): \(reason)")
            case (.migrationFailed(_, _, true)?, false, false), (.migrationInterrupted?, false, true):
                // Only a flush after the intent's removal failed: the put-back is complete.
                completeDespiteError.append(failed)
            default:
                Issue.record("\(label): unexpected outcome \(String(describing: thrown)), intent pending \(pending)")
            }
            if pending {
                // The next launch finishes the put-back before SQLite opens anything.
                #expect(throws: StoreError.migrationInterrupted(pending: Self.pendingMigrations)) { _ = try LibraryStore.open(layout) }
                #expect(!fm.fileExists(atPath: layout.migrationPutBackIntentURL.path), "\(label): intent left")
            }
            // The put-back is complete and nothing has opened the library since.
            if let failedCopy {
                #expect(!fm.fileExists(atPath: layout.walURL.path) && !fm.fileExists(atPath: layout.shmURL.path),
                        "\(label): the old -wal or -shm is beside the snapshot")
                for (name, data) in planted {
                    #expect((try? Data(contentsOf: failedCopy.appending(path: name))) == data, "\(label): \(name) not kept in \(failedCopy.lastPathComponent)")
                }
            }
            let shown = try migrations.readOnly(layout)
            #expect(shown.applied == ["v1-initial"] && shown.all == before.all, "\(label): the put-back library is not the v1 library")
            try expectRecovered(layout, before: before, putBackPending: false, label: label)
            number += 1
            guard number <= 64 else { Issue.record("\(path): more than 64 put-back operations"); break }
        }
        #expect(operations.count == number - 1)
        #expect(operations.contains("copy the snapshot into Staging") && operations.contains("move the staged copy into Library")
                && operations.contains("remove the intent"), "\(operations)")
        if atNextOpen {
            #expect(operations.contains("move library.sqlite-wal aside") && operations.contains("move library.sqlite-shm aside"), "\(operations)")
        }
        // The removal of an earlier partial copy happens exactly when one exists, and first.
        #expect(operations.contains("remove an earlier partial copy") == withPartial, "\(operations)")
        if withPartial { #expect(operations.first == "remove an earlier partial copy", "\(operations)") }
        if atNextOpen {
            // The test planted -wal and -shm, so every hooked operation is reached: 19, and 20 with an
            // earlier partial copy. (In the failing open, whether -wal and -shm are still there after
            // the pool closes depends on SQLite's persistent-WAL default; the evidence line counts them.)
            #expect(operations.count == (withPartial ? 20 : 19), "\(operations.count) operations: \(operations)")
        }
        evidence("put-back \(path): \(operations.count) fallible operations, each failed in turn with an injected ENOSPC and finished by the next open"
                 + " (the snapshot never beside the old -wal or -shm; every row intact after migrating): \(operations.joined(separator: "; "))"
                 + "; complete despite the error (only the flush after removing the intent failed): \(completeDespiteError)")
    }

    func stagingItems(_ layout: LibraryLayout) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: layout.stagingDirectory.path).sorted()
    }

    /// What crashes and errors can leave in this layer's `Staging/Persistence/`: a media import's
    /// copy, a snapshot being taken (with its rollback journal), a durable write's temp file,
    /// put-back copies of another intent, and a directory. Returns the names and their total size.
    func plantStagingLeftovers(_ layout: LibraryLayout) throws -> (names: [String], bytes: Int) {
        let staging = layout.stagingDirectory
        let files: [(String, Int)] = [("\(EntityID.make()).media", 3 << 20), ("\(EntityID.make()).sqlite", 64 << 10),
                                      ("\(EntityID.make()).sqlite-journal", 4096), ("\(EntityID.make()).tmp", 120),
                                      ("putback-\(EntityID.make()).sqlite", 64 << 10), ("putback-\(EntityID.make()).sqlite.partial", 8192)]
        for (name, size) in files {
            try DeterministicBytes.make(seed: UInt64(size), count: size).write(to: staging.appending(path: name))
        }
        let directory = staging.appending(path: "leftover-\(EntityID.make())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("inner".utf8).write(to: directory.appending(path: "inner.bin"))
        return (files.map(\.0) + [directory.lastPathComponent], files.map(\.1).reduce(5, +))
    }

    /// Intake's durable state in the shared `Staging/`, laid out as ADR-0010 and G0.3's
    /// `StorageLayout` keep it: the import journal, a staged job whose bytes are the only copy of a
    /// shared item already reported as received, a rejected handoff kept for "Inspect details", a
    /// claimed abandoned handoff, an extraction in progress, and two top-level files whose names
    /// have this layer's own temporary-file forms (only `Staging/Persistence/` is this layer's).
    func plantIntakeState(_ layout: LibraryLayout) throws {
        let staging = layout.sharedStagingDirectory
        let staged = EntityID.make(), rejected = EntityID.make(), abandoned = EntityID.make(), job = EntityID.make()
        let files: [(String, Data)] = [
            ("journal.json", Data(#"{"jobs":[{"id":"\#(staged)","state":"staged"},{"id":"\#(job)","state":"acquiring"}]}"#.utf8)),
            ("Staged/\(staged)/handoff.json", Data(#"{"handoff_id":"\#(staged)","items":[{"stored_path":"items/0.epub"}]}"#.utf8)),
            ("Staged/\(staged)/items/0.epub", DeterministicBytes.make(seed: 31, count: 96 << 10)),
            ("Rejected/\(rejected)/handoff.json", Data("{ tampered".utf8)),
            ("Abandoned/\(abandoned)/items/0.pdf", DeterministicBytes.make(seed: 32, count: 8192)),
            ("Extracting/\(job)/0.m4b", DeterministicBytes.make(seed: 33, count: 128 << 10)),
            ("\(EntityID.make()).tmp", Data("not this layer's".utf8)),
            ("putback-\(EntityID.make()).sqlite.partial", DeterministicBytes.make(seed: 34, count: 4096)),
        ]
        for (path, data) in files {
            let url = staging.appending(path: path, directoryHint: .notDirectory)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
    }

    /// Every entry of the shared `Staging/` outside this layer's `Persistence/`: relative path to
    /// "directory" or size and SHA-256.
    func intakeTree(_ layout: LibraryLayout) throws -> [String: String] {
        let staging = layout.sharedStagingDirectory
        var tree: [String: String] = [:]
        for path in try FileManager.default.subpathsOfDirectory(atPath: staging.path)
        where path != "Persistence" && !path.hasPrefix("Persistence/") {
            let url = staging.appending(path: path)
            if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                tree[path] = "directory"
            } else {
                let (sha, size) = try Digest.sha256Hex(fileAt: url)
                tree[path] = "\(size):\(sha)"
            }
        }
        return tree
    }

    @Test("abandoned files in Staging/Persistence/ are removed at launch, and intake's state elsewhere in Staging/ is never touched; a pending put-back keeps and uses its staged copy")
    func abandonedStagingIsCleared() throws {
        // No intent pending: everything in Staging/Persistence/ is abandoned; nothing else is ours.
        let scratch = try Scratch()
        let layout = scratch.layout()
        try CrashDrill.seed(layout, durability: .acknowledgedSaves)
        let planted = try plantStagingLeftovers(layout)
        try plantIntakeState(layout)
        let intake = try intakeTree(layout)
        #expect(try stagingItems(layout).count == planted.names.count)
        let store = try LibraryStore.open(layout)
        try store.close()
        let left = try stagingItems(layout)
        #expect(left.isEmpty, "\(left)")
        #expect(try intakeTree(layout) == intake, "the open changed intake's state in Staging/")

        // A put-back pending after a crash right after staging: the next open removes the abandoned
        // files, including another intent's put-back copies, moves the staged copy in without
        // copying the snapshot again, and leaves intake's state alone.
        let pendingScratch = try Scratch("abandonedStagingWithPutBack")
        let pendingLayout = try migrations.installV1(pendingScratch)
        let before = try migrations.readOnly(pendingLayout)
        var dying = StoreOptions()
        dying.faults.throwDuringRecommendationRebuild = true
        dying.putBackHooks = PutBackHooks(crashAfter: .staged)
        #expect(throws: StoreError.simulatedCrash("staged")) { _ = try LibraryStore.open(pendingLayout, options: dying) }
        let staged = try stagingItems(pendingLayout)
        #expect(staged.count == 1 && staged[0].hasPrefix("putback-") && staged[0].hasSuffix(".sqlite"), "\(staged)")
        _ = try plantStagingLeftovers(pendingLayout)
        try plantIntakeState(pendingLayout)
        let pendingIntake = try intakeTree(pendingLayout)
        let log = PutBackOperationLog()
        var resuming = StoreOptions()
        resuming.putBackHooks = PutBackHooks(operations: log)
        #expect(throws: StoreError.migrationInterrupted(pending: Self.pendingMigrations)) { _ = try LibraryStore.open(pendingLayout, options: resuming) }
        #expect(!log.recorded.contains("copy the snapshot into Staging"), "the staged copy must be reused: \(log.recorded)")
        let leftWithPutBack = try stagingItems(pendingLayout)
        #expect(leftWithPutBack.isEmpty, "\(leftWithPutBack)")
        #expect(try migrations.readOnly(pendingLayout).all == before.all)
        try expectRecovered(pendingLayout, before: before, putBackPending: false, label: "staging cleanup with a pending put-back")
        #expect(try intakeTree(pendingLayout) == pendingIntake, "the put-back or the migration changed intake's state in Staging/")
        evidence("Staging/Persistence/ at launch: \(planted.names.count) abandoned entries (\(planted.bytes) bytes: a media copy, a snapshot and its journal, a temp file, put-back copies of another intent, a directory) removed; with a put-back pending, the same removed and its staged copy moved in without a second copy of the snapshot. Intake's state in Staging/ (ADR-0010: \(intake.count) entries, \(intake.keys.filter { !$0.contains("/") }.sorted().joined(separator: ", ")) at the top level) byte for byte unchanged by both opens and the migration")
    }

    func recoveryItems(_ layout: LibraryLayout) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: layout.recoveryDirectory.path).filter { !$0.hasPrefix(".") }.sorted()
    }

    func recoveryBytes(_ layout: LibraryLayout) throws -> Int64 {
        try treeFingerprint(layout.recoveryDirectory).values.reduce(0) { $0 + Int64($1.split(separator: ":")[0])! }
    }

    @Test("repeated failing launches reuse one pre-migration snapshot and keep one failed copy; success removes the failed copy (review round 3)")
    func repeatedFailuresKeepRecoveryBounded() throws {
        let scratch = try Scratch()
        let layout = try migrations.installV1(scratch)
        let before = try migrations.readOnly(layout)
        let libraryBytes = FileManager.default.sizeOfFile(at: layout.databaseURL)
        var failing = StoreOptions()
        failing.faults.throwDuringRecommendationRebuild = true
        var snapshots: Set<String> = []
        var failedCopies: Set<String> = []
        var sizes: [Int64] = []
        for attempt in 1...4 {
            #expect(throws: StoreError.migrationFailed(identifier: "v2-recommendation-date-precision",
                                                       reason: "injected fault during v2-recommendation-date-precision",
                                                       restoredFromSnapshot: true)) {
                _ = try LibraryStore.open(layout, options: failing)
            }
            let items = try recoveryItems(layout)
            let snapshot = items.filter { $0.hasPrefix("pre-migration-") }
            let failed = items.filter { $0.hasPrefix("failed-") }
            #expect(items.count == 2 && snapshot.count == 1 && failed.count == 1, "attempt \(attempt): \(items)")
            snapshots.formUnion(snapshot)
            failedCopies.formUnion(failed)
            sizes.append(try recoveryBytes(layout))
            #expect(try migrations.readOnly(layout).all == before.all, "attempt \(attempt): the put-back library is not the v1 library")
        }
        evidence("4 failing launches of a \(libraryBytes)-byte v1 library: Recovery/ bytes \(sizes.map(String.init).joined(separator: " / ")); snapshots used \(snapshots.count), failed copies created \(failedCopies.count), Recovery/ holds 2 items after each launch")
        #expect(snapshots.count == 1, "a retry from the same pre-state must reuse the snapshot: \(snapshots)")
        #expect(failedCopies.count == 4, "each failed launch has its own failed copy, older ones removed")
        #expect(sizes.max()! < sizes.min()! + libraryBytes / 2, "Recovery/ grew: \(sizes)")

        // The migration now succeeds: the snapshot it used is kept, the failed copy goes.
        let store = try LibraryStore.open(layout)
        defer { try? store.close() }
        #expect(store.openReport.recoverySnapshotReused)
        #expect(try store.pool.read { try MigrationTests.preservedDump($0) } == before.dump)
        #expect(try recoveryItems(layout) == Array(snapshots), "after success Recovery/ must hold only the snapshot")
        let prune = try #require(store.openReport.recoveryPrune)
        #expect(prune.removed.count == 1 && prune.removed[0].hasPrefix("failed-") && prune.errors.isEmpty, "\(prune)")
        evidence("successful migration after the failures reused \(snapshots.first!) and removed \(prune.removed)")
    }

    @Test("a different pre-state takes a new snapshot; the put-back then removes the older snapshot and failed copy")
    func changedPreStateTakesNewSnapshot() throws {
        let scratch = try Scratch()
        let layout = try migrations.installV1(scratch)
        var failing = StoreOptions()
        failing.faults.throwDuringRecommendationRebuild = true
        #expect(throws: StoreError.self) { _ = try LibraryStore.open(layout, options: failing) }
        let first = try recoveryItems(layout)
        // Change the library outside the open (as a restore of another v1 backup would).
        let queue = try DatabaseQueue(path: layout.databaseURL.path)
        try queue.write { try $0.execute(sql: "UPDATE work SET title = title || ' (changed)' WHERE rowid = (SELECT min(rowid) FROM work)") }
        try queue.close()
        let changed = try migrations.readOnly(layout)
        #expect(throws: StoreError.self) { _ = try LibraryStore.open(layout, options: failing) }
        let second = try recoveryItems(layout)
        #expect(second.count == 2 && Set(second).isDisjoint(with: first), "first \(first), second \(second)")
        #expect(try migrations.readOnly(layout).all == changed.all, "the put-back library must be the changed pre-state")
        evidence("changed pre-state: Recovery/ \(first) replaced by \(second)")
    }

    /// Review round 4: snapshot reuse rests on `LibraryChecks.contentDigest`, which hashed GRDB's
    /// decoded strings, and GRDB decodes TEXT as a C string. The reviewer's probe (two tables
    /// holding `CAST(X'61006D696E65' AS TEXT)` and `CAST(X'61007468656972' AS TEXT)`) gave equal
    /// digests. The digest now reads every value as stored.
    @Test("the content digest sees every stored byte: text after a NUL, invalid UTF-8 and value types change it; row order does not (review round 4)")
    func contentDigestIsExact() throws {
        func state(_ sql: String) throws -> (digest: String, decoded: [String]) {
            let queue = try DatabaseQueue()
            try queue.write { try $0.execute(sql: sql) }
            return try queue.read { (db: Database) throws in
                let decoded = try Row.fetchAll(db, sql: "SELECT x FROM t ORDER BY rowid").map { String(describing: $0["x"] as DatabaseValue) }
                return (try LibraryChecks.contentDigest(db), decoded)
            }
        }
        let strict = "CREATE TABLE t(x TEXT) STRICT;"
        // The reviewer's probe: different bytes after a NUL, which GRDB decodes to the same "a".
        let mine = try state(strict + "INSERT INTO t VALUES (CAST(X'61006D696E65' AS TEXT))")
        let theirs = try state(strict + "INSERT INTO t VALUES (CAST(X'61007468656972' AS TEXT))")
        #expect(mine.decoded == theirs.decoded, "GRDB should decode both as the same string: \(mine.decoded) \(theirs.decoded)")
        #expect(mine.digest != theirs.digest, "text after a NUL must change the digest")
        // Invalid UTF-8: GRDB replaces each bad byte with U+FFFD, so both decode alike.
        let ff = try state(strict + "INSERT INTO t VALUES (CAST(X'61FF' AS TEXT))")
        let fe = try state(strict + "INSERT INTO t VALUES (CAST(X'61FE' AS TEXT))")
        #expect(ff.decoded == fe.decoded, "\(ff.decoded) \(fe.decoded)")
        #expect(ff.digest != fe.digest, "different invalid UTF-8 must change the digest")
        // Types: an integer is not the same digits stored as text.
        #expect(try state("CREATE TABLE t(x); INSERT INTO t VALUES (42)").digest
                != state("CREATE TABLE t(x); INSERT INTO t VALUES ('42')").digest)
        // Equal content is equal whatever the insertion order, and the same bytes give the same digest.
        #expect(try state(strict + "INSERT INTO t VALUES ('b'), ('a')").digest == state(strict + "INSERT INTO t VALUES ('a'), ('b')").digest)
        #expect(try state(strict + "INSERT INTO t VALUES (CAST(X'61006D696E65' AS TEXT))").digest == mine.digest)
        evidence("content digest: the review's probe (GRDB decodes both as \(mine.decoded)) now differs; invalid UTF-8 61FF and 61FE (decoded alike as \(ff.decoded)) differ; integer 42 and text '42' differ; row order does not matter")
    }

    @Test("a pre-state that differs only after an embedded NUL takes a new snapshot instead of reusing the old one (review round 4)")
    func preStateDifferingAfterNULTakesNewSnapshot() throws {
        let scratch = try Scratch()
        let layout = try migrations.installV1(scratch)
        var failing = StoreOptions()
        failing.faults.throwDuringRecommendationRebuild = true
        #expect(throws: StoreError.self) { _ = try LibraryStore.open(layout, options: failing) }
        let first = try recoveryItems(layout)
        // Change one title only after an embedded NUL (no app write can do this; a crafted database
        // or a tool could). GRDB decodes the title exactly as before.
        let queue = try DatabaseQueue(path: layout.databaseURL.path)
        let title = "SELECT title FROM work WHERE rowid = (SELECT min(rowid) FROM work)"
        let decodedBefore = try queue.read { try String.fetchOne($0, sql: title) }
        try queue.write { try $0.execute(sql: """
            UPDATE work SET title = CAST(CAST(title AS BLOB) || X'00' || CAST('changed' AS BLOB) AS TEXT)
            WHERE rowid = (SELECT min(rowid) FROM work)
            """) }
        let decodedAfter = try queue.read { try String.fetchOne($0, sql: title) }
        try queue.close()
        #expect(decodedAfter == decodedBefore, "GRDB should not see the change: \(String(describing: decodedBefore)) / \(String(describing: decodedAfter))")
        let changed = try migrations.readOnly(layout)
        #expect(throws: StoreError.self) { _ = try LibraryStore.open(layout, options: failing) }
        let second = try recoveryItems(layout)
        #expect(second.count == 2 && Set(second).isDisjoint(with: first), "the old snapshot must not be reused: first \(first), second \(second)")
        #expect(try migrations.readOnly(layout).all == changed.all, "the put-back library must be the changed pre-state, byte for byte")
        evidence("pre-state changed only after an embedded NUL (GRDB decodes the title alike): Recovery/ \(first) replaced by \(second), and the put-back library equals the changed pre-state")
    }

    @Test("pruning keeps the snapshot and failed copy a pre-restore copy's pending intent names, and removes nothing if that intent is unreadable")
    func pruneKeepsWhatAPreRestoreIntentNeeds() throws {
        let scratch = try Scratch()
        let (source, _) = try corpusLibrary(scratch, "Source")
        let bundle = scratch.dir("Exports/b.sylviabackup")
        try FileManager.default.createDirectory(at: bundle.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try BackupExporter(source).export(to: bundle)
        try source.close()
        let layout = try migrations.installV1(scratch)
        var options = StoreOptions()
        options.faults.throwDuringRecommendationRebuild = true
        options.putBackHooks = PutBackHooks(crashAfter: .databaseMovedAside)
        #expect(throws: StoreError.simulatedCrash("databaseMovedAside")) { _ = try LibraryStore.open(layout, options: options) }
        let restorer = BackupRestorer(layout: layout)
        let result = try restorer.commit(try restorer.prepare(bundle: bundle), confirmation: .replaceExistingLibrary, activeStore: nil)
        try result.store.close()
        let needed = try recoveryItems(layout).filter { !$0.hasPrefix("pre-restore-") }
        #expect(needed.count == 2, "\(needed)")
        // An unrelated older snapshot and failed copy, which the rule may remove.
        let stale = ["pre-migration-1-00000000.sqlite", "failed-00000000-0000-4000-8000-000000000000"]
        try Data("stale".utf8).write(to: layout.recoveryDirectory.appending(path: stale[0]))
        try FileManager.default.createDirectory(at: layout.recoveryDirectory.appending(path: stale[1]), withIntermediateDirectories: true)

        let intent = try #require(result.preRestoreCopy).appending(path: "migration-putback.json")
        #expect(chmod(intent.path, 0) == 0)
        let blocked = RecoveryRetention.prune(layout, keepSnapshot: "pre-migration-2-00000000.sqlite", keepFailed: nil)
        #expect(blocked.removed.isEmpty && !blocked.errors.isEmpty, "\(blocked)")
        #expect(chmod(intent.path, 0o600) == 0)

        let pruned = RecoveryRetention.prune(layout, keepSnapshot: "pre-migration-2-00000000.sqlite", keepFailed: nil)
        #expect(Set(pruned.removed) == Set(stale) && Set(pruned.kept) == Set(needed) && pruned.errors.isEmpty, "\(pruned)")
        #expect(Set(try recoveryItems(layout).filter { !$0.hasPrefix("pre-restore-") }) == Set(needed))
        evidence("prune with a pending intent in a pre-restore copy: kept \(pruned.kept), removed \(pruned.removed); with that intent unreadable: removed nothing (\(blocked.errors.first ?? ""))")
    }

    @Test("the review's probe: library files moved aside with no intent; the open refuses instead of creating an empty library",
          arguments: ["installation record", "recovery copies only"])
    func missingDatabaseIsNotReplaced(kind: String) throws {
        let scratch = try Scratch()
        let layout = scratch.layout()
        try CrashDrill.seed(layout, durability: .acknowledgedSaves)
        let store = try LibraryStore.open(layout)
        for n in 0..<3 { try store.saveCapture(CrashDrill.command(n)) }
        try store.close()
        // The state the old put-back left when it was killed after moving the library files aside.
        let failed = layout.recoveryDirectory.appending(path: "failed-probe", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: failed, withIntermediateDirectories: true)
        for url in [layout.databaseURL, layout.walURL, layout.shmURL] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.moveItem(at: url, to: failed.appending(path: url.lastPathComponent))
        }
        if kind == "recovery copies only" { try FileManager.default.removeItem(at: layout.installationURL) }
        #expect(throws: StoreError.libraryMissing(recoveryItems: ["failed-probe"])) { _ = try LibraryStore.open(layout) }
        #expect(!FileManager.default.fileExists(atPath: layout.databaseURL.path), "an empty library was created")
        // The data is where the recovery screen can find it.
        let queue = try RecoveryAccess.openReadOnly(failed.appending(path: "library.sqlite"))
        #expect(try queue.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM capture") } == 3)
        try queue.close()
        evidence("library.sqlite missing (\(kind)): open refused with libraryMissing; 3 captures readable in Recovery/failed-probe")
    }

    @Test("a new installation still gets a new library")
    func newInstallation() throws {
        let scratch = try Scratch()
        let store = try LibraryStore.open(scratch.layout())
        defer { try? store.close() }
        #expect(try store.schemaVersion == LibrarySchema.currentVersion)
        #expect(FileManager.default.fileExists(atPath: scratch.layout().installationURL.path))
    }

    @Test("a put-back intent that cannot be read (stand-in for before first unlock) or is invalid fails the open and changes nothing",
          arguments: ["unreadable", "not json", "traversal"])
    func badPutBackIntent(kind: String) throws {
        let scratch = try Scratch()
        let layout = try migrations.installV1(scratch)
        let before = try migrations.readOnly(layout)
        var options = StoreOptions()
        options.faults.throwDuringRecommendationRebuild = true
        options.putBackHooks = PutBackHooks(crashAfter: .databaseMovedAside)
        #expect(throws: StoreError.simulatedCrash("databaseMovedAside")) { _ = try LibraryStore.open(layout, options: options) }
        let intentURL = layout.migrationPutBackIntentURL
        let original = try Data(contentsOf: intentURL)
        switch kind {
        case "unreadable":
            #expect(chmod(intentURL.path, 0) == 0)
        case "not json":
            try Data("{ not json".utf8).write(to: intentURL)
        default:
            var json = try JSONSerialization.jsonObject(with: original) as! [String: Any]
            json["snapshot"] = "Recovery/../../elsewhere.sqlite"
            try JSONSerialization.data(withJSONObject: json).write(to: intentURL)
        }
        defer { _ = chmod(intentURL.path, 0o600) }
        // An abandoned file in Staging/: with an intent that cannot be acted on, even that stays.
        let abandoned = layout.stagingDirectory.appending(path: "\(EntityID.make()).tmp")
        try Data("abandoned".utf8).write(to: abandoned)
        let rootBefore = try treeFingerprint(layout.root, excluding: ["migration-putback.json"])
        #expect {
            _ = try LibraryStore.open(layout)
        } throws: { error in
            guard case StoreError.invalid(let why) = error else { return false }
            evidence("put-back intent \(kind): open refused: \(why)")
            return why.contains("migration put-back intent") && why.contains("nothing was changed")
        }
        #expect(try treeFingerprint(layout.root, excluding: ["migration-putback.json"]) == rootBefore, "a bad intent must not change any file")
        #expect(!FileManager.default.fileExists(atPath: layout.databaseURL.path), "an empty library was created")
        // Once the intent is readable and valid again, the next opens finish the put-back and migrate.
        #expect(chmod(intentURL.path, 0o600) == 0)
        try original.write(to: intentURL)
        try expectRecovered(layout, before: before, putBackPending: true, label: kind)
        #expect(!FileManager.default.fileExists(atPath: abandoned.path), "the abandoned staging file must go once the put-back can run")
    }

    @Test("a restore over a library whose put-back is pending replaces it; the pending intent moves with the old library")
    func restoreOverPendingPutBack() throws {
        let scratch = try Scratch()
        let (source, _) = try corpusLibrary(scratch, "Source")
        let bundle = scratch.dir("Exports/b.sylviabackup")
        try FileManager.default.createDirectory(at: bundle.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try BackupExporter(source).export(to: bundle)
        let sourceDump = try source.pool.read { try LibraryChecks.knowledgeDump($0) }
        try source.close()

        let layout = try migrations.installV1(scratch)
        var options = StoreOptions()
        options.faults.throwDuringRecommendationRebuild = true
        options.putBackHooks = PutBackHooks(crashAfter: .databaseMovedAside)
        #expect(throws: StoreError.simulatedCrash("databaseMovedAside")) { _ = try LibraryStore.open(layout, options: options) }

        // From the recovery screen the user restores a backup (no active store is open).
        let restorer = BackupRestorer(layout: layout)
        let result = try restorer.commit(try restorer.prepare(bundle: bundle), confirmation: .replaceExistingLibrary, activeStore: nil)
        #expect(try result.store.pool.read { try LibraryChecks.knowledgeDump($0) } == sourceDump)
        let preRestore = try #require(result.preRestoreCopy)
        #expect(FileManager.default.fileExists(atPath: preRestore.appending(path: "migration-putback.json").path))
        try result.store.close()
        // The restored library opens normally; its own Library/ has no intent.
        let reopened = try LibraryStore.open(layout)
        #expect(try reopened.pool.read { try LibraryChecks.knowledgeDump($0) } == sourceDump)
        try reopened.close()
        try expectNoPutBackLeftovers(layout)
    }
}
