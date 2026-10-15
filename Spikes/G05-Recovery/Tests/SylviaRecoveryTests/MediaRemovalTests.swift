import Foundation
import GRDB
import Testing
@testable import SylviaRecovery

@Suite("Media removal keeps knowledge (I-02, T44, plan 12, 17.2)")
struct MediaRemovalTests {
    @Test("removing all original media for a work keeps ledger, rating, recommendations, quotes, notes, excerpts and AI evidence")
    func removeAllMedia() throws {
        let scratch = try Scratch()
        let (store, corpus) = try corpusLibrary(scratch)
        defer { try? store.close() }
        let media = MediaService(store)
        let work = corpus.works["meditations"]!
        let before = try store.pool.read { try LibraryChecks.knowledgeDump($0) }

        let impact = try media.removalImpact(workID: work)
        evidence("impact report for Meditations: \(impact)")
        #expect(impact.assetCount == 4)
        #expect(impact.bytesFreed == 1_572_864 + 3_145_728 + 2_621_440 + 524_288)
        #expect(impact.captures == 3 && impact.excerptsPreserved == 1 && impact.excerptsPending == 0)
        #expect(impact.recommendations == 2 && impact.hasRating && impact.contextEvidence == 1 && impact.ledgerEvents >= 5)

        try media.removeAllOriginalMedia(workID: work)

        #expect(try store.pool.read { try LibraryChecks.knowledgeDump($0) } == before, "knowledge rows changed")
        try store.pool.read { (db: Database) throws in
            #expect(try LibraryChecks.foreignKeyViolations(db).isEmpty)
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM asset") == corpus.assets.count, "asset identities must remain")
        }
        // Unavailable, not corrupt: each asset resolves to a state, none throws.
        #expect(try media.availability(assetID: corpus.assets["med-epub"]!) == .recordOnly)
        #expect(try media.availability(assetID: corpus.assets["med-pdf"]!) == .recordOnly)
        #expect(try media.availability(assetID: corpus.assets["med-audio-1"]!) == .atSource(sourceKind: "mac_source"))
        // Another work's media is untouched.
        guard case .onDevice = try media.availability(assetID: corpus.assets["walden-epub"]!) else {
            Issue.record("Walden EPUB should still be on the device"); return
        }
        for key in ["med-epub", "med-audio-1", "med-audio-2", "med-pdf"] {
            #expect(!FileManager.default.fileExists(atPath: store.layout.mediaDirectory.appending(path: corpus.assets[key]!).path))
        }
        // The retained excerpt is permanent knowledge and stays.
        let blob = BlobStore(store).url(sha256: corpus.excerptSHA256, fileExtension: "mp3")
        #expect(try Digest.sha256Hex(fileAt: blob).digest == corpus.excerptSHA256)
        #expect(try BlobStore(store).collectGarbage().removed.isEmpty)
    }

    @Test("a pending excerpt blocks removal unless the user chooses to remove anyway (T23 guard)")
    func pendingExcerptGuard() throws {
        let scratch = try Scratch()
        let (store, corpus) = try corpusLibrary(scratch)
        defer { try? store.close() }
        try store.pool.write { try $0.execute(sql: "UPDATE retained_excerpt SET export_state = 'pending'") }
        let media = MediaService(store)
        let work = corpus.works["meditations"]!
        #expect(throws: StoreError.excerptsPending(count: 1)) { try media.removeAllOriginalMedia(workID: work) }
        guard case .onDevice = try media.availability(assetID: corpus.assets["med-audio-1"]!) else {
            Issue.record("refused removal must not change availability"); return
        }
        try media.removeAllOriginalMedia(workID: work, policy: .removeAnyway)
        #expect(try media.availability(assetID: corpus.assets["med-audio-1"]!) == .atSource(sourceKind: "mac_source"))
    }

    @Test("re-importing the same bytes restores availability without a duplicate asset or work (J-04)")
    func reimport() throws {
        let scratch = try Scratch()
        let (store, corpus) = try corpusLibrary(scratch)
        defer { try? store.close() }
        let media = MediaService(store)
        try media.removeAllOriginalMedia(workID: corpus.works["walden"]!)
        #expect(try media.availability(assetID: corpus.assets["walden-epub"]!) == .recordOnly)
        let copy = scratch.url.appending(path: "walden-again.epub")
        try DeterministicBytes.make(seed: 5, count: 1_048_576).write(to: copy)
        let assetID = try media.importOriginal(copy, editionID: corpus.editions["walden-epub"]!, role: "primary", sequence: 0,
                                               mediaType: "application/epub+zip")
        #expect(assetID == corpus.assets["walden-epub"]!)
        guard case .onDevice = try media.availability(assetID: assetID) else { Issue.record("should be on device"); return }
        try store.pool.read { (db: Database) throws in
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM asset") == corpus.assets.count)
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM work") == corpus.works.count)
        }
    }

    @Test("a file deleted behind the library's back reads as unavailable; orphan media is swept")
    func driftAndOrphans() throws {
        let scratch = try Scratch()
        let (store, corpus) = try corpusLibrary(scratch)
        defer { try? store.close() }
        let media = MediaService(store)
        let pdfDir = store.layout.mediaDirectory.appending(path: corpus.assets["med-pdf"]!, directoryHint: .isDirectory)
        try FileManager.default.removeItem(at: pdfDir)
        #expect(try media.availability(assetID: corpus.assets["med-pdf"]!) == .recordOnly)
        // Crash between the availability commit and file deletion leaves an orphan directory.
        let orphan = store.layout.mediaDirectory.appending(path: EntityID.make(), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: orphan.appending(path: "f.bin"))
        let swept = try media.sweepOrphanMedia()
        #expect(swept == [orphan.lastPathComponent])
        guard case .onDevice = try media.availability(assetID: corpus.assets["med-epub"]!) else { Issue.record("on-device media must survive the sweep"); return }
    }
}
