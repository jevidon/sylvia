import CryptoKit
import Foundation
import Testing
import SylviaTransferCore
@testable import SylviaTransferClient

@Suite("Part staging store (15.4, 15.5)")
struct StagingStoreTests {
    static let mib = Int(TransferProtocol.mebibyte)

    let root: URL = FileManager.default.temporaryDirectory.appendingPathComponent("staging-\(UUID().uuidString)")

    static func bytes(_ seed: UInt8, _ count: Int) -> [UInt8] {
        (0..<count).map { UInt8(truncatingIfNeeded: $0 &* 131 &+ Int(seed)) }
    }

    static func asset(id: String, data: [UInt8]) -> TransferManifest.Asset {
        let parts = PartPlan.slices(length: Int64(data.count), partSize: TransferProtocol.mebibyte).map {
            TransferManifest.Part(
                index: $0.index, offset: $0.offset, length: $0.length,
                sha256: SHA256Hex.digest(data[Int($0.offset)..<Int($0.offset + $0.length)]))
        }
        let digest = SHA256Hex.digest(data)
        return .init(
            assetID: id, ordinal: 0, displayName: "a.bin", mediaType: "application/octet-stream", length: Int64(data.count),
            etag: ETag.forContentDigest(digest), sha256: digest, partSize: TransferProtocol.mebibyte, parts: parts)
    }

    func incoming(_ store: PartStagingStore, _ data: [UInt8], _ part: TransferManifest.Part) throws -> URL {
        let url = store.incomingDirectory.appendingPathComponent("p\(part.index)-\(UUID().uuidString)")
        try Data(data[Int(part.offset)..<Int(part.offset + part.length)]).write(to: url)
        return url
    }

    @Test func commitsVerifiedPartsAndFinalizes() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Self.bytes(1, 3 * Self.mib + 99)
        let asset = Self.asset(id: CanonicalID.make(), data: data)
        var (store, reconciliation) = try PartStagingStore.open(root: root, asset: asset, itemVersionID: CanonicalID.make(), verifyExistingParts: true)
        #expect(reconciliation == .init(keptParts: 0, discardedParts: 0))
        // Sparse, preallocated: full length on disk before any part arrives.
        #expect((try FileManager.default.attributesOfItem(atPath: store.stagingURL.path)[.size] as? NSNumber)?.int64Value == asset.length)
        for part in asset.parts.reversed() {  // order does not matter
            try store.commit(part: part, from: incoming(store, data, part))
        }
        #expect(store.verifiedBytes == asset.length)
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.incomingDirectory.path).isEmpty)
        let url = try store.finalize()
        #expect(try Data(contentsOf: url) == Data(data))
        #expect(!FileManager.default.fileExists(atPath: store.stagingURL.path))
    }

    @Test func stopBetweenFinalMoveAndJournalKeepsTheVerifiedParts() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Self.bytes(7, 2 * Self.mib + 5)
        let asset = Self.asset(id: CanonicalID.make(), data: data)
        let version = CanonicalID.make()
        do {
            var (store, _) = try PartStagingStore.open(root: root, asset: asset, itemVersionID: version, verifyExistingParts: true)
            for part in asset.parts { try store.commit(part: part, from: incoming(store, data, part)) }
            // The process stops after finalize's rename but before its journal write.
            try FileManager.default.moveItem(at: store.stagingURL, to: store.verifiedURL)
        }
        var (reopened, reconciliation) = try PartStagingStore.open(root: root, asset: asset, itemVersionID: version, verifyExistingParts: true)
        #expect(reconciliation == .init(keptParts: asset.parts.count, discardedParts: 0))
        #expect(!reopened.isFinalVerified)  // not handed off until the full digest is checked again
        let url = try reopened.finalize()
        #expect(try Data(contentsOf: url) == Data(data))
    }

    @Test func refusesBytesThatDoNotMatchThePart() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Self.bytes(2, 2 * Self.mib)
        let asset = Self.asset(id: CanonicalID.make(), data: data)
        var (store, _) = try PartStagingStore.open(root: root, asset: asset, itemVersionID: CanonicalID.make(), verifyExistingParts: true)
        var corrupt = data
        corrupt[10] ^= 0xff
        #expect(throws: StagingError.digestMismatchOnCommit) {
            try store.commit(part: asset.parts[0], from: incoming(store, corrupt, asset.parts[0]))
        }
        #expect(!store.isVerified(0))
        // A short body is refused too.
        let short = store.incomingDirectory.appendingPathComponent("short")
        try Data(data[0..<100]).write(to: short)
        #expect(throws: StagingError.digestMismatchOnCommit) { try store.commit(part: asset.parts[0], from: short) }
        #expect(throws: StagingError.incomplete) { try store.finalize() }
    }

    @Test func resumeKeepsVerifiedPartsAndDropsUnverifiedIncoming() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Self.bytes(3, 4 * Self.mib)
        let asset = Self.asset(id: CanonicalID.make(), data: data)
        let version = CanonicalID.make()
        do {
            var (store, _) = try PartStagingStore.open(root: root, asset: asset, itemVersionID: version, verifyExistingParts: true)
            try store.commit(part: asset.parts[0], from: incoming(store, data, asset.parts[0]))
            try store.commit(part: asset.parts[2], from: incoming(store, data, asset.parts[2]))
            // A body that was arriving when the "process stopped".
            _ = try incoming(store, data, asset.parts[1])
        }
        let (reopened, reconciliation) = try PartStagingStore.open(root: root, asset: asset, itemVersionID: version, verifyExistingParts: true)
        #expect(reconciliation == .init(keptParts: 2, discardedParts: 0))
        #expect(reopened.isVerified(0) && reopened.isVerified(2) && !reopened.isVerified(1))
        #expect(try FileManager.default.contentsOfDirectory(atPath: reopened.incomingDirectory.path).isEmpty)
    }

    @Test func resumeDetectsDamagedOrMissingStagedBytes() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Self.bytes(4, 3 * Self.mib)
        let asset = Self.asset(id: CanonicalID.make(), data: data)
        let version = CanonicalID.make()
        var (store, _) = try PartStagingStore.open(root: root, asset: asset, itemVersionID: version, verifyExistingParts: true)
        for part in asset.parts { try store.commit(part: part, from: incoming(store, data, part)) }
        // Damage part 1 on disk.
        let handle = try FileHandle(forUpdating: store.stagingURL)
        try handle.seek(toOffset: UInt64(Self.mib + 5))
        try handle.write(contentsOf: Data([0x00, 0x01]))
        try handle.close()
        let (checked, reconciliation) = try PartStagingStore.open(root: root, asset: asset, itemVersionID: version, verifyExistingParts: true)
        #expect(reconciliation.keptParts == 2)
        #expect(checked.isVerified(0) && !checked.isVerified(1) && checked.isVerified(2))
        // Staging file deleted behind our back: nothing counts any more.
        try FileManager.default.removeItem(at: checked.stagingURL)
        let (empty, emptied) = try PartStagingStore.open(root: root, asset: asset, itemVersionID: version, verifyExistingParts: false)
        #expect(emptied.keptParts == 0 && empty.verifiedPartCount == 0)
    }

    @Test func versionChangeKeepsOnlyIdenticalParts() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let id = CanonicalID.make()
        let old = Self.bytes(5, 4 * Self.mib)
        var new = old
        new[2 * Self.mib + 7] ^= 0x55  // only part 2 differs
        let oldAsset = Self.asset(id: id, data: old)
        let newAsset = Self.asset(id: id, data: new)
        var (store, _) = try PartStagingStore.open(root: root, asset: oldAsset, itemVersionID: CanonicalID.make(), verifyExistingParts: true)
        for part in oldAsset.parts { try store.commit(part: part, from: incoming(store, old, part)) }
        var (updated, reconciliation) = try PartStagingStore.open(root: root, asset: newAsset, itemVersionID: CanonicalID.make(), verifyExistingParts: true)
        #expect(reconciliation == .init(keptParts: 3, discardedParts: 1))
        #expect(!updated.isVerified(2))
        try updated.commit(part: newAsset.parts[2], from: incoming(updated, new, newAsset.parts[2]))
        let url = try updated.finalize()
        let result = try Data(contentsOf: url)
        #expect(result == Data(new))
        #expect(result != Data(old))
    }

    @Test func finalDigestMismatchHandsNothingOff() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Self.bytes(6, 2 * Self.mib)
        var asset = Self.asset(id: CanonicalID.make(), data: data)
        asset.sha256 = String(repeating: "0", count: 64)  // a manifest whose full digest disagrees with its parts
        var (store, _) = try PartStagingStore.open(root: root, asset: asset, itemVersionID: CanonicalID.make(), verifyExistingParts: true)
        for part in asset.parts { try store.commit(part: part, from: incoming(store, data, part)) }
        #expect(throws: StagingError.finalDigestMismatch) { try store.finalize() }
        #expect(!FileManager.default.fileExists(atPath: store.verifiedURL.path))
        #expect(store.verifiedPartCount == 0)
    }

    @Test func inMemoryCredentialStore() throws {
        let store = InMemoryCredentialStore()
        try store.saveToken("t1", sourceID: "s")
        #expect(try store.token(sourceID: "s") == "t1")
        try store.deleteToken(sourceID: "s")
        #expect(try store.token(sourceID: "s") == nil)
    }
    // The Keychain store is tested hosted on the iOS simulator (Spikes/G02-Transfer/iOS), because a
    // hostless test bundle has no keychain access group there (errSecMissingEntitlement, -34018).
}
