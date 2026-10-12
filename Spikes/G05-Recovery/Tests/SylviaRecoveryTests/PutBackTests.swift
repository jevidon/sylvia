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

    @Test("an I/O error (full disk) during the put-back fails the open with the intent kept; the next open finishes it",
          arguments: [PutBackStep.staged, .databaseMovedAside, .snapshotMovedIn])
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
