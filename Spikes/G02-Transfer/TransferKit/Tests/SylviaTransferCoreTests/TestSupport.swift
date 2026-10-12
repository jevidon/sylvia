import CryptoKit
import Foundation
import SylviaTransferCore

enum TestPaths {
    /// Repository root, from this file's location (Spikes/G02-Transfer/TransferKit/Tests/SylviaTransferCoreTests/).
    static let repositoryRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        return url
    }()

    static let contractFixtures = repositoryRoot.appendingPathComponent("Contracts/fixtures")

    static var bundledFixtures: URL {
        Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
    }

    static func jsonFiles(in directory: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

/// Builds manifests over deterministic bytes for tests.
enum ManifestFactory {
    static let sourceID = "5a1e0c3e-7d2b-4c1a-9f00-000000000001"
    static let mib = TransferProtocol.mebibyte

    static func bytes(seed: UInt8, count: Int) -> [UInt8] {
        (0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ Int(seed)) }
    }

    static func asset(
        id: String = CanonicalID.make(), ordinal: Int = 0, data: [UInt8], partSize: Int64 = TransferProtocol.mebibyte,
        name: String = "book.epub", mediaType: String = "application/epub+zip"
    ) -> TransferManifest.Asset {
        let parts = PartPlan.slices(length: Int64(data.count), partSize: partSize).map { slice in
            TransferManifest.Part(
                index: slice.index, offset: slice.offset, length: slice.length,
                sha256: SHA256Hex.digest(data[Int(slice.offset)..<Int(slice.offset + slice.length)]))
        }
        let digest = SHA256Hex.digest(data)
        return TransferManifest.Asset(
            assetID: id, ordinal: ordinal, displayName: name, mediaType: mediaType, length: Int64(data.count),
            etag: ETag.forContentDigest(digest), sha256: digest, partSize: partSize, parts: parts)
    }

    static func manifest(
        itemID: String = CanonicalID.make(), kind: ItemKind = .single, assets: [TransferManifest.Asset],
        cover: String? = nil
    ) -> TransferManifest {
        TransferManifest(
            sourceID: sourceID, itemID: itemID, itemVersionID: CanonicalID.make(),
            createdAt: Date(timeIntervalSince1970: 1_790_000_000), grouping: .init(kind: kind, title: "Walden"),
            coverAssetID: cover, assets: assets)
    }

    /// Applies a change and recomputes the digest, so only the semantic rule under test can fail.
    static func resealed(_ manifest: TransferManifest, _ change: (inout TransferManifest) -> Void) -> TransferManifest {
        var copy = manifest
        change(&copy)
        copy.manifestDigest = copy.computedDigest()
        return copy
    }
}
