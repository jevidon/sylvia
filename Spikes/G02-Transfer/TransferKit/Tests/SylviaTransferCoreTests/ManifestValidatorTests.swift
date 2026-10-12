import Foundation
import Testing
@testable import SylviaTransferCore

@Suite("Manifest validation (A.3)")
struct ManifestValidatorTests {
    let expectations = ManifestValidator.Expectations(sourceID: ManifestFactory.sourceID)
    let valid = ManifestFactory.manifest(
        assets: [ManifestFactory.asset(data: ManifestFactory.bytes(seed: 7, count: Int(2 * TransferProtocol.mebibyte + 12_345)))])

    func rejects(_ manifest: TransferManifest, _ expected: ManifestError, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(throws: expected, sourceLocation: sourceLocation) {
            try ManifestValidator.validate(manifest, expecting: expectations)
        }
    }

    @Test func acceptsValidSingleAndGroupManifests() throws {
        try ManifestValidator.validate(valid, expecting: expectations)
        let a = ManifestFactory.asset(ordinal: 0, data: ManifestFactory.bytes(seed: 1, count: 3_000_000), name: "01.mp3", mediaType: "audio/mpeg")
        let b = ManifestFactory.asset(ordinal: 1, data: ManifestFactory.bytes(seed: 2, count: 1), name: "02.mp3", mediaType: "audio/mpeg")
        let c = ManifestFactory.asset(ordinal: 2, data: ManifestFactory.bytes(seed: 3, count: 4_000), name: "cover.jpg", mediaType: "image/jpeg")
        let group = ManifestFactory.manifest(kind: .group, assets: [a, b, c], cover: c.assetID)
        try ManifestValidator.validate(group, expecting: expectations)
        #expect(group.totalBytes == 3_004_001)
    }

    @Test func manifestDigestIsReproducibleAndCoversPartLayout() {
        let manifest = valid
        #expect(manifest.manifestDigest == manifest.computedDigest())
        #expect(manifest.digestInput.hasPrefix("sylvia-transfer-manifest-v1\nprotocol=1.0\nsource="))
        var tampered = manifest
        tampered.assets[0].parts[1].sha256 = String(repeating: "0", count: 64)
        rejects(tampered, .manifestDigestMismatch)
        // Display metadata is not part of the digest.
        var relabelled = manifest
        relabelled.grouping.title = "Walden; or, Life in the Woods"
        #expect(relabelled.computedDigest() == manifest.manifestDigest)
    }

    @Test func rejectsZeroLengthFile() {
        let zero = ManifestFactory.resealed(valid) { $0.assets[0].length = 0; $0.assets[0].parts = [] }
        rejects(zero, .zeroLengthAsset(valid.assets[0].assetID))
    }

    @Test func rejectsDuplicatePart() {
        let id = valid.assets[0].assetID
        rejects(ManifestFactory.resealed(valid) { $0.assets[0].parts.insert($0.assets[0].parts[1], at: 2) }, .duplicatePart(id, 1))
    }

    @Test func rejectsOverlappingPartsAndGaps() {
        let id = valid.assets[0].assetID
        rejects(ManifestFactory.resealed(valid) { $0.assets[0].parts[1].offset -= 4096 }, .overlappingParts(id, 1))
        rejects(ManifestFactory.resealed(valid) { $0.assets[0].parts[1].offset += 4096 }, .gapBetweenParts(id, 1))
        // A distinct index that restates the same range is still an overlap.
        rejects(
            ManifestFactory.resealed(valid) {
                var copy = $0.assets[0].parts[1]
                copy.index = 2
                $0.assets[0].parts[2] = copy
            }, .overlappingParts(id, 2))
    }

    @Test func rejectsMissingFinalBytesAndInconsistentTotalLength() {
        let id = valid.assets[0].assetID
        rejects(ManifestFactory.resealed(valid) { _ = $0.assets[0].parts.popLast() }, .missingFinalBytes(id))
        rejects(ManifestFactory.resealed(valid) { $0.assets[0].length += 10 }, .missingFinalBytes(id))
        rejects(ManifestFactory.resealed(valid) { $0.assets[0].length -= 10 }, .partsExceedLength(id))
        rejects(ManifestFactory.resealed(valid) { $0.assets[0].parts = [] }, .missingFinalBytes(id))
    }

    @Test func rejectsInconsistentPartSizes() {
        let id = valid.assets[0].assetID
        rejects(ManifestFactory.resealed(valid) { $0.assets[0].parts[0].length -= 1 }, .partSizeInconsistent(id, 0))
        rejects(ManifestFactory.resealed(valid) { $0.assets[0].partSize += 1 }, .invalidPartSize(id))
        rejects(ManifestFactory.resealed(valid) { $0.assets[0].partSize = 512 * 1024 }, .invalidPartSize(id))
        rejects(ManifestFactory.resealed(valid) { $0.assets[0].parts[1].length = 0 }, .emptyPart(id, 1))
        rejects(ManifestFactory.resealed(valid) { $0.assets[0].parts.reverse() }, .partOrderInvalid(id, 2))
    }

    @Test func rejectsUnsupportedMajorVersionBeforeDecodingTheRest() throws {
        var json = try JSONSerialization.jsonObject(with: TransferJSON.encode(valid)) as! [String: Any]
        json["protocol_version"] = ["major": 2, "minor": 0]
        json["assets"] = "a future shape"
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: ManifestError.unsupportedMajorVersion(2)) {
            try ManifestValidator.decodeAndValidate(data, expecting: expectations)
        }
        #expect(ManifestError.unsupportedMajorVersion(2).reason.contains("update Sylvia"))
    }

    @Test func rejectsWrongSourceItemAndIdentifiers() {
        rejects(ManifestFactory.resealed(valid) { $0.sourceID = CanonicalID.make() }, .sourceMismatch)
        #expect(throws: ManifestError.itemMismatch) {
            try ManifestValidator.validate(valid, expecting: .init(sourceID: ManifestFactory.sourceID, itemID: CanonicalID.make()))
        }
        rejects(ManifestFactory.resealed(valid) { $0.itemID = $0.itemID.uppercased() }, .invalidIdentifier)
        rejects(ManifestFactory.resealed(valid) { $0.itemVersionID = "../../etc/passwd" }, .invalidIdentifier)
    }

    @Test func rejectsWeakETagsBadDigestsAndPathLikeNames() {
        let id = valid.assets[0].assetID
        rejects(ManifestFactory.resealed(valid) { $0.assets[0].etag = "W/" + $0.assets[0].etag }, .weakOrInvalidETag(id))
        rejects(ManifestFactory.resealed(valid) { $0.assets[0].sha256 = $0.assets[0].sha256.uppercased() }, .invalidDigest(id))
        rejects(ManifestFactory.resealed(valid) { $0.assets[0].displayName = "../secret.epub" }, .displayNameLooksLikePath(id))
        rejects(ManifestFactory.resealed(valid) { $0.assets[0].mediaType = "application/epub+zip; q=1" }, .invalidMediaType(id))
        rejects(ManifestFactory.resealed(valid) { $0.grouping.title = "Walden\u{7}" }, .controlCharactersInMetadata)
        rejects(ManifestFactory.resealed(valid) { $0.grouping.title = String(repeating: "x", count: 513) }, .metadataTooLarge)
    }

    @Test func rejectsGroupingCoverAndAssetListProblems() {
        let a = ManifestFactory.asset(ordinal: 0, data: ManifestFactory.bytes(seed: 1, count: 10))
        let b = ManifestFactory.asset(ordinal: 1, data: ManifestFactory.bytes(seed: 2, count: 10))
        let group = ManifestFactory.manifest(kind: .group, assets: [a, b])
        rejects(ManifestFactory.resealed(group) { $0.grouping.kind = .single }, .groupingMismatch)
        rejects(ManifestFactory.resealed(group) { $0.assets[1].assetID = a.assetID }, .duplicateAsset(a.assetID))
        rejects(ManifestFactory.resealed(group) { $0.assets[1].ordinal = 5 }, .assetOrderInvalid(b.assetID))
        rejects(ManifestFactory.resealed(group) { $0.coverAssetID = CanonicalID.make() }, .coverNotInAssets)
        rejects(ManifestFactory.resealed(group) { $0.assets = [] }, .noAssets)
    }

    @Test func limitsPartCounts() {
        // 17 GiB at 1 MiB parts would need 17,408 parts: over the 16,384 limit.
        let big = TransferManifest.Asset(
            assetID: CanonicalID.make(), ordinal: 0, displayName: "big.m4b", mediaType: "audio/mp4",
            length: 17 * 1024 * TransferProtocol.mebibyte, etag: ETag.forContentDigest(String(repeating: "a", count: 64)),
            sha256: String(repeating: "a", count: 64), partSize: TransferProtocol.mebibyte, parts: [])
        let manifest = ManifestFactory.manifest(assets: [big])
        rejects(manifest, .tooManyParts(big.assetID))
        #expect(throws: ManifestError.tooLarge) {
            try ManifestValidator.decodeAndValidate(Data(count: 17 * 1_048_576), expecting: expectations)
        }
    }

    // MARK: Contract fixtures (Contracts/fixtures/transfer-manifest.v1 and the semantic-invalid set)

    @Test func everyValidContractFixturePassesTheSwiftValidator() throws {
        let files = TestPaths.jsonFiles(in: TestPaths.contractFixtures.appendingPathComponent("transfer-manifest.v1/valid"))
        #expect(files.count >= 4)
        for file in files {
            let manifest = try ManifestValidator.decodeAndValidate(Data(contentsOf: file), expecting: expectations)
            #expect(manifest.manifestDigest == manifest.computedDigest(), "\(file.lastPathComponent)")
        }
    }

    @Test func everyInvalidContractFixtureIsRejectedBySwiftToo() throws {
        let files = TestPaths.jsonFiles(in: TestPaths.contractFixtures.appendingPathComponent("transfer-manifest.v1/invalid"))
        #expect(files.count >= 10)
        for file in files {
            #expect(throws: ManifestError.self, "\(file.lastPathComponent)") {
                try ManifestValidator.decodeAndValidate(Data(contentsOf: file), expecting: expectations)
            }
        }
    }

    /// These manifests are valid against the JSON Schema (checked by the CI drop-in) but break a rule
    /// only the semantic validator can check. Each must be rejected with the named reason.
    @Test(arguments: [
        ("duplicate-part", "duplicatePart"),
        ("overlapping-parts", "overlappingParts"),
        ("gap-between-parts", "gapBetweenParts"),
        ("missing-final-bytes", "missingFinalBytes"),
        ("inconsistent-total-length", "missingFinalBytes"),
        ("parts-exceed-length", "partsExceedLength"),
        ("short-non-final-part", "partSizeInconsistent"),
        ("parts-out-of-order", "partOrderInvalid"),
        ("cover-not-in-assets", "coverNotInAssets"),
        ("single-with-two-assets", "groupingMismatch"),
        ("manifest-digest-mismatch", "manifestDigestMismatch"),
        ("duplicate-asset-id", "duplicateAsset"),
        ("ordinal-not-array-position", "assetOrderInvalid"),
        ("different-source", "sourceMismatch"),
    ])
    func semanticInvalidFixture(name: String, reason: String) throws {
        let file = TestPaths.bundledFixtures.appendingPathComponent("manifests/semantic-invalid/\(name).json")
        let data = try Data(contentsOf: file)
        do {
            _ = try ManifestValidator.decodeAndValidate(data, expecting: expectations)
            Issue.record("\(name) was accepted")
        } catch {
            #expect(String(describing: error).hasPrefix(reason), "\(name): \(error)")
        }
    }

    @Test func semanticInvalidSetIsComplete() {
        let files = TestPaths.jsonFiles(in: TestPaths.bundledFixtures.appendingPathComponent("manifests/semantic-invalid"))
        #expect(files.count == 14)
    }
}
