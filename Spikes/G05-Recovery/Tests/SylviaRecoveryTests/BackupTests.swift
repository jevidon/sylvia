import Foundation
import GRDB
import Testing
@testable import SylviaRecovery
import SylviaSQLiteShim

@Suite("Backup export (plan 17.3, 17.4, T35, T47)")
struct BackupExportTests {
    @Test("export: manifest, consistent snapshot, portable JSON and Markdown, verified digests, no WAL files")
    func export() throws {
        let scratch = try Scratch()
        let (store, corpus) = try corpusLibrary(scratch)
        defer { try? store.close() }
        let bundle = scratch.dir("Exports/a.sylviabackup")
        try FileManager.default.createDirectory(at: bundle.deletingLastPathComponent(), withIntermediateDirectories: true)
        let result = try BackupExporter(store).export(to: bundle)
        let m = result.manifest
        #expect(m.format == "sylviabackup" && m.schema_version == 1 && m.encryption == "none")
        #expect(m.library.schema_version == 2 && m.library.migrations == LibrarySchema.migrations.map(\.identifier))
        #expect(m.originating_device_id == store.deviceID)
        #expect(!m.complete && m.excluded_media.count == corpus.assets.count)
        #expect(m.excluded_classes.map(\.class).contains("original_media") && m.excluded_classes.map(\.class).contains("secrets"))
        #expect(m.files.contains { $0.path == "blobs/excerpts/\(corpus.excerptSHA256).mp3" })
        #expect(m.counts["capture"] == 5 && m.counts["note_revision"] == 9)
        let files = try FileManager.default.subpathsOfDirectory(atPath: bundle.path)
        #expect(!files.contains { $0.hasSuffix("-wal") || $0.hasSuffix("-shm") || $0.hasSuffix("-journal") || $0.contains("partial") })
        #expect(try BackupValidator.validate(bundle).manifestSHA256 == result.manifestSHA256)
        let json = try Data(contentsOf: bundle.appending(path: "export/library.json"))
        let live = try store.pool.read { try LibraryChecks.knowledgeDump($0) }
        #expect(try PortableExport.canonicalDump(fromJSON: json) == live)
        // The export is recorded, and leases are released.
        try store.pool.read { (db: Database) throws in
            #expect(try String.fetchOne(db, sql: "SELECT manifest_sha256 FROM export_record") == result.manifestSHA256)
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM retention_lease") == 0)
        }
        #expect(throws: BackupError.destinationExists("a.sylviabackup")) { _ = try BackupExporter(store).export(to: bundle) }
        evidence("export: \(m.files.count) files, counts \(m.counts.values.reduce(0, +)) rows, manifest sha256 \(result.manifestSHA256)")
    }

    @Test("Markdown holds every conversation message: work-linked, capture-linked only, and linked to neither")
    func markdownConversations() throws {
        let scratch = try Scratch()
        let (store, corpus) = try corpusLibrary(scratch)
        defer { try? store.close() }
        // The review's probe: the corpus conversation keeps only its capture association.
        try store.pool.write { (db: Database) throws in
            try db.execute(sql: "UPDATE conversation SET work_id = NULL WHERE id = ?", arguments: [corpus.conversationID])
            try LibraryStore.journal(db, "conversation", corpus.conversationID, "update", at: store.clock.nowMillis())
            let now = store.clock.nowMillis()
            let loose = EntityID.make()
            try store.insertJournaled(db, "conversation", id: loose, [
                "id": loose, "work_id": nil, "capture_id": nil, "created_at_ms": now, "updated_at_ms": now,
            ])
            for (ordinal, role, content) in [(0, "user", "A question asked outside any book?"),
                                             (1, "assistant", "An answer kept with no work attached.")] {
                let messageID = EntityID.make()
                try store.insertJournaled(db, "message", id: messageID, [
                    "id": messageID, "conversation_id": loose, "ordinal": ordinal, "role": role, "content": content,
                    "state": "complete", "provider_json": nil, "request_id": nil, "context_pack_id": nil, "created_at_ms": now,
                ])
            }
        }
        let bundle = scratch.dir("Exports/m.sylviabackup")
        try FileManager.default.createDirectory(at: bundle.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try BackupExporter(store).export(to: bundle)
        let directory = bundle.appending(path: "export/markdown")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        var files: [String: String] = [:]
        for name in names { files[name] = try String(contentsOf: directory.appending(path: name), encoding: .utf8) }
        let messages = try store.pool.read { (db: Database) throws in
            try Row.fetchAll(db, sql: "SELECT conversation_id, content FROM message ORDER BY conversation_id, ordinal")
                .map { ($0["conversation_id"] as String, $0["content"] as String) }
        }
        #expect(messages.count == 5)
        let all = files.values.joined()
        let missing = messages.filter { !all.contains($0.1) }
        #expect(missing.isEmpty, "messages missing from Markdown: \(missing)")
        // The capture-linked conversation is in its capture's work file; the loose one in its own file.
        let meditations = try #require(files.first { $0.key.hasPrefix("meditations-") }?.value)
        #expect(messages.filter { $0.0 == corpus.conversationID }.allSatisfy { meditations.contains($0.1) })
        let loose = try #require(files[PortableExport.unassociatedConversationsFile])
        #expect(loose.contains("A question asked outside any book?") && loose.contains("An answer kept with no work attached."))
        evidence("Markdown conversations: \(messages.count) messages, \(missing.count) missing; files \(names)")
    }

    @Test("T47: export while another task keeps writing gets one consistent snapshot boundary")
    func exportDuringEdits() async throws {
        let scratch = try Scratch()
        let layout = scratch.layout()
        try CrashDrill.seed(layout, durability: .acknowledgedSaves)
        let (store, _) = try corpusLibrary(scratch)
        defer { try? store.close() }
        let noteID = try store.addNote(workID: corpusWork(store), body: "revision 1")

        let writer = Task.detached { () -> Int in
            var n = 0
            var revision = 1
            while !Task.isCancelled && n < 5000 {
                try store.saveCapture(CrashDrill.command(n))
                revision = try store.reviseNote(noteID, expectedRevision: revision, body: "revision \(revision + 1)")
                n += 1
            }
            return n
        }
        try await Task.sleep(for: .milliseconds(50))
        var bundles: [URL] = []
        var concurrentWrites: [Int64] = []
        for i in 0..<4 {
            let bundle = scratch.dir("Exports/during-\(i).sylviabackup")
            try FileManager.default.createDirectory(at: bundle.deletingLastPathComponent(), withIntermediateDirectories: true)
            let seqBefore = try await store.pool.read { try Int64.fetchOne($0, sql: "SELECT max(seq) FROM change_journal") ?? 0 }
            _ = try BackupExporter(store).export(to: bundle)
            let seqAfter = try await store.pool.read { try Int64.fetchOne($0, sql: "SELECT max(seq) FROM change_journal") ?? 0 }
            concurrentWrites.append(seqAfter - seqBefore)
            bundles.append(bundle)
        }
        writer.cancel()
        let written = try await writer.value
        #expect(written > 0)
        var boundaries: [Int64] = []
        for bundle in bundles {
            let manifest = try BackupValidator.validate(bundle).manifest
            let queue = try RecoveryAccess.openReadOnly(bundle.appending(path: "database/library.sqlite"))
            try await queue.read { (db: Database) throws in
                #expect(try LibraryChecks.integrity(db) == ["ok"])
                #expect(try LibraryChecks.foreignKeyViolations(db).isEmpty)
                // No transaction is split: every capture is complete, the note's pointer matches its
                // newest revision, and nothing is newer than the recorded journal boundary.
                #expect(try CrashDrill.verify(db, acknowledged: [], checkContentOf: []).isEmpty)
                let note = try Row.fetchOne(db, sql: "SELECT current_revision, (SELECT max(revision) FROM note_revision WHERE note_id = ?) AS top FROM note WHERE id = ?",
                                            arguments: [noteID, noteID])!
                #expect(note["current_revision"] as Int == note["top"] as Int)
                #expect(try Int64.fetchOne(db, sql: "SELECT max(seq) FROM change_journal") == manifest.snapshot.change_journal_seq)
                #expect(try LibraryChecks.counts(db) == manifest.counts)
            }
            try queue.close()
            boundaries.append(manifest.snapshot.change_journal_seq)
        }
        evidence("export during edits: \(written) capture+note transaction pairs by the concurrent writer; journal entries written during each export \(concurrentWrites); snapshot boundaries \(boundaries)")
        #expect(concurrentWrites.allSatisfy { $0 > 1 }, "the writer must make progress while each export runs")
        #expect(boundaries == boundaries.sorted())
    }

    @Test("T47: cleanup racing an export cannot remove a leased excerpt; the bundle still has it")
    func leaseProtectsBlob() throws {
        let scratch = try Scratch()
        let (store, corpus) = try corpusLibrary(scratch)
        defer { try? store.close() }
        let blobs = BlobStore(store)
        let raced = Box<BlobStore.CollectionResult>()
        let bundle = scratch.dir("Exports/race.sylviabackup")
        try FileManager.default.createDirectory(at: bundle.deletingLastPathComponent(), withIntermediateDirectories: true)
        let hooks = ExportHooks(afterSnapshot: {
            // After the snapshot boundary the user removes the excerpt audio and cleanup runs.
            try blobs.deleteRetainedExcerpts(captureID: corpus.captures["audio"]!)
            raced.value = try blobs.collectGarbage()
        })
        _ = try BackupExporter(store).export(to: bundle, hooks: hooks)
        #expect(raced.value?.keptBecauseLeased == [corpus.excerptSHA256])
        #expect(raced.value?.removed.isEmpty == true)
        let copied = bundle.appending(path: "blobs/excerpts/\(corpus.excerptSHA256).mp3")
        #expect(try Digest.sha256Hex(fileAt: copied).digest == corpus.excerptSHA256)
        // Lease released after export: now cleanup removes the unreferenced blob.
        #expect(try blobs.collectGarbage().removed == [corpus.excerptSHA256])
    }

    @Test("an excerpt missing from disk fails the export instead of producing an incomplete bundle")
    func missingBlobFailsExport() throws {
        let scratch = try Scratch()
        let (store, corpus) = try corpusLibrary(scratch)
        defer { try? store.close() }
        try FileManager.default.removeItem(at: BlobStore(store).url(sha256: corpus.excerptSHA256, fileExtension: "mp3"))
        let bundle = scratch.dir("Exports/missing.sylviabackup")
        try FileManager.default.createDirectory(at: bundle.deletingLastPathComponent(), withIntermediateDirectories: true)
        #expect(throws: BackupError.missingBlob(corpus.excerptSHA256)) { _ = try BackupExporter(store).export(to: bundle) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: bundle.deletingLastPathComponent().path).isEmpty,
                "no partial bundle may remain")
        #expect(try store.pool.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM retention_lease") } == 0)
    }
}

func corpusWork(_ store: LibraryStore) throws -> String {
    try store.pool.read { try String.fetchOne($0, sql: "SELECT id FROM work WHERE title = 'Walden; or, Life in the Woods'")! }
}

final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?
    var value: T? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

@Suite("Restore (plan 17.4, T35, T46, T47, J-06)")
struct RestoreTests {
    @Test("restore drill after source deletion (J-06, T35)")
    func drill() throws {
        let scratch = try Scratch()
        let report = try RestoreDrill.run(workDirectory: scratch.dir("drill"))
        evidence("restore drill\n\(report)")
        #expect(report.failures.isEmpty, "\(report.failures)")
        #expect(report.checks.count >= 30)
    }

    /// A good bundle exported from a corpus library, plus a separate active library to protect.
    struct Fixture {
        let scratch: Scratch
        let bundle: URL
        let active: LibraryStore
        let activeLayout: LibraryLayout
    }

    func makeFixture() throws -> Fixture {
        let scratch = try Scratch()
        let (source, _) = try corpusLibrary(scratch, "Source")
        let bundle = scratch.dir("Exports/good.sylviabackup")
        try FileManager.default.createDirectory(at: bundle.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try BackupExporter(source).export(to: bundle)
        try source.close()
        let activeLayout = scratch.layout("Active")
        let active = try LibraryStore.open(activeLayout)
        try active.pool.write { (db: Database) throws in
            try active.insertJournaled(db, "work", id: "11111111-1111-4111-8111-111111111111", [
                "id": "11111111-1111-4111-8111-111111111111", "title": "Active library work", "sort_title": "active",
                "description": nil, "language_tag": "en", "metadata_revision": 1, "created_at_ms": 1, "updated_at_ms": 1, "deleted_at_ms": nil,
            ])
        }
        return Fixture(scratch: scratch, bundle: bundle, active: active, activeLayout: activeLayout)
    }

    /// Applies `damage` to a copy of the good bundle and checks that `prepare` rejects it with
    /// `expected`, leaving the active library byte-for-byte unchanged and no restore work behind.
    func expectRejected(_ name: String, _ fixture: Fixture, damage: (URL) throws -> Void,
                        matches expected: (BackupError) -> Bool) throws {
        let variant = fixture.scratch.dir("Variants/\(name).sylviabackup")
        try FileManager.default.createDirectory(at: variant.deletingLastPathComponent(), withIntermediateDirectories: true)
        try copyTree(fixture.bundle, to: variant)
        try damage(variant)
        let before = try treeFingerprint(fixture.activeLayout.libraryDirectory, excluding: ["library.sqlite-shm"])
        let beforeDump = try fixture.active.pool.read { try LibraryChecks.knowledgeDump($0) }
        let restorer = BackupRestorer(layout: fixture.activeLayout)
        var thrown: (any Error)?
        do { _ = try restorer.prepare(bundle: variant) } catch { thrown = error }
        guard let error = thrown as? BackupError else {
            Issue.record("\(name): expected a BackupError, got \(String(describing: thrown))"); return
        }
        #expect(expected(error), "\(name): unexpected error \(error)")
        evidence("rejected \(name): \(error)")
        #expect(try treeFingerprint(fixture.activeLayout.libraryDirectory, excluding: ["library.sqlite-shm"]) == before, "\(name) altered the library files")
        #expect(try fixture.active.pool.read { try LibraryChecks.knowledgeDump($0) } == beforeDump)
        let leftovers = try FileManager.default.subpathsOfDirectory(atPath: fixture.activeLayout.restoreWorkDirectory.path)
        #expect(leftovers.isEmpty, "\(name) left restore work behind: \(leftovers.prefix(5))")
    }

    @Test("T46: corrupt, truncated, newer and malicious backups are rejected without touching the library")
    func rejections() throws {
        let fixture = try makeFixture()
        defer { try? fixture.active.close() }
        let db = "database/library.sqlite"
        func manifestURL(_ b: URL) -> URL { b.appending(path: "manifest.json") }

        try expectRejected("newer-manifest-version", fixture, damage: { b in
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL(b))) as! [String: Any]
            json["schema_version"] = 2
            json["files"] = "reshaped in v2"
            try JSONSerialization.data(withJSONObject: json).write(to: manifestURL(b))
        }) { $0 == .unsupportedManifestVersion(2) }

        try expectRejected("newer-library-schema-in-manifest", fixture, damage: { b in
            try rewriteManifest(b) { $0.library.schema_version = 3; $0.library.migrations.append("v3-future") }
        }) { if case .newerLibrarySchema(3, 2, ["v3-future"]) = $0 { return true }; return false }

        try expectRejected("newer-library-schema-in-database", fixture, damage: { b in
            let queue = try DatabaseQueue(path: b.appending(path: db).path)
            try queue.write { try $0.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v3-future')") }
            try queue.close()
            try rewriteManifest(b) { try refreshEntry(&$0, bundle: b, path: db) }
        }) { if case .newerLibrarySchema(_, 2, ["v3-future"]) = $0 { return true }; return false }

        try expectRejected("truncated-database", fixture, damage: { b in
            let url = b.appending(path: db)
            let data = try Data(contentsOf: url)
            try data.prefix(data.count / 2).write(to: url)
        }) { if case .sizeMismatch(db, _, _) = $0 { return true }; return false }

        try expectRejected("bit-flip-in-database", fixture, damage: { b in
            let url = b.appending(path: db)
            var data = try Data(contentsOf: url)
            data[data.count - 100] ^= 0x01
            try data.write(to: url)
        }) { $0 == .digestMismatch(path: db) }

        try expectRejected("corrupt-database-with-matching-digest", fixture, damage: { b in
            let url = b.appending(path: db)
            var data = try Data(contentsOf: url)
            for i in stride(from: 4096, to: min(data.count, 4096 * 6), by: 7) { data[i] = 0xFF }
            try data.write(to: url)
            try rewriteManifest(b) { try refreshEntry(&$0, bundle: b, path: db) }
        }) { if case .corruptDatabase = $0 { return true }; return false }

        try expectRejected("not-a-database", fixture, damage: { b in
            try Data(repeating: 0x41, count: 8192).write(to: b.appending(path: db))
            try rewriteManifest(b) { try refreshEntry(&$0, bundle: b, path: db) }
        }) { if case .corruptDatabase = $0 { return true }; return false }

        try expectRejected("foreign-key-violation-with-matching-digest", fixture, damage: { b in
            let queue = try DatabaseQueue(path: b.appending(path: db).path)
            try queue.writeWithoutTransaction { (db: Database) throws in
                try db.execute(sql: "PRAGMA foreign_keys = OFF")
                try db.execute(sql: "UPDATE capture SET work_id = '99999999-9999-4999-8999-999999999999' WHERE kind = 'word'")
            }
            try queue.close()
            try rewriteManifest(b) { try refreshEntry(&$0, bundle: b, path: db) }
        }) { $0 == .foreignKeyViolations(1) }

        try expectRejected("count-mismatch", fixture, damage: { b in
            try rewriteManifest(b) { $0.counts["capture"] = 4 }
        }) { $0 == .countMismatch(table: "capture", expected: 4, actual: 5) }

        for (label, path) in [("traversal", "../outside.txt"), ("absolute", "/etc/passwd"), ("nested-traversal", "blobs/excerpts/../../../x"),
                              ("backslash", "blobs\\excerpts\\x"), ("hidden", ".hidden/x"), ("unicode", "export/markdown/caf\u{e9}.md")] {
            try expectRejected("path-\(label)", fixture, damage: { b in
                try rewriteManifest(b) { $0.files.append(.init(path: path, role: .markdown, sha256: String(repeating: "a", count: 64), byte_count: 1)) }
            }) { $0 == .unsafePath(path) }
        }

        try expectRejected("symlink-to-outside", fixture, damage: { b in
            let outside = fixture.scratch.url.appending(path: "outside-secret.txt")
            try Data("outside".utf8).write(to: outside)
            let target = b.appending(path: "export/markdown/link.md")
            try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside)
            try rewriteManifest(b) { $0.files.append(.init(path: "export/markdown/link.md", role: .markdown,
                                                            sha256: Digest.sha256Hex("outside"), byte_count: 7)) }
        }) { $0 == .symlinkInBundle("export/markdown/link.md") }

        try expectRejected("symlinked-directory", fixture, damage: { b in
            let outside = fixture.scratch.dir("outside-dir")
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            let markdown = b.appending(path: "export/markdown")
            let names = try FileManager.default.contentsOfDirectory(atPath: markdown.path)
            for name in names { try FileManager.default.moveItem(at: markdown.appending(path: name), to: outside.appending(path: name)) }
            try FileManager.default.removeItem(at: markdown)
            try FileManager.default.createSymbolicLink(at: markdown, withDestinationURL: outside)
        }) { if case .symlinkInBundle = $0 { return true }; return false }

        try expectRejected("unlisted-file", fixture, damage: { b in
            try Data("extra".utf8).write(to: b.appending(path: "export/extra.txt"))
        }) { $0 == .unlistedFile("export/extra.txt") }

        try expectRejected("missing-blob-file", fixture, damage: { b in
            let blobs = b.appending(path: "blobs/excerpts")
            for name in try FileManager.default.contentsOfDirectory(atPath: blobs.path) { try FileManager.default.removeItem(at: blobs.appending(path: name)) }
        }) { if case .missingFile = $0 { return true }; return false }

        try expectRejected("blob-dropped-from-manifest", fixture, damage: { b in
            let blobs = b.appending(path: "blobs/excerpts")
            for name in try FileManager.default.contentsOfDirectory(atPath: blobs.path) { try FileManager.default.removeItem(at: blobs.appending(path: name)) }
            try rewriteManifest(b) { $0.files.removeAll { $0.role == .retained_excerpt } }
        }) { if case .missingBlob = $0 { return true }; return false }

        try expectRejected("unreferenced-blob", fixture, damage: { b in
            let data = Data("not referenced".utf8)
            let sha = Digest.sha256Hex(data)
            try data.write(to: b.appending(path: "blobs/excerpts/\(sha).mp3"))
            try rewriteManifest(b) { $0.files.append(.init(path: "blobs/excerpts/\(sha).mp3", role: .retained_excerpt, sha256: sha, byte_count: Int64(data.count))) }
        }) { if case .unreferencedBlob = $0 { return true }; return false }

        try expectRejected("duplicate-path", fixture, damage: { b in
            try rewriteManifest(b) { m in m.files.append(m.files.first { $0.role == .portable_json }!) }
        }) { $0 == .duplicatePath("export/library.json") }

        try expectRejected("role-mismatch", fixture, damage: { b in
            try rewriteManifest(b) { m in
                let i = m.files.firstIndex { $0.role == .portable_json }!
                m.files[i].role = .database_snapshot
            }
        }) { $0 == .roleMismatch(path: "export/library.json", role: "database_snapshot") }

        try expectRejected("missing-manifest", fixture, damage: { b in
            try FileManager.default.removeItem(at: manifestURL(b))
        }) { $0 == .manifestMissing }

        try expectRejected("garbage-manifest", fixture, damage: { b in
            try Data("{ not json".utf8).write(to: manifestURL(b))
        }) { if case .manifestUnreadable = $0 { return true }; return false }

        try expectRejected("oversized-manifest", fixture, damage: { b in
            try Data(repeating: 0x20, count: BackupManifest.maximumBytes + 1).write(to: manifestURL(b))
        }) { $0 == .manifestTooLarge(Int64(BackupManifest.maximumBytes + 1)) }

        try expectRejected("complete-claim-with-excluded-media", fixture, damage: { b in
            try rewriteManifest(b) { $0.complete = true }
        }) { $0 == .invalidField("complete") }

        // I-09: a manifest that is internally consistent but does not describe the snapshot's assets.
        try expectRejected("complete-claim-hiding-excluded-media", fixture, damage: { b in
            try rewriteManifest(b) { $0.complete = true; $0.excluded_media = [] }
        }) { if case .excludedMediaMismatch = $0 { return true }; return false }

        try expectRejected("excluded-media-wrong-digest", fixture, damage: { b in
            try rewriteManifest(b) { $0.excluded_media[0].sha256 = String(repeating: "0", count: 64) }
        }) { if case .excludedMediaMismatch = $0 { return true }; return false }

        try expectRejected("excluded-media-asset-missing", fixture, damage: { b in
            try rewriteManifest(b) { $0.excluded_media.removeLast() }
        }) { if case .excludedMediaMismatch = $0 { return true }; return false }

        // Malicious database content with matching digests (plan 18.1): the snapshot's schema must be
        // exactly what this build's migrations produce. Each case changes only the database.
        func damageDatabase(_ b: URL, _ sql: String) throws {
            let queue = try DatabaseQueue(path: b.appending(path: db).path)
            try queue.writeWithoutTransaction { (db: Database) throws in
                // The attacker's own SQLite: not defensive, so writable_schema works.
                #expect(sylvia_sqlite_set_defensive(db.sqliteConnection, 0) == 0)
                try db.execute(sql: "PRAGMA foreign_keys = OFF")
                try db.execute(sql: sql)
            }
            try queue.close()
            try rewriteManifest(b) { try refreshEntry(&$0, bundle: b, path: db) }
        }
        func schemaMismatch(_ detail: String) -> (BackupError) -> Bool {
            { if case .schemaMismatch(let why) = $0 { return why.contains(detail) }; return false }
        }
        try expectRejected("trigger-deleting-knowledge", fixture, damage: { b in
            try damageDatabase(b, "CREATE TRIGGER evil AFTER UPDATE ON asset_location BEGIN DELETE FROM recommendation_event; END")
        }, matches: schemaMismatch("unexpected trigger evil"))

        try expectRejected("view", fixture, damage: { b in
            try damageDatabase(b, "CREATE VIEW peek AS SELECT * FROM note_revision")
        }, matches: schemaMismatch("unexpected view peek"))

        try expectRejected("extra-table", fixture, damage: { b in
            try damageDatabase(b, "CREATE TABLE unexpected_table (x TEXT)")
        }, matches: schemaMismatch("unexpected table unexpected_table"))

        try expectRejected("rating-without-strict-or-check", fixture, damage: { b in
            try damageDatabase(b, """
                CREATE TABLE rating_loose (work_id TEXT PRIMARY KEY NOT NULL REFERENCES work(id) ON DELETE RESTRICT,
                  value INTEGER, scale TEXT NOT NULL DEFAULT 'half_stars_1_10', updated_at_ms INTEGER NOT NULL, review_note TEXT);
                INSERT INTO rating_loose SELECT work_id, value, scale, updated_at_ms, review_note FROM rating;
                DROP TABLE rating;
                ALTER TABLE rating_loose RENAME TO rating;
                """)
        }, matches: schemaMismatch("altered table rating"))

        try expectRejected("capture-anchor-cascade-from-asset", fixture, damage: { b in
            // Same columns, but deleting an asset would now cascade into knowledge (I-02).
            try damageDatabase(b, """
                PRAGMA writable_schema = ON;
                UPDATE sqlite_schema SET sql = replace(sql, 'asset_id TEXT REFERENCES asset(id) ON DELETE RESTRICT',
                                                       'asset_id TEXT REFERENCES asset(id) ON DELETE CASCADE')
                  WHERE type = 'table' AND name = 'capture_anchor';
                PRAGMA writable_schema = OFF;
                """)
        }, matches: schemaMismatch("altered table capture_anchor"))

        try expectRejected("dropped-index", fixture, damage: { b in
            try damageDatabase(b, "DROP INDEX capture_work")
        }, matches: schemaMismatch("missing index capture_work"))

        // Row values the schema does not constrain (review round 2): effective dates and the
        // ChangeJournal sequence. The schema, counts and foreign keys of these snapshots are valid.
        func invalidRows(_ detail: String) -> (BackupError) -> Bool {
            { if case .invalidRows(let why) = $0 { return why.contains(detail) }; return false }
        }
        try expectRejected("effective-date-not-a-date", fixture, damage: { b in
            try damageDatabase(b, "UPDATE consumption_run SET started_date = 'banana', started_date_precision = 'day'")
        }, matches: invalidRows("consumption_run.started_date"))

        try expectRejected("effective-date-not-its-precision", fixture, damage: { b in
            try damageDatabase(b, "UPDATE ledger_event SET effective_date = '2019-02-30', effective_date_precision = 'year'")
        }, matches: invalidRows("ledger_event.effective_date"))

        try expectRejected("effective-date-impossible-day", fixture, damage: { b in
            try damageDatabase(b, "UPDATE edition SET published_date = '2019-02-30', published_date_precision = 'day' WHERE published_date IS NOT NULL")
        }, matches: invalidRows("edition.published_date"))

        try expectRejected("recommendation-date-not-a-date", fixture, damage: { b in
            try damageDatabase(b, "UPDATE recommendation_event SET event_date = '2024-13', event_date_precision = 'month'")
        }, matches: invalidRows("recommendation_event.event_date"))

        try expectRejected("journal-sequence-near-int64-max", fixture, damage: { b in
            try damageDatabase(b, "UPDATE sqlite_sequence SET seq = 9223372036854775807 - 20 WHERE name = 'change_journal'")
        }, matches: invalidRows("sqlite_sequence for change_journal is 9223372036854775787"))

        try expectRejected("journal-sequence-extra-entry", fixture, damage: { b in
            try damageDatabase(b, "INSERT INTO sqlite_sequence (name, seq) VALUES ('work', 5)")
        }, matches: invalidRows("sqlite_sequence has an entry for 'work'"))

        // Review round 3: a sign is not a digit (Swift's Int(String) accepts "+019").
        try expectRejected("effective-date-plus-sign-year", fixture, damage: { b in
            try damageDatabase(b, "UPDATE ledger_event SET effective_date = '+019', effective_date_precision = 'year'")
        }, matches: invalidRows("ledger_event.effective_date"))

        try expectRejected("effective-date-plus-sign-day", fixture, damage: { b in
            try damageDatabase(b, "UPDATE consumption_run SET started_date = '2019-+1-+5', started_date_precision = 'day'")
        }, matches: invalidRows("consumption_run.started_date"))

        // Review round 3: a note's revisions must be exactly 1...current_revision, because
        // `reviseNote` inserts current_revision + 1 (stale: every later edit fails on the key;
        // Int64.max: the + 1 would overflow; dangling: the note has no current text).
        let noteWithRevisions = "(SELECT note_id FROM note_revision GROUP BY note_id HAVING count(*) >= 2 ORDER BY note_id LIMIT 1)"
        try expectRejected("note-current-revision-stale", fixture, damage: { b in
            try damageDatabase(b, "UPDATE note SET current_revision = 1 WHERE id = \(noteWithRevisions)")
        }, matches: invalidRows("current_revision 1 but"))

        try expectRejected("note-current-revision-int64-max", fixture, damage: { b in
            try damageDatabase(b, "UPDATE note SET current_revision = 9223372036854775807 WHERE id = \(noteWithRevisions)")
        }, matches: invalidRows("current_revision 9223372036854775807 but"))

        try expectRejected("note-current-revision-dangling", fixture, damage: { b in
            try damageDatabase(b, "UPDATE note SET current_revision = 77 WHERE id = \(noteWithRevisions)")
        }, matches: invalidRows("current_revision 77 but"))

        try expectRejected("note-revisions-not-from-one", fixture, damage: { b in
            try damageDatabase(b, "DELETE FROM note_revision WHERE revision = 1 AND note_id = \(noteWithRevisions)")
            try rewriteManifest(b) { $0.counts["note_revision"]! -= 1 }
        }, matches: invalidRows("revisions must be exactly 1...current_revision"))

        // Review round 3: every INTEGER stays within ±(2^53 - 1), so the JSON export can always run
        // and no counter the app increments can overflow.
        try expectRejected("work-metadata-revision-2-pow-53", fixture, damage: { b in
            try damageDatabase(b, "UPDATE work SET metadata_revision = 9007199254740992")
        }, matches: invalidRows("work.metadata_revision"))

        try expectRejected("edition-asset-timeline-revision-int64-max", fixture, damage: { b in
            try damageDatabase(b, "UPDATE edition_asset SET timeline_revision = 9223372036854775807")
        }, matches: invalidRows("edition_asset.timeline_revision"))

        try expectRejected("work-created-at-int64-min", fixture, damage: { b in
            try damageDatabase(b, "UPDATE work SET created_at_ms = -9223372036854775807 - 1")
        }, matches: invalidRows("work.created_at_ms"))

        // Review round 4 (finding F12): GRDB reads TEXT as a C string, so a stored NUL hides the rest
        // of the text and invalid UTF-8 is replaced; the app would show, edit and export other text
        // than is stored. Every TEXT value must be valid UTF-8 without a NUL.
        try expectRejected("text-with-nul", fixture, damage: { b in
            try damageDatabase(b, """
                UPDATE note_revision SET body = CAST(CAST(body AS BLOB) || X'00' || CAST('hidden after a NUL' AS BLOB) AS TEXT)
                WHERE rowid = (SELECT min(rowid) FROM note_revision)
                """)
        }, matches: invalidRows("note_revision.body"))

        try expectRejected("text-invalid-utf8", fixture, damage: { b in
            try damageDatabase(b, "UPDATE capture SET quoted_text = CAST(X'73617574FF6572696E67' AS TEXT) WHERE kind = 'word'")
        }, matches: invalidRows("capture.quoted_text"))

        // Cover thumbnails follow the same rules as excerpt blobs.
        try expectRejected("unreferenced-cover", fixture, damage: { b in
            let data = Data("not a referenced cover".utf8)
            let sha = Digest.sha256Hex(data)
            try data.write(to: b.appending(path: "blobs/covers/\(sha).jpg"))
            try rewriteManifest(b) { $0.files.append(.init(path: "blobs/covers/\(sha).jpg", role: .cover_thumbnail, sha256: sha, byte_count: Int64(data.count))) }
        }) { if case .unreferencedBlob = $0 { return true }; return false }

        try expectRejected("cover-dropped-from-manifest", fixture, damage: { b in
            let covers = b.appending(path: "blobs/covers")
            for name in try FileManager.default.contentsOfDirectory(atPath: covers.path) { try FileManager.default.removeItem(at: covers.appending(path: name)) }
            try rewriteManifest(b) { $0.files.removeAll { $0.role == .cover_thumbnail } }
        }) { if case .missingBlob = $0 { return true }; return false }

        // An unreadable directory must not end the bundle walk early and hide an unlisted file.
        let hidden = "export/zz-unreadable"
        try expectRejected("unreadable-directory-with-unlisted-file", fixture, damage: { b in
            let directory = b.appending(path: hidden)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("unlisted".utf8).write(to: directory.appending(path: "unlisted.txt"))
            #expect(chmod(directory.path, 0) == 0)
        }) { $0 == .notABundle("cannot read \(hidden)") }
        _ = chmod(fixture.scratch.dir("Variants/unreadable-directory-with-unlisted-file.sylviabackup").appending(path: hidden).path, 0o700)
    }

    @Test("untrusted databases are opened in SQLite's defensive mode with trusted_schema off")
    func defensiveOpen() throws {
        let scratch = try Scratch()
        let url = scratch.url.appending(path: "untrusted.sqlite")
        let setup = try DatabaseQueue(path: url.path)
        let defaults = try setup.writeWithoutTransaction { (db: Database) throws -> (defensive: Int32, trusted: Int) in
            try db.execute(sql: "CREATE TABLE t (x INTEGER) STRICT")
            return (sylvia_sqlite_defensive_state(db.sqliteConnection), try Int.fetchOne(db, sql: "PRAGMA trusted_schema") ?? -1)
        }
        try setup.close()
        // Informational: what a default GRDB connection on this platform has. Restore does not rely on it.
        evidence("default GRDB connection: SQLITE_DBCONFIG_DEFENSIVE=\(defaults.defensive) trusted_schema=\(defaults.trusted); untrusted configuration sets 1 and 0")
        let queue = try DatabaseQueue(path: url.path, configuration: SchemaCheck.untrustedConfiguration())
        defer { try? queue.close() }
        try queue.writeWithoutTransaction { (db: Database) throws in
            #expect(sylvia_sqlite_defensive_state(db.sqliteConnection) == 1)
            #expect(try Int.fetchOne(db, sql: "PRAGMA trusted_schema") == 0)
            // Defensive mode ignores writable_schema, so the schema table stays read-only.
            try db.execute(sql: "PRAGMA writable_schema = ON")
            #expect(throws: DatabaseError.self) {
                try db.execute(sql: "UPDATE sqlite_schema SET sql = 'CREATE TABLE t (x TEXT)' WHERE name = 't'")
            }
        }
        #expect(try queue.read { try String.fetchOne($0, sql: "SELECT sql FROM sqlite_schema WHERE name = 't'") } == "CREATE TABLE t (x INTEGER) STRICT")
    }

    @Test("the reference schema equals a real library's schema for every migration prefix")
    func referenceSchemaMatchesLibraries() throws {
        let scratch = try Scratch()
        let identifiers = LibrarySchema.migrations.map(\.identifier)
        for count in 1...identifiers.count {
            var options = StoreOptions()
            options.migrateUpTo = identifiers[count - 1]
            let store = try LibraryStore.open(scratch.layout("prefix-\(count)"), options: options)
            let applied = try store.pool.read { try LibrarySchema.applied($0) }
            #expect(applied == Array(identifiers.prefix(count)))
            try store.pool.read { (db: Database) throws in try SchemaCheck.requireReference(db, applied: applied) }
            try store.close()
        }
        // The committed v1 fixture too.
        let fixture = try RecoveryAccess.openReadOnly(MigrationTests.fixture)
        try fixture.read { (db: Database) throws in try SchemaCheck.requireReference(db, applied: ["v1-initial"]) }
        try fixture.close()
        // A migration list that skips one is not a schema this build produces.
        #expect(try SchemaCheck.reference(applied: ["v1-initial", "v2-recommendation-date-precision"]) == nil)
    }

    @Test("restore replaces the active library only with confirmation and keeps a pre-restore copy")
    func replaceWithConfirmation() throws {
        let fixture = try makeFixture()
        let restorer = BackupRestorer(layout: fixture.activeLayout)
        let plan = try restorer.prepare(bundle: fixture.bundle)
        #expect(throws: BackupError.confirmationRequired) { _ = try restorer.commit(plan, confirmation: nil, activeStore: fixture.active) }
        // Still open and unchanged after the refused commit.
        #expect(try fixture.active.pool.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM work") } == 1)
        let result = try restorer.commit(plan, confirmation: .replaceExistingLibrary, activeStore: fixture.active)
        defer { try? result.store.close() }
        #expect(try result.store.pool.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM work") } == 3)
        let copy = try #require(result.preRestoreCopy)
        let queue = try RecoveryAccess.openReadOnly(copy.appending(path: "library.sqlite"))
        #expect(try queue.read { try String.fetchAll($0, sql: "SELECT title FROM work") } == ["Active library work"])
        try queue.close()
        #expect(!FileManager.default.fileExists(atPath: fixture.activeLayout.restoreIntentURL.path))
    }

    @Test("J-06: originals that were on the source device are restored as at-source or unavailable records, never as on-device")
    func onDeviceMediaBecomesUnavailable() throws {
        let fixture = try makeFixture()
        // The bundle was exported with media still on the source device (the common J-06 case).
        let snapshot = try RecoveryAccess.openReadOnly(fixture.bundle.appending(path: "database/library.sqlite"))
        let exported = try snapshot.read { (db: Database) throws in
            (locations: try Row.fetchAll(db, sql: "SELECT id, asset_id, source_id, availability FROM asset_location ORDER BY id")
                .map { (id: $0["id"] as String, assetID: $0["asset_id"] as String, sourceID: $0["source_id"] as String?, availability: $0["availability"] as String) },
             assets: try Int.fetchOne(db, sql: "SELECT count(*) FROM asset") ?? -1)
        }
        try snapshot.close()
        let onDeviceAtExport = exported.locations.filter { $0.availability == "on_device" }
        #expect(onDeviceAtExport.count >= 4, "the fixture must export originals that are on the device")
        #expect(onDeviceAtExport.contains { $0.sourceID != nil } && onDeviceAtExport.contains { $0.sourceID == nil })

        let restorer = BackupRestorer(layout: fixture.activeLayout)
        let plan = try restorer.prepare(bundle: fixture.bundle)
        #expect(plan.unavailableAssets == exported.assets)
        #expect(plan.unavailableAssets == plan.manifest.excluded_media.count)
        let result = try restorer.commit(plan, confirmation: .replaceExistingLibrary, activeStore: fixture.active)
        defer { try? result.store.close() }
        let restored = try result.store.pool.read { (db: Database) throws in
            Dictionary(uniqueKeysWithValues: try Row.fetchAll(db, sql: "SELECT id, availability, local_relative_path FROM asset_location").map {
                ($0["id"] as String, (availability: $0["availability"] as String, path: $0["local_relative_path"] as String?))
            })
        }
        #expect(restored.count == exported.locations.count)
        for location in exported.locations {
            let after = try #require(restored[location.id])
            #expect(after.availability != "on_device" && after.path == nil, "\(location.id) still claims a local file")
            if location.availability == "on_device" {
                #expect(after.availability == (location.sourceID == nil ? "unavailable" : "at_source"))
            } else {
                #expect(after.availability == location.availability, "locations that were not on the device keep their state")
            }
        }
        let journaled = try result.store.pool.read { (db: Database) throws in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM change_journal WHERE entity = 'asset_location' AND operation = 'update' AND seq > ?",
                             arguments: [plan.manifest.snapshot.change_journal_seq]) ?? -1
        }
        #expect(journaled == onDeviceAtExport.count)
        let media = MediaService(result.store)
        var states: [String: Int] = [:]
        for assetID in Set(exported.locations.map(\.assetID)) {
            switch try media.availability(assetID: assetID) {
            case .onDevice: Issue.record("\(assetID) resolves as on device after restore")
            case .atSource(let kind): states["not on this device · from \(kind)", default: 0] += 1
            case .recordOnly: states["record only", default: 0] += 1
            }
        }
        evidence("restore of a bundle exported with \(onDeviceAtExport.count) originals on the device: \(onDeviceAtExport.count) locations converted, availability \(states.sorted { $0.key < $1.key })")
    }

    @Test("a backup from an older library schema (v1) is migrated in the temporary library before the swap")
    func restoreOlderBackup() throws {
        let scratch = try Scratch()
        var options = StoreOptions()
        options.migrateUpTo = "v1-initial"
        let (old, _) = try corpusLibrary(scratch, "Old", options: options)
        #expect(try old.schemaVersion == 1)
        let before = try old.pool.read { try MigrationTests.preservedDump($0) }
        let bundle = scratch.dir("Exports/v1.sylviabackup")
        try FileManager.default.createDirectory(at: bundle.deletingLastPathComponent(), withIntermediateDirectories: true)
        let exported = try BackupExporter(old).export(to: bundle)
        try old.close()
        #expect(exported.manifest.library.schema_version == 1 && exported.manifest.library.migrations == ["v1-initial"])

        let restorer = BackupRestorer(layout: scratch.layout("New"))
        let plan = try restorer.prepare(bundle: bundle)
        #expect(plan.librarySchemaVersion == 2)
        let result = try restorer.commit(plan, confirmation: .replaceExistingLibrary, activeStore: nil)
        defer { try? result.store.close() }
        #expect(try result.store.schemaVersion == 2)
        try result.store.pool.read { (db: Database) throws in
            #expect(try MigrationTests.preservedDump(db) == before)
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM recommendation_event WHERE event_date_precision IS NULL") == 0)
        }
    }

    @Test("insufficient space refuses a restore before anything is copied")
    func restoreSpace() throws {
        let fixture = try makeFixture()
        defer { try? fixture.active.close() }
        var options = StoreOptions()
        options.space = FixedSpaceProbe(bytes: 4096)
        #expect { _ = try BackupRestorer(layout: fixture.activeLayout, options: options).prepare(bundle: fixture.bundle) } throws: { error in
            if case BackupError.insufficientSpace(_, 4096) = error { return true }
            return false
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.activeLayout.restoreWorkDirectory.path).isEmpty)
    }

    @Test("T47: a crash at any point of the swap leaves either the old or the restored library, never neither",
          arguments: RestoreStep.allCases)
    func crashDuringSwap(step: RestoreStep) throws {
        let fixture = try makeFixture()
        let restorer = BackupRestorer(layout: fixture.activeLayout)
        let plan = try restorer.prepare(bundle: fixture.bundle)
        #expect(throws: BackupError.simulatedCrash(step.rawValue)) {
            _ = try restorer.commit(plan, confirmation: .replaceExistingLibrary, activeStore: fixture.active,
                                    hooks: RestoreHooks(crashAfter: step))
        }
        // Next launch, through the real launch path.
        let store = try LibraryStore.open(fixture.activeLayout)
        defer { try? store.close() }
        let outcome = store.openReport.restoreReconciliation
        let titles = try store.pool.read { try String.fetchAll($0, sql: "SELECT title FROM work ORDER BY title") }
        evidence("crash after \(step.rawValue): reconcile -> \(outcome); library works \(titles)")
        switch step {
        case .intentWritten:
            #expect(outcome == .keptExistingLibrary)
            #expect(titles == ["Active library work"])
        case .activeMovedAside, .restoredMovedIn:
            #expect(outcome == .completedRestore)
            #expect(titles.count == 3)
        }
        try store.pool.read { (db: Database) throws in
            #expect(try LibraryChecks.integrity(db) == ["ok"])
            #expect(try LibraryChecks.foreignKeyViolations(db).isEmpty)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.activeLayout.restoreIntentURL.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.activeLayout.restoreWorkDirectory.path).isEmpty)
    }

    #if os(macOS)
    @Test("T47: SIGKILL during prepare or the swap leaves exactly the old or the restored library (short run; CI runs 300)")
    func restoreCrashDrillShort() throws {
        let scratch = try Scratch()
        let executable = toolExecutable()
        #expect(FileManager.default.isExecutableFile(atPath: executable.path), "tool not built at \(executable.path)")
        let drill = RestoreCrashDrillParent(executable: executable, workDirectory: scratch.dir("restore-crash"), iterations: 30, seed: 11)
        let report = try drill.run()
        evidence("restore crash drill (short)\n\(report)")
        #expect(report.failures.isEmpty)
        #expect((report.killsByWindow["prepare"] ?? 0) >= 5 && (report.killsByWindow["commit"] ?? 0) >= 5)
        #expect((report.outcomes["old library kept"] ?? 0) > 0 && (report.outcomes["restored library"] ?? 0) > 0)
    }
    #endif

    @Test("a preparation abandoned by a crash is cleared at the next launch, and the library is untouched")
    func abandonedPreparation() throws {
        let fixture = try makeFixture()
        let plan = try BackupRestorer(layout: fixture.activeLayout).prepare(bundle: fixture.bundle)
        #expect(FileManager.default.fileExists(atPath: plan.workDirectory.path))
        try fixture.active.close()
        let store = try LibraryStore.open(fixture.activeLayout)
        defer { try? store.close() }
        #expect(store.openReport.restoreReconciliation == .nothingToDo)
        #expect(!FileManager.default.fileExists(atPath: plan.workDirectory.path))
        #expect(try store.pool.read { try String.fetchAll($0, sql: "SELECT title FROM work") } == ["Active library work"])
    }

    /// What an invalid or unreadable intent must leave alone: the intent itself, the prepared restore
    /// in `RestoreWork/`, and every library file.
    struct SwapState: Equatable {
        let intent: Data?
        let restoreWork: [String: String]
        let library: [String: String]
    }

    func swapState(_ layout: LibraryLayout) throws -> SwapState {
        SwapState(intent: try? Data(contentsOf: layout.restoreIntentURL),
                  restoreWork: try treeFingerprint(layout.restoreWorkDirectory),
                  library: try treeFingerprint(layout.libraryDirectory, excluding: ["library.sqlite-shm"]))
    }

    @Test("an invalid restore intent fails the open and changes nothing (no empty library, prepared restore kept)",
          arguments: ["not json", #"{"id":"x"}"#, "traversal"])
    func invalidRestoreIntent(kind: String) throws {
        let fixture = try makeFixture()
        let layout = fixture.activeLayout
        let plan = try BackupRestorer(layout: layout).prepare(bundle: fixture.bundle)
        try fixture.active.close()
        let body: String
        switch kind {
        case "traversal":
            // Well-formed, but its paths do not match the fixed shape for its ID.
            body = #"{"id":"\#(plan.id)","pre_restore_library":"../Elsewhere/Library","work_library":"RestoreWork/\#(plan.id)/Library"}"#
        default:
            body = kind
        }
        try Data(body.utf8).write(to: layout.restoreIntentURL)
        let before = try swapState(layout)
        #expect(!before.restoreWork.isEmpty)
        #expect { _ = try LibraryStore.open(layout) } throws: { error in
            guard case StoreError.invalid(let why) = error else { return false }
            evidence("restore intent \(kind.debugDescription): open refused: \(why)")
            return why.contains("restore intent")
        }
        #expect(try swapState(layout) == before, "an invalid intent must not change any file")
        // Read-only recovery access still shows the user's library.
        let queue = try RecoveryAccess.openReadOnly(layout.databaseURL)
        #expect(try queue.read { try String.fetchAll($0, sql: "SELECT title FROM work") } == ["Active library work"])
        try queue.close()
    }

    @Test("a restore intent that exists but cannot be read (stand-in for before first unlock) fails the open and changes nothing")
    func unreadableRestoreIntent() throws {
        let fixture = try makeFixture()
        let layout = fixture.activeLayout
        let plan = try BackupRestorer(layout: layout).prepare(bundle: fixture.bundle)
        let restorer = BackupRestorer(layout: layout)
        // A real intent from a swap interrupted after the active library was moved aside.
        #expect(throws: BackupError.simulatedCrash(RestoreStep.activeMovedAside.rawValue)) {
            _ = try restorer.commit(plan, confirmation: .replaceExistingLibrary, activeStore: fixture.active,
                                    hooks: RestoreHooks(crashAfter: .activeMovedAside))
        }
        // Mode 000 makes the read fail the way a class-C file does before first unlock (on a device the
        // cause is protection, not permissions; see device checklist step 4).
        #expect(chmod(layout.restoreIntentURL.path, 0) == 0)
        defer { _ = chmod(layout.restoreIntentURL.path, 0o600) }
        let restoreWorkBefore = try treeFingerprint(layout.restoreWorkDirectory)
        let rootBefore = try FileManager.default.contentsOfDirectory(atPath: layout.root.path).sorted()
        #expect { _ = try LibraryStore.open(layout) } throws: { error in
            guard case StoreError.invalid(let why) = error else { return false }
            evidence("unreadable restore intent: open refused: \(why)")
            return why.contains("cannot be read")
        }
        // Nothing created an empty Library/ and the validated restored library is still waiting.
        #expect(!FileManager.default.fileExists(atPath: layout.libraryDirectory.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: layout.root.path).sorted() == rootBefore)
        #expect(try treeFingerprint(layout.restoreWorkDirectory) == restoreWorkBefore)
        // Once readable again (after unlock), the next open completes the restore.
        #expect(chmod(layout.restoreIntentURL.path, 0o600) == 0)
        let store = try LibraryStore.open(layout)
        defer { try? store.close() }
        #expect(store.openReport.restoreReconciliation == .completedRestore)
        #expect(try store.pool.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM work") } == 3)
    }

    @Test("an installation record that exists but cannot be read or decoded is an error, never a new device identity",
          arguments: ["unreadable", "garbage"])
    func installationRecordProblems(kind: String) throws {
        let scratch = try Scratch()
        let layout = scratch.layout()
        let first = try LibraryStore.open(layout)
        let originalID = first.deviceID
        try first.close()
        if kind == "garbage" {
            try Data("{ not a record".utf8).write(to: layout.installationURL)
        } else {
            #expect(chmod(layout.installationURL.path, 0) == 0)
        }
        defer { _ = chmod(layout.installationURL.path, 0o600) }
        let bytesBefore = kind == "garbage" ? try Data(contentsOf: layout.installationURL) : nil
        #expect { _ = try LibraryStore.open(layout) } throws: { error in
            guard case StoreError.invalid(let why) = error else { return false }
            evidence("installation record \(kind): open refused: \(why)")
            return why.contains("installation.json")
        }
        #expect(chmod(layout.installationURL.path, 0o600) == 0)
        if let bytesBefore {
            #expect(try Data(contentsOf: layout.installationURL) == bytesBefore, "the record must not be replaced")
        } else {
            let reopened = try LibraryStore.open(layout)
            #expect(reopened.deviceID == originalID)
            try reopened.close()
        }
    }

    @Test("reconcile rolls back to the pre-restore copy if both libraries are missing")
    func rollbackToPreRestore() throws {
        let fixture = try makeFixture()
        let restorer = BackupRestorer(layout: fixture.activeLayout)
        let plan = try restorer.prepare(bundle: fixture.bundle)
        #expect(throws: BackupError.self) {
            _ = try restorer.commit(plan, confirmation: .replaceExistingLibrary, activeStore: fixture.active,
                                    hooks: RestoreHooks(crashAfter: .activeMovedAside))
        }
        // Simulate the restored copy being lost (e.g. a cleanup ran) before the next launch.
        try FileManager.default.removeItem(at: plan.workDirectory)
        let store = try LibraryStore.open(fixture.activeLayout)
        defer { try? store.close() }
        #expect(store.openReport.restoreReconciliation == .rolledBackToPreRestoreCopy)
        #expect(try store.pool.read { try String.fetchAll($0, sql: "SELECT title FROM work") } == ["Active library work"])
    }
}
