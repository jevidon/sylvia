import Foundation
@testable import SylviaContainerLayout
import SylviaImportHandoff
import SylviaIntakeCore
import SylviaPack
import Testing

/// Stands in for a writer that is still copying a drop-area file: appends `bytes` to it, once.
final class AppendOnce: @unchecked Sendable {
    private let url: URL
    private let bytes: Int
    private let lock = NSLock()
    private var done = false
    init(_ url: URL, bytes: Int) {
        self.url = url
        self.bytes = bytes
    }
    func appendIfFirst() {
        let first: Bool = lock.withLock { defer { done = true }; return !done }
        guard first, let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(repeating: 0x5A, count: bytes))
    }
    var appended: Bool { lock.withLock { done } }
}

struct FakeContainer {
    let root: URL
    let layout: StorageLayout

    init() throws {
        root = try TestDirectory.make()   // removed when the test ends (TemporaryFiles.swift)
        layout = StorageLayout(documents: root.appendingPathComponent("Documents", isDirectory: true),
                               applicationSupport: root.appendingPathComponent("Library/Application Support/Sylvia", isDirectory: true),
                               appGroup: root.appendingPathComponent("AppGroup", isDirectory: true))
        try FileManager.default.createDirectory(at: layout.documents, withIntermediateDirectories: true)
        try layout.bootstrap()
    }

    func importer() throws -> DropAreaImporter {
        DropAreaImporter(layout: layout, journal: try IntakeJournal(url: layout.journal))
    }

    /// Writes a small valid pack (two text files and one stored audio-like file) and returns its bytes.
    func makePack(named name: String, seed: UInt64 = 1, audioBytes: UInt64 = 2 << 20) async throws -> Data {
        let src = root.appendingPathComponent("src-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let audio = src.appendingPathComponent("a.caf")
        try DeterministicBytes(seed: seed).writeFile(audio, length: audioBytes)
        let notes = src.appendingPathComponent("n.md")
        try Data("# Notes \(seed)\n".utf8).write(to: notes)
        let out = root.appendingPathComponent(name)
        try await PackWriter().write(sources: [
            PackSource(url: audio, path: "Book/part-01.caf", kind: .audio, mediaType: "audio/x-caf", groupID: "book", order: 1),
            PackSource(url: notes, path: "Book/notes.md", kind: .markdown, mediaType: "text/markdown"),
        ], groups: [.init(groupID: "book", kind: .audiobook, title: "Book")], to: out)
        let data = try Data(contentsOf: out)
        try FileManager.default.removeItem(at: out)
        return data
    }

    /// A real SQLite database in WAL mode at the layout's database path, left open so -wal and -shm exist.
    @discardableResult
    func makeDatabase() throws -> OpaquePointer {
        try SQLiteFixture.makeWALDatabase(at: layout.database)
    }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}

var goodInfo: [String: Any] { ["UIFileSharingEnabled": true, "LSSupportsOpeningDocumentsInPlace": false] }

@Suite("container layout (T42: private data never Finder-visible)", .removesTemporaryFiles)
struct ContainerLayoutTests {
    @Test("the layout puts every private class outside Documents and the Info.plist keys are checked")
    func layoutAudit() throws {
        let c = try FakeContainer()
        try c.makeDatabase()
        try Data("note".utf8).write(to: c.layout.notes.appendingPathComponent("n1.md"))
        try Data("clip".utf8).write(to: c.layout.retainedKnowledge.appendingPathComponent("clip.m4a"))
        #expect(LayoutAudit.audit(c.layout, infoDictionary: goodInfo).isEmpty)
        #expect(FileManager.default.fileExists(atPath: c.layout.database.path))

        #expect(!LayoutAudit.audit(c.layout, infoDictionary: ["UIFileSharingEnabled": true]).isEmpty, "the in-place key must be explicit")
        #expect(!LayoutAudit.audit(c.layout, infoDictionary: ["LSSupportsOpeningDocumentsInPlace": false]).isEmpty)
        let bad = StorageLayout(documents: c.layout.documents, applicationSupport: c.layout.documents.appendingPathComponent("Sylvia"), appGroup: nil)
        #expect(LayoutAudit.audit(bad, infoDictionary: goodInfo).count >= 4)
        try Data().write(to: c.layout.documents.appendingPathComponent("stray.sqlite-wal"))
        #expect(LayoutAudit.audit(c.layout, infoDictionary: goodInfo).count == 1)
    }

    @Test("staging and the handoff inbox are excluded from backup; knowledge and database are not")
    func backupClasses() throws {
        let c = try FakeContainer()
        func excluded(_ url: URL) throws -> Bool { try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup ?? false }
        #expect(try excluded(c.layout.staging))
        #expect(try excluded(try #require(c.layout.handoffInbox)))
        #expect(try !excluded(c.layout.databaseDirectory))
        #expect(try !excluded(c.layout.notes))
        #expect(try !excluded(c.layout.retainedKnowledge))
    }

    @Test("deleting everything in Documents (as Finder can) leaves the catalog untouched")
    func finderDeletion() async throws {
        let c = try FakeContainer()
        try c.makeDatabase()
        let before = try FileDigest.sha256(of: c.layout.database)
        try await c.makePack(named: "x").write(to: c.layout.documents.appendingPathComponent("x.sylviapack"))
        for name in try FileManager.default.contentsOfDirectory(atPath: c.layout.documents.path) {
            try FileManager.default.removeItem(at: c.layout.documents.appendingPathComponent(name))
        }
        #expect(try FileDigest.sha256(of: c.layout.database) == before)
    }
}

@Suite("drop-area import (Finder cable copy) and single-file routes (T08, T42)", .removesTemporaryFiles)
struct DropAreaImportTests {
    @Test("a valid bundle copied into Documents imports into private staging, then leaves the drop area")
    func importBundle() async throws {
        let c = try FakeContainer()
        try await c.makePack(named: "p").write(to: c.layout.documents.appendingPathComponent("Book.sylviapack"))
        let importer = try c.importer()
        #expect(importer.listDropArea().map(\.kind) == [.bundle])
        let job = try await importer.importDropAreaItem(named: "Book.sylviapack")
        #expect(job.state == .staged && job.route == .documentsBundle)
        let staged = c.layout.staging.appendingPathComponent(job.stagedDirectory)
        for item in job.items {
            #expect(try FileDigest.sha256(of: staged.appendingPathComponent(item.relativePath)).sha256 == item.sha256)
        }
        // Plan 16.4: cleaned up after a successful import, so no multi-GiB transport copy stays in Documents (where it
        // would also be backed up).
        #expect(!FileManager.default.fileExists(atPath: c.layout.documents.appendingPathComponent("Book.sylviapack").path))
        #expect(importer.listDropArea().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: c.layout.extracting.path).isEmpty)
        #expect(LayoutAudit.audit(c.layout, infoDictionary: goodInfo).isEmpty)
        // The same bundle copied again is a duplicate: needs_review, and its transport copy is removed too.
        try await c.makePack(named: "p").write(to: c.layout.documents.appendingPathComponent("Book.sylviapack"))
        #expect(try await importer.importDropAreaItem(named: "Book.sylviapack").state == .needsReview)
        #expect(importer.listDropArea().isEmpty)
    }

    @Test("a bundle replaced in the drop area while it was being imported is not removed")
    func replacedDuringImport() async throws {
        let c = try FakeContainer()
        let bundle = c.layout.documents.appendingPathComponent("Book.sylviapack")
        try await c.makePack(named: "p").write(to: bundle)
        let replacement = try await c.makePack(named: "q", seed: 9)
        let importer = DropAreaImporter(layout: c.layout, journal: try IntakeJournal(url: c.layout.journal), hook: { step in
            // As Finder copying a new file over the old one: a different file under the same name.
            if step == .moved {
                try FileManager.default.removeItem(at: bundle)
                try replacement.write(to: bundle)
            }
        })
        #expect(try await importer.importDropAreaItem(named: "Book.sylviapack").state == .staged)
        #expect(try Data(contentsOf: bundle) == replacement, "the new copy is kept for the user")
    }

    @Test("not enough space to extract: the shortfall is named, nothing is written, the bundle stays")
    func insufficientSpace() async throws {
        let c = try FakeContainer()
        let data = try await c.makePack(named: "p")
        try data.write(to: c.layout.documents.appendingPathComponent("Book.sylviapack"))
        let available: UInt64 = 1_000
        let importer = DropAreaImporter(layout: c.layout, journal: try IntakeJournal(url: c.layout.journal),
                                        reader: PackReader(availableCapacity: { _ in available }))
        do {
            _ = try await importer.importDropAreaItem(named: "Book.sylviapack")
            Issue.record("imported without space")
        } catch {
            guard case let .insufficientSpace(needed) = error else { Issue.record("wrong error \(error)"); return }
            let total = try await PackReader().validate(c.layout.documents.appendingPathComponent("Book.sylviapack")).manifest.totalSize
            #expect(needed == total + PackLimits().extractionSpaceMargin - available)
            #expect(error.description.contains("free up"), "\(error)")
            print("insufficient space: \(error)")
        }
        #expect(importer.journal.jobs.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: c.layout.extracting.path).isEmpty)
        #expect(FileManager.default.fileExists(atPath: c.layout.documents.appendingPathComponent("Book.sylviapack").path))
    }

    @Test("open-in of a .sylviapack goes through the bundle importer; the Inbox copy is removed after success and failure")
    func openInBundle() async throws {
        let c = try FakeContainer()
        let importer = try c.importer()
        let inbox = c.layout.documents.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let data = try await c.makePack(named: "p")

        let good = inbox.appendingPathComponent("Book.sylviapack")
        try data.write(to: good)
        let job = try await importer.importOpenedFile(at: good, route: .openIn)
        #expect(job.state == .staged && job.route == .openIn && job.items.count == 2)
        #expect(!FileManager.default.fileExists(atPath: good.path))

        let partial = inbox.appendingPathComponent("Partial.sylviapack")
        try data.prefix(data.count / 2).write(to: partial)
        await #expect(throws: DropAreaImporter.ImportError.self) { try await importer.importOpenedFile(at: partial, route: .openIn) }
        #expect(!FileManager.default.fileExists(atPath: partial.path), "a failed open-in leaves no Finder-visible copy")

        let script = inbox.appendingPathComponent("tool.sh")
        try Data("#!/bin/sh".utf8).write(to: script)
        await #expect(throws: DropAreaImporter.ImportError.unsupportedType) { try await importer.importOpenedFile(at: script, route: .openIn) }
        #expect(!FileManager.default.fileExists(atPath: script.path))
        #expect(importer.journal.jobs.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: c.layout.extracting.path).isEmpty)
    }

    @Test("an open-in copy left in Documents/Inbox by a crash is listed and can be imported or removed")
    func inboxLeftovers() async throws {
        let c = try FakeContainer()
        let importer = try c.importer()
        let inbox = c.layout.documents.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try DeterministicBytes(seed: 5).writeFile(inbox.appendingPathComponent("Left.epub"), length: 100_000)
        try DeterministicBytes(seed: 6).writeFile(inbox.appendingPathComponent("Other.pdf"), length: 1_000)
        #expect(importer.listDropArea().map(\.name) == ["Inbox/Left.epub", "Inbox/Other.pdf"])
        #expect(importer.listDropArea().map(\.kind) == [.file, .file])
        let job = try await importer.importDropAreaItem(named: "Inbox/Left.epub")
        #expect(job.state == .staged && job.route == .openIn)
        try importer.removeFromDropArea(named: "Inbox/Other.pdf")
        #expect(importer.listDropArea().isEmpty)
        await #expect(throws: DropAreaImporter.ImportError.notInDropArea) { try await importer.importDropAreaItem(named: "Inbox/../x") }
        await #expect(throws: DropAreaImporter.ImportError.notInDropArea) { try await importer.importDropAreaItem(named: "Inbox/") }
    }

    @Test("a single-file import is an APFS clone: identical bytes, private mode, the source untouched")
    func singleFileClone() throws {
        let c = try FakeContainer()
        let importer = try c.importer()
        let src = c.root.appendingPathComponent("Walden.epub")
        try DeterministicBytes(seed: 11).writeFile(src, length: 3 << 20)
        let before = try FileDigest.sha256(of: src)
        let identityBefore = try #require(DropAreaImporter.FileIdentity.of(src))
        let job = try importer.importSingleFile(at: src, route: .documentPicker)
        // The source is untouched (review R3-05): same device, inode, size and modification time, and the same bytes.
        #expect(DropAreaImporter.FileIdentity.of(src) == identityBefore)
        let staged = c.layout.staging.appendingPathComponent(job.stagedDirectory).appendingPathComponent(job.items[0].relativePath)
        #expect(job.items[0].sha256 == before.sha256 && job.items[0].byteCount == before.byteCount)
        #expect(try FileDigest.sha256(of: staged) == before)
        let mode = try FileManager.default.attributesOfItem(atPath: staged.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        #expect(try FileDigest.sha256(of: src) == before)
        // On APFS the clone shares the source's blocks: writing to the source afterwards does not change the staged copy.
        let handle = try FileHandle(forWritingTo: src)
        try handle.write(contentsOf: Data([0xFF]))
        try handle.close()
        #expect(try FileDigest.sha256(of: staged) == before)
    }

    @Test("a partial bundle in Documents is rejected and leaves no job and no extracted files",
          arguments: [0.25, 0.5, 0.75, 0.999])
    func partialBundle(fraction: Double) async throws {
        let c = try FakeContainer()
        let data = try await c.makePack(named: "p")
        try data.prefix(Int(Double(data.count) * fraction)).write(to: c.layout.documents.appendingPathComponent("Book.sylviapack"))
        let importer = try c.importer()
        await #expect(throws: DropAreaImporter.ImportError.self) { try await importer.importDropAreaItem(named: "Book.sylviapack") }
        #expect(importer.journal.jobs.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: c.layout.extracting.path).isEmpty)
        #expect(FileManager.default.fileExists(atPath: c.layout.documents.appendingPathComponent("Book.sylviapack").path),
                "a rejected bundle stays until the user removes it")
    }

    @Test("an uncoordinated writer still copying (as Finder may be): import is rejected until the copy completes")
    func uncoordinatedWriter() async throws {
        let c = try FakeContainer()
        let data = try await c.makePack(named: "p", audioBytes: 8 << 20)
        let dest = c.layout.documents.appendingPathComponent("Slow.sylviapack")
        // Writer: plain POSIX writes in 256 KiB chunks with pauses, no file coordination.
        let fd = open(dest.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        try #require(fd >= 0)
        let half = data.count / 2
        _ = data.prefix(half).withUnsafeBytes { write(fd, $0.baseAddress!, half) }
        let importer = try c.importer()
        var attempts: [String] = []
        do {
            _ = try await importer.importDropAreaItem(named: "Slow.sylviapack")
            attempts.append("accepted at half")
        } catch {
            attempts.append("rejected at half: \(error)")
        }
        _ = data.suffix(from: half).withUnsafeBytes { write(fd, $0.baseAddress!, data.count - half) }
        close(fd)
        let job = try await importer.importDropAreaItem(named: "Slow.sylviapack")
        attempts.append("accepted after completion")
        print("uncoordinated writer: \(attempts.joined(separator: "; "))")
        #expect(attempts.first?.hasPrefix("rejected") == true)
        #expect(job.state == .staged)
        #expect(importer.journal.jobs.count == 1)
    }

    @Test("a coordinated writer: the coordinated snapshot waits for the write to finish")
    func coordinatedWriter() async throws {
        let c = try FakeContainer()
        let data = try await c.makePack(named: "p")
        let dest = c.layout.documents.appendingPathComponent("Coordinated.sylviapack")
        let writerHolding = Flag()
        let writer = Thread {
            var error: NSError?
            NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: dest, options: [], error: &error) { url in
                let fd = open(url.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
                let half = data.count / 2
                _ = data.prefix(half).withUnsafeBytes { write(fd, $0.baseAddress!, half) }
                writerHolding.set()
                Thread.sleep(forTimeInterval: 1.0)
                _ = data.suffix(from: half).withUnsafeBytes { write(fd, $0.baseAddress!, data.count - half) }
                close(fd)
            }
        }
        writer.start()
        while !writerHolding.isSet {
            try await Task.sleep(for: .milliseconds(10))
        }
        let started = ContinuousClock.now
        let job = try await c.importer().importDropAreaItem(named: "Coordinated.sylviapack")
        let waited = ContinuousClock.now - started
        print("coordinated writer: import waited \(waited) for the coordinated write")
        #expect(job.state == .staged)
        #expect(waited > .milliseconds(500))
    }

    @Test("open-in, document picker and share extension: the same bytes are flagged as duplicates the same way")
    func duplicateParityAcrossRoutes() async throws {
        let c = try FakeContainer()
        let importer = try c.importer()
        let src = c.root.appendingPathComponent("Walden.epub")
        try DeterministicBytes(seed: 42).writeFile(src, length: 400_000)

        // Share extension route: handoff into the App Group inbox, then the app's scan.
        let inbox = try #require(c.layout.handoffInbox)
        let env = HandoffEnvironment(inbox: inbox, producerBundleIdentifier: "test", producerBuildVersion: "1")
        _ = try HandoffSession.run(environment: env, files: [(src, "org.idpf.epub-container")]).get()
        let scan = try InboxScanner(inbox: inbox, stagingRoot: c.layout.staging, journal: importer.journal).scan()
        #expect(scan.acceptedJobs.count == 1)

        // Open-in route: the system places a copy in Documents/Inbox.
        let openInDir = c.layout.documents.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: openInDir, withIntermediateDirectories: true)
        let openInCopy = openInDir.appendingPathComponent("Walden.epub")
        try FileManager.default.copyItem(at: src, to: openInCopy)
        let openIn = try await importer.importOpenedFile(at: openInCopy, route: .openIn)
        #expect(openIn.state == .needsReview)
        #expect(!FileManager.default.fileExists(atPath: openInCopy.path), "the system's Inbox copy is removed after import")

        // Document picker route: the original stays where it is, untouched (I-08; review R3-05): the same device, inode,
        // size and modification time afterwards, and the same bytes.
        let identityBefore = try #require(DropAreaImporter.FileIdentity.of(src))
        let digestBefore = try FileDigest.sha256(of: src)
        let picker = try importer.importSingleFile(at: src, route: .documentPicker)
        #expect(picker.state == .needsReview)
        #expect(DropAreaImporter.FileIdentity.of(src) == identityBefore, "imports copy; the source is never modified (I-08)")
        #expect(try FileDigest.sha256(of: src) == digestBefore)
        #expect(picker.items[0].sha256 == digestBefore.sha256 && picker.items[0].byteCount == digestBefore.byteCount)

        let jobs = importer.journal.jobs
        #expect(jobs.count == 3)
        #expect(Set(jobs.map(\.items[0].sha256)).count == 1)
        #expect(jobs.filter { $0.state == .staged }.count == 1)
    }

    @Test("process death after each commit step of a bundle import, then relaunch: exactly one staged job, bytes intact",
          arguments: [AcceptStep.intentRecorded, .moved, .finished])
    func crashDuringBundleCommit(step: AcceptStep) async throws {
        let c = try FakeContainer()
        try await c.makePack(named: "p").write(to: c.layout.documents.appendingPathComponent("Book.sylviapack"))
        let dying = DropAreaImporter(layout: c.layout, journal: try IntakeJournal(url: c.layout.journal), hook: { reached in
            if reached == step { throw SimulatedProcessDeath(step: .renameManifest) }
        })
        await #expect(throws: DropAreaImporter.ImportError.simulatedProcessDeath) {
            try await dying.importDropAreaItem(named: "Book.sylviapack")
        }
        // Relaunch: a new journal read from disk, then the launch-time recovery.
        let relaunched = try c.importer()
        let report = relaunched.recoverInterruptedImports()
        let jobs = relaunched.journal.jobs
        try #require(jobs.count == 1, "after a crash at \(step.rawValue)")
        #expect(jobs[0].state == .staged)
        #expect(report.failed.isEmpty)
        #expect(report.finished == (step == .finished ? [] : [jobs[0].jobID]))
        let staged = c.layout.staging.appendingPathComponent(jobs[0].stagedDirectory)
        for item in jobs[0].items {
            #expect(try FileDigest.sha256(of: staged.appendingPathComponent(item.relativePath)).sha256 == item.sha256)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: c.layout.extracting.path).isEmpty)
        // A second recovery is a no-op.
        #expect(relaunched.recoverInterruptedImports() == DropAreaImporter.RecoveryReport())
    }

    @Test("process death mid-copy (no commit intent yet): relaunch removes the partial copy and records no job")
    func crashBeforeIntent() throws {
        let c = try FakeContainer()
        let orphan = c.layout.extracting.appendingPathComponent(UUID().uuidString + "/items", isDirectory: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try Data(count: 4096).write(to: orphan.appendingPathComponent("0.epub"))
        try Data(count: 10).write(to: c.layout.extracting.appendingPathComponent(UUID().uuidString + ".sylviapack"))
        let importer = try c.importer()
        let report = importer.recoverInterruptedImports()
        #expect(report.removedExtractions.count == 2)
        #expect(importer.journal.jobs.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: c.layout.extracting.path).isEmpty)
    }

    @Test("an intent whose bytes vanished is reported as failed_final, never as staged")
    func intentWithoutBytes() throws {
        let c = try FakeContainer()
        let importer = try c.importer()
        let job = IntakeJournal.Job(jobID: UUID(), route: .openIn, state: .accepting, handoffID: nil,
                                    stagedDirectory: "Staged/\(UUID().uuidString)",
                                    items: [.init(relativePath: "items/0.epub", byteCount: 1, sha256: String(repeating: "0", count: 64),
                                                  contentType: "org.idpf.epub-container", originalFilename: "x.epub")],
                                    duplicateOf: nil, createdAt: Date())
        try importer.journal.upsert(job)
        let report = importer.recoverInterruptedImports()
        #expect(report.failed == [job.jobID])
        #expect(importer.journal.job(id: job.jobID)?.state == .failedFinal)
    }

    /// G0.3 review R2-05: plan 8.5 allows a raw file copied with Finder (user-initiated, coordinated). It used to be
    /// sent to the bundle importer and refused as "truncated_or_not_a_pack".
    @Test("a raw EPUB copied into Documents with Finder imports through the single-file importer and stays until removed")
    func rawFinderFile() async throws {
        let c = try FakeContainer()
        let importer = try c.importer()
        let raw = c.layout.documents.appendingPathComponent("Walden.epub")
        try DeterministicBytes(seed: 77).writeFile(raw, length: 750_000)
        try DeterministicBytes(seed: 78).writeFile(c.layout.documents.appendingPathComponent("photo.jpg"), length: 1_000)
        #expect(importer.listDropArea().map(\.name) == ["Walden.epub", "photo.jpg"])
        #expect(importer.listDropArea().map(\.kind) == [.file, .unsupported])

        let job = try await importer.importDropAreaItem(named: "Walden.epub")
        #expect(job.route == .documentsFile && job.state == .staged)
        #expect(job.items.count == 1 && job.items[0].byteCount == 750_000 && job.items[0].contentType == "org.idpf.epub-container")
        let staged = c.layout.staging.appendingPathComponent(job.stagedDirectory).appendingPathComponent(job.items[0].relativePath)
        #expect(try Data(contentsOf: staged) == Data(contentsOf: raw))
        #expect(FileManager.default.fileExists(atPath: raw.path),
                "a raw Finder file is never removed automatically: nothing proves Finder had finished")
        let again = try await importer.importDropAreaItem(named: "Walden.epub")
        #expect(again.state == .needsReview, "the same bytes again are a duplicate, as on every other route")
        await #expect(throws: DropAreaImporter.ImportError.unsupportedType) { try await importer.importDropAreaItem(named: "photo.jpg") }
        try importer.removeFromDropArea(named: "Walden.epub")
        #expect(importer.listDropArea().map(\.name) == ["photo.jpg"])
        #expect(importer.journal.jobs.count == 2)
        print("raw Finder file: imported as \(job.route.rawValue) \(job.state.rawValue), again \(again.state.rawValue); the Documents copy stayed until removed")
    }

    @Test("a raw file still being written (as Finder may be) is staged as the partial bytes: without a manifest nothing proves completeness")
    func rawFinderFileStillCopying() async throws {
        let c = try FakeContainer()
        let importer = try c.importer()
        let dest = c.layout.documents.appendingPathComponent("Long.m4b")
        let full = c.root.appendingPathComponent("full.m4b")
        try DeterministicBytes(seed: 79).writeFile(full, length: 4 << 20)
        let data = try Data(contentsOf: full)
        let fd = open(dest.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        try #require(fd >= 0)
        let half = data.count / 2
        _ = data.prefix(half).withUnsafeBytes { write(fd, $0.baseAddress!, half) }
        let partial = try await importer.importDropAreaItem(named: "Long.m4b")
        _ = data.suffix(from: half).withUnsafeBytes { write(fd, $0.baseAddress!, data.count - half) }
        close(fd)
        #expect(try Data(contentsOf: dest) == data, "the writer's copy is intact: the import did not remove or change it")
        let complete = try await importer.importDropAreaItem(named: "Long.m4b")
        print("raw file still copying: import at half staged \(partial.items[0].byteCount) of \(data.count) bytes (\(partial.state.rawValue)); after the copy finished \(complete.items[0].byteCount) bytes (\(complete.state.rawValue))")
        // This is the limitation plan 8.5 states, recorded rather than hidden (report F15): the partial job is staged,
        // not trusted, and only the type's later validation can catch it; a bundle in the same situation is rejected
        // (uncoordinatedWriter above).
        #expect(partial.state == .staged && partial.items[0].byteCount == UInt64(half))
        #expect(complete.state == .staged && complete.items[0].byteCount == UInt64(data.count))
    }

    /// A raw file Finder is still writing changes while it is imported. The hook stands in for that writer: right after
    /// the snapshot is hashed (the window in which a live copy keeps writing) it appends to the file once.
    @Test("a raw file that changes while it is imported (Finder still copying) is refused and nothing is staged; once it stops changing it imports")
    func rawFinderFileChangingDuringImport() async throws {
        let c = try FakeContainer()
        let raw = c.layout.documents.appendingPathComponent("Copying.mp3")
        try DeterministicBytes(seed: 80).writeFile(raw, length: 2 << 20)
        let writer = AppendOnce(raw, bytes: 4096)
        let importer = DropAreaImporter(layout: c.layout, journal: try IntakeJournal(url: c.layout.journal), hook: { step in
            if step == .verified { writer.appendIfFirst() }
        })
        await #expect(throws: DropAreaImporter.ImportError.stillBeingWritten) {
            try await importer.importDropAreaItem(named: "Copying.mp3")
        }
        #expect(writer.appended)
        #expect(importer.journal.jobs.isEmpty, "no commit intent for a file that was still changing")
        #expect(try FileManager.default.contentsOfDirectory(atPath: c.layout.extracting.path).isEmpty)
        #expect(FileManager.default.fileExists(atPath: raw.path), "the file stays for the next attempt")
        // The writer has stopped: the next import stages the whole file.
        let job = try await importer.importDropAreaItem(named: "Copying.mp3")
        #expect(job.route == .documentsFile && job.state == .staged && job.items[0].byteCount == (2 << 20) + 4096)
        print("raw file changing during its import: refused (stillBeingWritten); after it stopped changing: staged \(job.items[0].byteCount) bytes")
    }

    @Test("unsupported single files and names outside the drop area are refused")
    func refusals() async throws {
        let c = try FakeContainer()
        let importer = try c.importer()
        let exe = c.root.appendingPathComponent("tool.sh")
        try Data("#!/bin/sh".utf8).write(to: exe)
        #expect(throws: DropAreaImporter.ImportError.unsupportedType) { try importer.importSingleFile(at: exe, route: .openIn) }
        await #expect(throws: DropAreaImporter.ImportError.notInDropArea) { try await importer.importDropAreaItem(named: "../x.sylviapack") }
        await #expect(throws: DropAreaImporter.ImportError.notInDropArea) { try await importer.importDropAreaItem(named: "missing.sylviapack") }
    }
}
