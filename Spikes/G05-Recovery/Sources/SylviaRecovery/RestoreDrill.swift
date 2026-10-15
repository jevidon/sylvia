import Foundation
import GRDB

/// The G0.5 restore drill (T35, J-06): build a golden corpus, delete the source media, export,
/// reset the installation, restore, and compare everything that must survive.
public enum RestoreDrill {
    public struct Report: Sendable, CustomStringConvertible {
        public var checks: [(name: String, passed: Bool, detail: String)] = []
        public var failures: [String] { checks.filter { !$0.passed }.map { "\($0.name): \($0.detail)" } }
        mutating func check(_ name: String, _ passed: Bool, _ detail: String = "") {
            checks.append((name, passed, detail))
        }
        public var description: String {
            checks.map { "\($0.passed ? "PASS" : "FAIL") \($0.name)\($0.detail.isEmpty ? "" : " — \($0.detail)")" }
                .joined(separator: "\n")
        }
    }

    /// Canary values standing in for Keychain items (provider key, pairing token). They are written
    /// beside the library, where a careless exporter could pick them up, and must not appear in the
    /// bundle. This proves the exporter does not copy them; it cannot prove the absence of secrets
    /// the drill does not know about.
    public static let secretCanaries = ["sk-SYLVIA-CANARY-provider-key-7f3a9c", "pair-SYLVIA-CANARY-token-41d2e8"]

    public static func run(workDirectory: URL, log: (String) -> Void = { _ in }) throws -> Report {
        var report = Report()
        let fm = FileManager.default
        try? fm.removeItem(at: workDirectory)
        try fm.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        let installRoot = workDirectory.appending(path: "Install", directoryHint: .isDirectory)
        let layout = LibraryLayout(root: installRoot)
        let macSource = workDirectory.appending(path: "MacSource", directoryHint: .isDirectory)
        let exports = workDirectory.appending(path: "Exports", directoryHint: .isDirectory)
        try fm.createDirectory(at: exports, withIntermediateDirectories: true)

        // 1. Golden corpus.
        var store = try LibraryStore.open(layout)
        let corpus = try GoldenCorpus.build(in: store, sourceDirectory: macSource)
        let secretsFile = installRoot.appending(path: "keychain-standin.json", directoryHint: .notDirectory)
        try Data(#"{"provider_key":"\#(secretCanaries[0])","pairing_token":"\#(secretCanaries[1])"}"#.utf8).write(to: secretsFile)
        let before = try store.pool.read { db in
            (dump: try LibraryChecks.knowledgeDump(db), counts: try LibraryChecks.counts(db))
        }
        let sourceDeviceID = store.deviceID
        log("corpus: \(before.counts.filter { LibrarySchema.knowledgeTables.contains($0.key) }.values.reduce(0, +)) knowledge rows")
        report.check("corpus has every knowledge table populated",
                     LibrarySchema.knowledgeTables.allSatisfy { (before.counts[$0] ?? 0) > 0 },
                     LibrarySchema.knowledgeTables.filter { (before.counts[$0] ?? 0) == 0 }.joined(separator: ", "))

        // 2. Delete the source media: remove every original from the library, then the source itself.
        let media = MediaService(store)
        for workID in corpus.works.values.sorted() { try media.removeAllOriginalMedia(workID: workID) }
        try fm.removeItem(at: macSource)
        let afterRemoval = try store.pool.read { try LibraryChecks.knowledgeDump($0) }
        report.check("media removal leaves every knowledge row unchanged (T44)", afterRemoval == before.dump)
        let onDevice = try store.pool.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM asset_location WHERE availability = 'on_device'") ?? -1 }
        report.check("no asset is on the device after removal", onDevice == 0, "\(onDevice) on device")
        let mediaLeft = try fm.contentsOfDirectory(atPath: layout.mediaDirectory.path)
        report.check("Media directory is empty after removal", mediaLeft.isEmpty, mediaLeft.joined(separator: ", "))

        // 3. Export.
        let bundle = exports.appending(path: "Sylvia-drill.sylviabackup", directoryHint: .isDirectory)
        let exported = try BackupExporter(store).export(to: bundle)
        report.check("export bundle validates", (try? BackupValidator.validate(bundle)) != nil)
        report.check("manifest lists every original as excluded media and does not claim completeness",
                     exported.manifest.excluded_media.count == corpus.assets.count && !exported.manifest.complete,
                     "\(exported.manifest.excluded_media.count) excluded, complete=\(exported.manifest.complete)")
        report.check("manifest originating device is the source installation", exported.manifest.originating_device_id == sourceDeviceID)
        let coverFiles = exported.manifest.files.filter { $0.role == .cover_thumbnail }.map(\.sha256).sorted()
        report.check("bundle holds every canonical cover thumbnail after source deletion", !coverFiles.isEmpty
                        && coverFiles == corpus.covers.values.map(\.sha256).sorted(), "\(coverFiles.count) covers")
        var bundleBytes = Data()
        for case let url as URL in fm.enumerator(at: bundle, includingPropertiesForKeys: nil)! where !url.hasDirectoryPath {
            bundleBytes.append(try Data(contentsOf: url))
        }
        for canary in secretCanaries {
            report.check("secret canary absent from bundle", bundleBytes.range(of: Data(canary.utf8)) == nil, String(canary.prefix(12)) + "…")
        }
        report.check("no absolute installation path in bundle", bundleBytes.range(of: Data(installRoot.path.utf8)) == nil)
        try store.close()

        // 4. Reset: the installation is erased (as after deleting the app), then reinstalled.
        try fm.removeItem(at: installRoot)
        store = try LibraryStore.open(layout)
        let freshCount = try store.pool.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM work") ?? -1 }
        report.check("fresh installation starts empty", freshCount == 0)

        // 5. Restore: prepare in a temporary library, then replace with confirmation.
        let restorer = BackupRestorer(layout: layout)
        let plan = try restorer.prepare(bundle: bundle)
        report.check("restore without confirmation is refused",
                     (try? restorer.commit(plan, confirmation: nil, activeStore: nil)) == nil)
        let restored = try restorer.commit(plan, confirmation: .replaceExistingLibrary, activeStore: store)
        store = restored.store
        defer { try? store.close() }

        // 6. Verify.
        let after = try store.pool.read { db in
            (dump: try LibraryChecks.knowledgeDump(db), counts: try LibraryChecks.counts(db),
             integrity: try LibraryChecks.integrity(db), fk: try LibraryChecks.foreignKeyViolations(db))
        }
        report.check("integrity_check ok after restore", after.integrity == ["ok"], after.integrity.joined(separator: "; "))
        report.check("foreign_key_check clean after restore", after.fk.isEmpty, "\(after.fk.count) violations")
        for table in LibrarySchema.knowledgeTables {
            report.check("count \(table)", after.counts[table] == before.counts[table],
                         "before \(before.counts[table] ?? -1), after \(after.counts[table] ?? -1)")
        }
        report.check("every knowledge row restored byte-for-byte (works, editions, anchors, notes and revisions, ledger, rating, recommendations, captures, excerpts, conversations, context evidence)",
                     after.dump == before.dump, firstDifference(before.dump, after.dump))
        report.check("restored dump digest equals source", Digest.sha256Hex(after.dump) == Digest.sha256Hex(before.dump),
                     Digest.sha256Hex(after.dump))

        let blob = BlobStore(store).url(sha256: corpus.excerptSHA256, fileExtension: corpus.excerptExtension)
        let blobDigest = (try? Digest.sha256Hex(fileAt: blob))?.digest
        report.check("retained excerpt audio restored with its digest", blobDigest == corpus.excerptSHA256)

        var coverDetail: [String] = []
        var coversOK = !corpus.covers.isEmpty
        for (key, cover) in corpus.covers.sorted(by: { $0.key < $1.key }) {
            let url = CoverStore.url(store.layout, sha256: cover.sha256, fileExtension: cover.fileExtension)
            let digest = (try? Digest.sha256Hex(fileAt: url))?.digest
            let pointer = try store.pool.read { db in
                try String.fetchOne(db, sql: "SELECT cover_thumbnail_sha256 FROM edition WHERE id = ?", arguments: [corpus.editions[key]!])
            }
            coversOK = coversOK && digest == cover.sha256 && pointer == cover.sha256
            coverDetail.append("\(key)=\(cover.fileExtension) \(digest == cover.sha256 ? "digest ok" : "digest wrong or missing")")
        }
        report.check("canonical cover thumbnails restored with their digests and edition references (plan 17.3)", coversOK,
                     coverDetail.joined(separator: "; "))

        let restoredMedia = MediaService(store)
        var availability: [String] = []
        var allUnavailable = true
        for (key, assetID) in corpus.assets.sorted(by: { $0.key < $1.key }) {
            let state = try restoredMedia.availability(assetID: assetID)
            switch state {
            case .onDevice: allUnavailable = false; availability.append("\(key)=on device")
            case .atSource(let kind): availability.append("\(key)=not on this device · from \(kind)")
            case .recordOnly: availability.append("\(key)=record only")
            }
        }
        report.check("missing originals resolve as unavailable records, not errors", allUnavailable, availability.joined(separator: "; "))

        let anchorsOK = try store.pool.read { db in
            try Int.fetchOne(db, sql: """
                SELECT count(*) FROM capture_anchor a JOIN asset s ON s.id = a.asset_id WHERE a.asset_sha256 <> s.sha256
                """) == 0
        }
        report.check("every anchor still binds to its asset digest", anchorsOK)
        let remoteBytes = try store.pool.read { try Int64.fetchOne($0, sql: "SELECT byte_count FROM asset WHERE id = ?", arguments: [corpus.assets["walden-audio"]!]) }
        report.check("64-bit asset size survives (5 GiB + 7)", remoteBytes == corpus.remoteAssetBytes, "\(remoteBytes ?? -1)")

        let markdownDir = bundle.appending(path: "export/markdown", directoryHint: .isDirectory)
        var markdown = ""
        for name in try fm.contentsOfDirectory(atPath: markdownDir.path).sorted() {
            markdown += try String(contentsOf: markdownDir.appending(path: name, directoryHint: .notDirectory), encoding: .utf8)
        }
        let quotesInMarkdown = corpus.quotes.values.allSatisfy { quote in
            markdown.contains(quote.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n"))
        }
        report.check("Markdown export contains every quote exactly", quotesInMarkdown)
        let currentNotes = try store.pool.read { db in
            try String.fetchAll(db, sql: """
                SELECT r.body FROM note n JOIN note_revision r ON r.note_id = n.id AND r.revision = n.current_revision WHERE n.trashed_at_ms IS NULL
                """)
        }
        report.check("Markdown export contains every current note", currentNotes.allSatisfy { markdown.contains($0) }, "\(currentNotes.count) notes")
        let (messages, evidenceTexts) = try store.pool.read { db in
            (try String.fetchAll(db, sql: "SELECT content FROM message"), try String.fetchAll(db, sql: "SELECT text FROM context_evidence"))
        }
        report.check("Markdown export contains every conversation message", !messages.isEmpty && messages.allSatisfy { markdown.contains($0) },
                     "\(messages.count) messages")
        report.check("Markdown export contains every context evidence text", !evidenceTexts.isEmpty
                        && evidenceTexts.allSatisfy { markdown.contains(PortableExport.singleLine($0)) }, "\(evidenceTexts.count) evidence items")

        let json = try Data(contentsOf: bundle.appending(path: "export/library.json", directoryHint: .notDirectory))
        report.check("portable JSON alone reproduces every knowledge row", try PortableExport.canonicalDump(fromJSON: json) == before.dump)

        report.check("restored installation keeps its own device identity", store.deviceID != sourceDeviceID)
        let leases = try store.pool.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM retention_lease") ?? -1 }
        report.check("no retention leases carried over", leases == 0)
        var protectionDetail: [String] = []
        var protectionOK = true
        let coverURLs = corpus.covers.sorted { $0.key < $1.key }.map { CoverStore.url(store.layout, sha256: $0.value.sha256, fileExtension: $0.value.fileExtension) }
        for url in [store.layout.databaseURL, store.layout.walURL, store.layout.shmURL, blob] + coverURLs {
            let reported = (try? store.protector.protectionClass(of: url))?.rawValue ?? "none reported"
            protectionDetail.append("\(url.lastPathComponent)=\(reported)")
            do { try store.protector.verify(url) } catch { protectionOK = false }
        }
        if !FileProtector.platformReportsProtection {
            protectionDetail.append("simulator: readback is not faithful, so this is not evidence of protection")
        }
        report.check("restored database, WAL, SHM, excerpt and covers read back the library protection class", protectionOK,
                     protectionDetail.joined(separator: " "))
        return report
    }

    static func firstDifference(_ a: String, _ b: String) -> String {
        let la = a.split(separator: "\n"), lb = b.split(separator: "\n")
        for (x, y) in zip(la, lb) where x != y { return "first difference: \(x.prefix(120)) vs \(y.prefix(120))" }
        return la.count == lb.count ? "" : "line counts \(la.count) vs \(lb.count)"
    }
}
