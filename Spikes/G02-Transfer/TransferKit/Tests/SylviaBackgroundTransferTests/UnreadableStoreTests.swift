import Darwin
import Foundation
import Testing
import SylviaTransferClient
import SylviaTransferCore
@testable import SylviaBackgroundTransfer

/// Review finding R1-04: a store whose file exists but cannot be read (before the first unlock on iOS the
/// file system refuses class C files; here chmod 000 stands in for that on the host) is never taken for an
/// empty store and never written over. Environment: host (macOS), not run as root.
@Suite("Stores that cannot be read (R1-04)")
struct UnreadableStoreTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("stores-\(UUID().uuidString)")

    static func source(_ name: String) -> PairedSource {
        PairedSource(
            sourceID: CanonicalID.make(), sourceName: name, deviceID: CanonicalID.make(), spkiSHA256: String(repeating: "ab", count: 32),
            endpoints: [.init(host: "127.0.0.1", port: 4443)], scopes: [.catalog, .read, .download, .receipt])
    }

    @Test func pairedSourcesThatCannotBeReadAreNeitherListedNorOverwritten() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("sources.json")
        let first = Self.source("Mac A")
        try PairedSourceStore(url: url).upsert(first)
        let bytes = try Data(contentsOf: url)
        #expect(chmod(url.path, 0) == 0)
        defer { chmod(url.path, 0o644) }

        let store = try PairedSourceStore(url: url)
        #expect(store.unreadable == StoreUnreadable(store: "sources.json", reason: "not_accessible"))
        #expect(store.all.isEmpty)
        #expect(throws: StoreUnreadable.self) { try store.upsert(Self.source("Mac B")) }
        #expect(throws: StoreUnreadable.self) { try store.remove(first.sourceID) }
        #expect(chmod(url.path, 0o644) == 0)
        #expect(try Data(contentsOf: url) == bytes, "the unreadable file was written over")

        // Readable again (the first unlock): the store reloads and both writes now keep the earlier pairing.
        #expect(store.reload())
        #expect(store.all == [first])
        try store.upsert(Self.source("Mac B"))
        #expect(try PairedSourceStore(url: url).all.count == 2)
    }

    @Test func damagedSourcesFileIsReportedAndKept() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("sources.json")
        try Data("[{not json".utf8).write(to: url)
        let store = try PairedSourceStore(url: url)
        #expect(store.unreadable?.reason == "damaged")
        #expect(throws: StoreUnreadable.self) { try store.upsert(Self.source("Mac A")) }
        #expect(try Data(contentsOf: url) == Data("[{not json".utf8))
    }

    @Test func importLedgerThatCannotBeReadRefusesToImport() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("verified.bin")
        try Data("verified bytes".utf8).write(to: file)
        let importer = try StubImporter(root: root)
        let version = CanonicalID.make()
        _ = try importer.importVerified(
            jobID: CanonicalID.make(), itemID: CanonicalID.make(), itemVersionID: version,
            assets: [.init(assetID: CanonicalID.make(), url: file, sha256: SHA256Hex.digest(Data("verified bytes".utf8)), length: 14)])
        let ledger = try Data(contentsOf: importer.ledgerURL)
        #expect(chmod(importer.ledgerURL.path, 0) == 0)
        defer { chmod(importer.ledgerURL.path, 0o644) }

        let reopened = try StubImporter(root: root)
        #expect(reopened.isUnreadable)
        #expect(reopened.records.isEmpty)
        let other = root.appendingPathComponent("other.bin")
        try Data("other".utf8).write(to: other)
        #expect(throws: StubImporter.ImportError.ledgerUnreadable) {
            try reopened.importVerified(
                jobID: CanonicalID.make(), itemID: CanonicalID.make(), itemVersionID: CanonicalID.make(),
                assets: [.init(assetID: CanonicalID.make(), url: other, sha256: SHA256Hex.digest(Data("other".utf8)), length: 5)])
        }
        #expect(FileManager.default.fileExists(atPath: other.path), "a file was moved although the ledger could not be read")
        #expect(chmod(importer.ledgerURL.path, 0o644) == 0)
        #expect(try Data(contentsOf: importer.ledgerURL) == ledger)
        #expect(reopened.reload())
        #expect(reopened.record(itemVersionID: version)?.completions == 1)
    }

    @Test func jobRecordThatCannotBeReadIsInaccessibleNotUnreadable() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try JobStore(root: root)
        let job = JobRecord(
            jobID: CanonicalID.make(), sourceID: CanonicalID.make(), itemID: CanonicalID.make(), title: "Walden",
            itemVersionID: CanonicalID.make(), now: Date())
        try store.save(job)
        let url = store.directory(job.jobID).appendingPathComponent("job.json")
        #expect(chmod(url.path, 0) == 0)
        defer { chmod(url.path, 0o644) }
        let loaded = store.loadAll()
        #expect(loaded.jobs.isEmpty && loaded.unreadable.isEmpty)
        #expect(loaded.inaccessible == [job.jobID])
    }

    @Test func outOfSpaceErrorsAreRecognizedInEveryShape() {
        #expect(StagingError.isOutOfSpace(POSIXError(.ENOSPC)))
        #expect(StagingError.isOutOfSpace(POSIXError(.EDQUOT)))
        #expect(StagingError.isOutOfSpace(CocoaError(.fileWriteOutOfSpace)))
        #expect(StagingError.isOutOfSpace(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))))
        let wrapped = NSError(
            domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))])
        #expect(StagingError.isOutOfSpace(wrapped))
        #expect(!StagingError.isOutOfSpace(POSIXError(.EIO)))
        #expect(!StagingError.isOutOfSpace(CocoaError(.fileWriteNoPermission)))
        // Local storage failures never read as a network problem.
        #expect(PartFailure.localStorageFull.recovery == .pause(.insufficientSpace))
        #expect(PartFailure.localWriteFailed("move").recovery == .retryPart)
        #expect(PartFailure.localWriteFailed("move").exhaustedRetriesReason == .storageUnavailable)
        #expect(PartFailure.transport("lost").exhaustedRetriesReason == .sourceUnreachable)
        #expect(PartFailure.digestMismatch.exhaustedRetriesReason == .repeatedPartFailure)
    }
}
