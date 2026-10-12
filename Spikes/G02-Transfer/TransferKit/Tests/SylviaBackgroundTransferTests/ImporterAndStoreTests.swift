import Foundation
import Testing
import SylviaTransferCore
@testable import SylviaBackgroundTransfer

struct StopHere: Error {}

@Suite("Stub importer: exactly-once handoff (T38 single import)")
struct StubImporterTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("importer-\(UUID().uuidString)")

    func verifiedFiles(_ count: Int) throws -> [StubImporter.VerifiedAsset] {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("staging"), withIntermediateDirectories: true)
        return try (0..<count).map { index in
            let data = Data((0..<(1000 + index)).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ index) })
            let url = root.appendingPathComponent("staging/verified-\(index).bin")
            try data.write(to: url)
            return .init(assetID: CanonicalID.make(), url: url, sha256: SHA256Hex.digest(data), length: Int64(data.count))
        }
    }

    @Test func importsOnceAndCountsLaterCallsAsDuplicates() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let assets = try verifiedFiles(2)
        let importer = try StubImporter(root: root)
        let version = CanonicalID.make()
        guard case .imported(let record) = try importer.importVerified(jobID: CanonicalID.make(), itemID: CanonicalID.make(), itemVersionID: version, assets: assets) else {
            Issue.record("first call did not import")
            return
        }
        #expect(record.completions == 1)
        for asset in assets {
            let moved = importer.destination(importID: record.importID, assetID: asset.assetID)
            #expect(SHA256Hex.digest(try Data(contentsOf: moved)) == asset.sha256)
            #expect(!FileManager.default.fileExists(atPath: asset.url.path))
        }
        // A second call (a relaunch that saw "ready for import" again) changes nothing.
        guard case .alreadyImported(let again) = try importer.importVerified(jobID: CanonicalID.make(), itemID: CanonicalID.make(), itemVersionID: version, assets: assets) else {
            Issue.record("second call imported again")
            return
        }
        #expect(again.importID == record.importID && again.completions == 1 && again.duplicateRequests == 1)
        // A fresh importer reading the ledger from disk agrees.
        let reopened = try StubImporter(root: root)
        #expect(reopened.records.count == 1)
        #expect(reopened.record(itemVersionID: version)?.completions == 1)
    }

    @Test(arguments: ["after_intent", "after_move:first"])
    func aStopAtAnyPointIsCompletedByTheNextCallExactlyOnce(_ point: String) throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let assets = try verifiedFiles(2)
        let stopAt = point == "after_move:first" ? "after_move:\(assets[0].assetID)" : point
        let version = CanonicalID.make()
        do {
            let importer = try StubImporter(root: root)
            importer.setStopHook { name in if name == stopAt { throw StopHere() } }
            #expect(throws: StubImporter.ImportError.self) {
                _ = try importer.importVerified(jobID: CanonicalID.make(), itemID: CanonicalID.make(), itemVersionID: version, assets: assets)
            }
            #expect(importer.record(itemVersionID: version)?.state == .importing)
        }
        // "Relaunch": a new importer from the ledger on disk; the caller still points at the old file locations.
        let importer = try StubImporter(root: root)
        guard case .imported(let record) = try importer.importVerified(jobID: CanonicalID.make(), itemID: CanonicalID.make(), itemVersionID: version, assets: assets) else {
            Issue.record("recovery did not complete the import")
            return
        }
        #expect(record.completions == 1 && record.state == .imported)
        for asset in assets {
            #expect(SHA256Hex.digest(try Data(contentsOf: importer.destination(importID: record.importID, assetID: asset.assetID))) == asset.sha256)
        }
        let libraryFolders = try FileManager.default.contentsOfDirectory(atPath: importer.libraryRoot.path)
        #expect(libraryFolders == [record.importID])  // one import, not two
    }

    @Test func missingVerifiedFileIsAnErrorNotAnEmptyImport() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        var assets = try verifiedFiles(1)
        try FileManager.default.removeItem(at: assets[0].url)
        assets[0].url = root.appendingPathComponent("staging/missing.bin")
        let importer = try StubImporter(root: root)
        #expect(throws: StubImporter.ImportError.missingVerifiedFile(assetID: assets[0].assetID)) {
            _ = try importer.importVerified(jobID: CanonicalID.make(), itemID: CanonicalID.make(), itemVersionID: CanonicalID.make(), assets: assets)
        }
    }
}

@Suite("Job store and durable files")
struct JobStoreTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("jobs-\(UUID().uuidString)")

    @Test func jobsRoundTripAndUnreadableFoldersAreReportedNotDeleted() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try JobStore(root: root)
        var job = JobRecord(
            jobID: CanonicalID.make(), sourceID: CanonicalID.make(), itemID: CanonicalID.make(), title: "Walden",
            itemVersionID: CanonicalID.make(), now: Date(timeIntervalSince1970: 1_790_000_000))
        job.failedAttempts["x:1"] = 2
        try store.save(job)
        let broken = CanonicalID.make()
        try FileManager.default.createDirectory(at: store.directory(broken), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: store.directory(broken).appendingPathComponent("job.json"))
        let loaded = store.loadAll()
        #expect(loaded.jobs == [job])
        #expect(loaded.unreadable == [broken])
        #expect(loaded.inaccessible.isEmpty)
        #expect(FileManager.default.fileExists(atPath: store.directory(broken).path))
        // No temporary files are left next to the record.
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.directory(job.jobID).path) == ["job.json"])
    }
}
