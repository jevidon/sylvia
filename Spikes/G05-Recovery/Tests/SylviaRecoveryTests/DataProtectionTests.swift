import Foundation
import GRDB
import Testing
@testable import SylviaRecovery

/// What the host and simulator can show about file protection (plan 18.1, T50). Neither enforces
/// locked-device behaviour; that is the device checklist. The host (macOS) reports protection
/// classes faithfully; the iOS Simulator reports none for directories and class C for every file,
/// and these tests assert exactly that there. Class C is the default class on both platforms, so
/// only a run with a non-default class shows that the code sets the class.
@Suite("Data protection classes (plan 18.1, T50 partial)")
struct DataProtectionTests {
    let expected = FileProtectionType.completeUntilFirstUserAuthentication
    static let unreported = "none reported"

    func protection(_ url: URL) throws -> String {
        try FileProtector.library.protectionClass(of: url)?.rawValue ?? Self.unreported
    }

    /// Host and device: the class must read back. Simulator: the readback is not faithful
    /// (directories report none, files report class C), so only those two values are accepted and
    /// the simulator result is not evidence of protection.
    func expectClass(_ url: URL, _ wanted: FileProtectionType, _ label: String) throws {
        let value = try protection(url)
        if FileProtector.platformReportsProtection {
            #expect(value == wanted.rawValue, "\(label): \(value)")
        } else {
            let isDirectory = (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
            let simulatorDefault = isDirectory ? Self.unreported : FileProtectionType.completeUntilFirstUserAuthentication.rawValue
            #expect(value == simulatorDefault, "\(label): simulator reported \(value)")
        }
    }

    /// One protection readback, taken while the item exists.
    struct Reading {
        let item: String
        let value: String
        let isDirectory: Bool
    }

    /// Runs every code path that creates a persistent file with `protector` and reads back, at the
    /// time each exists, every file and directory that must carry its class: the library tree,
    /// database, WAL and SHM, installation record, imported media, excerpt and cover blobs, every
    /// bundle file, the restored library and its blobs, the pre-restore copy, a pre-migration
    /// snapshot, a snapshot put back after a failed migration and the failed files kept beside it.
    func protectedItems(_ scratch: Scratch, protector: FileProtector) throws -> [Reading] {
        var readings: [Reading] = []
        func read(_ urls: [URL]) throws {
            for url in urls {
                let isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
                readings.append(Reading(item: url.path.replacingOccurrences(of: scratch.url.path, with: ""),
                                        value: try protection(url), isDirectory: isDirectory))
            }
        }
        var options = StoreOptions()
        options.protector = protector
        let (store, corpus) = try corpusLibrary(scratch, options: options)
        let layout = store.layout
        // WAL and SHM exist while the pool is open.
        #expect(FileManager.default.fileExists(atPath: layout.walURL.path) && FileManager.default.fileExists(atPath: layout.shmURL.path))
        try read(layout.managedDirectories + [layout.databaseURL, layout.walURL, layout.shmURL, layout.installationURL,
                                               BlobStore(store).url(sha256: corpus.excerptSHA256, fileExtension: "mp3")])
        try read(corpus.covers.values.map { CoverStore.url(layout, sha256: $0.sha256, fileExtension: $0.fileExtension) })
        for key in ["med-epub", "med-audio-1"] {
            let mediaDir = layout.mediaDirectory.appending(path: corpus.assets[key]!, directoryHint: .isDirectory)
            try read([mediaDir] + FileManager.default.contentsOfDirectory(at: mediaDir, includingPropertiesForKeys: nil))
        }

        let bundle = scratch.dir("Exports/p.sylviabackup")
        try protector.ensureDirectory(bundle.deletingLastPathComponent())
        _ = try BackupExporter(store).export(to: bundle)
        try read([bundle] + FileManager.default.subpathsOfDirectory(atPath: bundle.path).map { bundle.appending(path: $0) })

        // Restore over this library: restored files, its blobs, and the pre-restore copy.
        let restorer = BackupRestorer(layout: layout, options: options)
        let restored = try restorer.commit(try restorer.prepare(bundle: bundle), confirmation: .replaceExistingLibrary, activeStore: store)
        try read([layout.libraryDirectory, layout.databaseURL, layout.walURL, layout.shmURL,
                  BlobStore(restored.store).url(sha256: corpus.excerptSHA256, fileExtension: "mp3")])
        try read(corpus.covers.values.map { CoverStore.url(layout, sha256: $0.sha256, fileExtension: $0.fileExtension) })
        let preRestore = try #require(restored.preRestoreCopy)
        try read([preRestore.deletingLastPathComponent(), preRestore, preRestore.appending(path: "library.sqlite")])
        try restored.store.close()

        // Migration safety copies: a pre-migration snapshot, then a failed migration that puts it back.
        let migrating = scratch.layout("Migrating")
        var v1 = options
        v1.migrateUpTo = "v1-initial"
        try LibraryStore.open(migrating, options: v1).close()
        var failing = options
        failing.faults.throwDuringRecommendationRebuild = true
        #expect(throws: StoreError.self) { _ = try LibraryStore.open(migrating, options: failing) }
        let recovery = try FileManager.default.contentsOfDirectory(at: migrating.recoveryDirectory, includingPropertiesForKeys: nil)
        #expect(recovery.contains { $0.lastPathComponent.hasPrefix("pre-migration-") } && recovery.contains { $0.lastPathComponent.hasPrefix("failed-") })
        for item in recovery {
            try read([item])
            if try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                try read(FileManager.default.contentsOfDirectory(at: item, includingPropertiesForKeys: nil))
            }
        }
        try read([migrating.databaseURL])   // the snapshot put back
        return readings
    }

    /// The chosen class (C) everywhere, including the simulator (where the readback is not evidence).
    /// C is also the platform default for new files on macOS and for app files on iOS, so this run
    /// alone cannot show that the code applied anything; the non-default run below can.
    @Test("database, WAL, SHM, directories, blobs, covers, media, snapshots, bundles and restored files carry the chosen class C")
    func everyFileProtected() throws {
        let scratch = try Scratch()
        let readings = try protectedItems(scratch, protector: .library)
        for reading in readings {
            if FileProtector.platformReportsProtection {
                #expect(reading.value == expected.rawValue, "\(reading.item): \(reading.value)")
            } else {
                let simulatorDefault = reading.isDirectory ? Self.unreported : expected.rawValue
                #expect(reading.value == simulatorDefault, "\(reading.item): simulator reported \(reading.value)")
            }
        }
        let seen = Dictionary(grouping: readings, by: \.value).mapValues(\.count)
        evidence("class C (chosen; also the platform default) read back on \(readings.count) files and directories: \(seen)")
    }

    /// Whether class A and B keys are available to this process right now. Always true in a test run
    /// on a device or the simulator (the runner needs the device unlocked). On the macOS host it is
    /// false while the screen is locked: class-A files cannot be created and closed class-B files
    /// cannot be reopened (observed: `lockedHostEnforcement`).
    static var classKeysAvailable: Bool {
        #if os(macOS)
        let directory = FileManager.default.temporaryDirectory.appending(path: "g05-keys-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appending(path: "a.bin")
            try Data("x".utf8).write(to: file, options: .completeFileProtection)
            return try Data(contentsOf: file) == Data("x".utf8)
        } catch {
            return false
        }
        #else
        return true
        #endif
    }

    /// The discriminating run: the same flow with class B, which is not the platform default. Every
    /// item must come out class B, so nothing relied on the default or kept a source file's class.
    /// Class A is not usable for the library (see `inheritance`: SQLite's SHM file is not class A),
    /// and macOS does not support class D (a class-D request reads back as C). Not run in the
    /// simulator, whose readback reports class C for every file, or on a host whose screen is locked,
    /// where closed class-B files cannot be reopened.
    @Test("with non-default class B supplied in StoreOptions, every file and directory carries class B",
          .enabled(if: FileProtector.platformReportsProtection, "the iOS Simulator reports class C for every file whatever was requested, so a non-default class cannot be read back there"),
          .enabled(if: classKeysAvailable, "class A/B keys are unavailable (host screen locked): closed class-B files cannot be reopened, so the flow cannot run with class B now; see lockedHostEnforcement"))
    func everyFileProtectedNonDefault() throws {
        let scratch = try Scratch()
        let wanted = FileProtectionType.completeUnlessOpen
        let readings = try protectedItems(scratch, protector: FileProtector(protection: wanted))
        for reading in readings {
            #expect(reading.value == wanted.rawValue, "\(reading.item): \(reading.value)")
        }
        let seen = Dictionary(grouping: readings, by: \.value).mapValues(\.count)
        evidence("class B (non-default) requested: read back on \(readings.count) files and directories: \(seen)")
    }

    #if os(macOS)
    /// Host only, and only while the screen is locked (after a login, so after first unlock): the host
    /// analogue of T50 step 3. The chosen class C keeps working, and classes A and B are enforced, so
    /// a class read back as B or A is a real class, not a label. Says nothing about an iPhone.
    @Test("host screen locked: the class-C library keeps saving; class A cannot be created and closed class-B files cannot be reopened",
          .enabled(if: !classKeysAvailable, "the host screen is unlocked; this observation needs a locked screen"))
    func lockedHostEnforcement() throws {
        let scratch = try Scratch()
        let store = try LibraryStore.open(scratch.layout())
        try store.pool.write { db in
            try store.insertJournaled(db, "work", id: CrashDrill.seedWorkID, [
                "id": CrashDrill.seedWorkID, "title": "Locked", "sort_title": "locked", "description": nil, "language_tag": "en",
                "metadata_revision": 1, "created_at_ms": 0, "updated_at_ms": 0, "deleted_at_ms": nil,
            ])
        }
        for n in 0..<5 { try store.saveCapture(CrashDrill.command(n)) }
        try store.close()
        let reopened = try LibraryStore.open(scratch.layout())
        let saved = try reopened.pool.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM capture") ?? -1 }
        try reopened.close()
        #expect(saved == 5)

        let classA = scratch.dir("ClassA")
        try FileManager.default.createDirectory(at: classA, withIntermediateDirectories: true)
        var classACreate = "created"
        do { try Data("x".utf8).write(to: classA.appending(path: "a.bin"), options: .completeFileProtection) } catch {
            classACreate = "refused (\((error as NSError).localizedDescription))"
        }
        #expect(classACreate != "created")
        let classB = scratch.dir("ClassB")
        try FileProtector(protection: .completeUnlessOpen).ensureDirectory(classB)
        let fileB = classB.appending(path: "b.bin")
        try Data("x".utf8).write(to: fileB)
        let reportedB = try protection(fileB)
        let fd = open(fileB.path, O_RDONLY)
        let reopenB = fd >= 0 ? "reopened" : "refused (errno \(errno))"
        if fd >= 0 { close(fd) }
        #expect(reportedB == FileProtectionType.completeUnlessOpen.rawValue)
        #expect(fd < 0)
        evidence("host screen locked: class-C library saved and reopened \(saved) captures; class-A file \(classACreate); class-B file created (\(reportedB)) then \(reopenB)")
    }
    #endif

    @Test("SQLite-created WAL and SHM inherit the directory's class (class-B and class-A control directories)",
          .enabled(if: classKeysAvailable, "class A/B keys are unavailable (host screen locked), so SQLite cannot open files in class-A or class-B directories now"))
    func inheritance() throws {
        let scratch = try Scratch()
        // Control: a directory with a different class (B) than Sylvia's (C), so inheritance is visible.
        let directory = scratch.dir("ClassB")
        try FileProtector(protection: .completeUnlessOpen).ensureDirectory(directory)
        let pool = try DatabasePool(path: directory.appending(path: "probe.sqlite").path)
        try pool.write { try $0.execute(sql: "CREATE TABLE t(x INTEGER) STRICT; INSERT INTO t VALUES (1)") }
        for name in ["probe.sqlite", "probe.sqlite-wal", "probe.sqlite-shm"] {
            try expectClass(directory.appending(path: name), .completeUnlessOpen, "\(name) in a class-B directory")
        }
        let observed = try ["probe.sqlite", "probe.sqlite-wal", "probe.sqlite-shm"].map { "\($0)=\(try protection(directory.appending(path: $0)))" }
        try pool.close()
        evidence("files SQLite created in a class-B directory: \(observed.joined(separator: " "))")
        // Observation only: the same in a class-A directory. Class A is not Sylvia's class.
        let classA = scratch.dir("ClassA")
        try FileProtector(protection: .complete).ensureDirectory(classA)
        let poolA = try DatabasePool(path: classA.appending(path: "probe.sqlite").path)
        try poolA.write { try $0.execute(sql: "CREATE TABLE t(x INTEGER) STRICT; INSERT INTO t VALUES (1)") }
        let observedA = try ["probe.sqlite", "probe.sqlite-wal", "probe.sqlite-shm"].map { "\($0)=\(try protection(classA.appending(path: $0)))" }
        try poolA.close()
        evidence("files SQLite created in a class-A directory: \(observedA.joined(separator: " "))")
    }

    @Test("the library records the class SQLite's files had before Sylvia set it explicitly")
    func libraryFilesBeforeExplicitSet() throws {
        let scratch = try Scratch()
        let store = try LibraryStore.open(scratch.layout())
        defer { try? store.close() }
        let before = store.openReport.protectionBeforeExplicitSet
        evidence("library files before explicit set: \(before.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
        #expect(before.count == 3)
        // Host: inherited from Library/ (class C, also the default). Simulator: its constant file default (also C).
        #expect(before.values.allSatisfy { $0 == expected.rawValue })
    }

    @Test("a file with the wrong class is detected, never silently accepted",
          .enabled(if: FileProtector.platformReportsProtection, "the iOS Simulator protection readback is not faithful (files report class C in any directory), so no mismatch can be produced there"))
    func mismatchDetected() throws {
        let scratch = try Scratch()
        let plain = scratch.url.appending(path: "plain.bin")
        try Data("x".utf8).write(to: plain, options: .noFileProtection)
        evidence("file written with .noFileProtection into the test's temporary directory reports: \(try protection(plain))")
        // A file created in a class-B directory has class B, which differs from Sylvia's class C.
        let directory = scratch.dir("ClassB")
        try FileProtector(protection: .completeUnlessOpen).ensureDirectory(directory)
        let url = directory.appending(path: "weak.bin")
        try Data("x".utf8).write(to: url)
        #expect(try protection(url) == FileProtectionType.completeUnlessOpen.rawValue)
        #expect(throws: ProtectionError.self) { try FileProtector.library.verify(url) }
        // Correcting it either works (and is verified) or fails loudly; it is never left as is.
        do {
            try FileProtector.library.protect(url)
            #expect(try protection(url) == expected.rawValue)
            evidence("changing an existing file's class with setAttributes: applied and verified")
        } catch let error as ProtectionError {
            evidence("changing an existing file's class with setAttributes: refused (\(error)); the class is fixed at creation here")
        }
    }

    @Test("staging, recovery and restore work are excluded from device backup; the library is not")
    func backupExclusion() throws {
        let scratch = try Scratch()
        let store = try LibraryStore.open(scratch.layout())
        defer { try? store.close() }
        func excluded(_ url: URL) throws -> Bool { try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup ?? false }
        #expect(try !excluded(store.layout.libraryDirectory))
        #expect(try !excluded(store.layout.databaseURL))
        for url in [store.layout.stagingDirectory, store.layout.recoveryDirectory, store.layout.restoreWorkDirectory] {
            #expect(try excluded(url), "\(url.lastPathComponent)")
        }
    }
}
