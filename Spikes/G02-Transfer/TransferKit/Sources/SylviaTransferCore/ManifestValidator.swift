import Foundation

/// Semantic validation of a transfer manifest before any byte is requested (Appendix A.3).
///
/// The JSON Schema checks shapes, patterns and ranges; this validator checks what a schema cannot:
/// part continuity (no duplicate, overlapping or missing parts, no gap, no missing final bytes), that
/// the parts add up to the asset length, part-size consistency, unique IDs, ordinal order, the cover
/// reference, the manifest digest and the binding to the paired source and requested item.
public enum ManifestValidator {
    public struct Expectations: Sendable {
        public var sourceID: String
        public var itemID: String?
        public init(sourceID: String, itemID: String? = nil) {
            self.sourceID = sourceID
            self.itemID = itemID
        }
    }

    /// Decodes and validates raw JSON. Size is checked before decoding.
    public static func decodeAndValidate(
        _ data: Data, expecting expectations: Expectations, maximumBytes: Int = 16 * 1_048_576
    ) throws(ManifestError) -> TransferManifest {
        guard data.count <= maximumBytes else { throw .tooLarge }
        // Check the major version first so a future manifest gets the update message, not "malformed".
        if let probe = try? JSONDecoder().decode(VersionProbe.self, from: data),
            let major = probe.protocolVersion?.major, major != TransferProtocol.major
        {
            throw .unsupportedMajorVersion(major)
        }
        let manifest: TransferManifest
        do {
            manifest = try TransferJSON.decode(TransferManifest.self, from: data)
        } catch {
            throw .malformed
        }
        try validate(manifest, expecting: expectations)
        return manifest
    }

    public static func validate(_ manifest: TransferManifest, expecting expectations: Expectations) throws(ManifestError) {
        guard manifest.schemaVersion == 1 else { throw .unsupportedSchemaVersion(manifest.schemaVersion) }
        guard manifest.protocolVersion.major == TransferProtocol.major else {
            throw .unsupportedMajorVersion(manifest.protocolVersion.major)
        }
        for id in [manifest.sourceID, manifest.itemID, manifest.itemVersionID] {
            guard CanonicalID.isValid(id) else { throw .invalidIdentifier }
        }
        guard manifest.sourceID == expectations.sourceID else { throw .sourceMismatch }
        if let itemID = expectations.itemID, manifest.itemID != itemID { throw .itemMismatch }
        try validateText(manifest.grouping.title, maximum: TransferProtocol.maximumTitleLength)
        guard manifest.grouping.creators.count <= TransferProtocol.maximumCreators else { throw .metadataTooLarge }
        for creator in manifest.grouping.creators { try validateText(creator, maximum: 256) }

        guard !manifest.assets.isEmpty else { throw .noAssets }
        guard manifest.assets.count <= TransferProtocol.maximumAssetsPerItem else { throw .tooManyAssets }
        if manifest.grouping.kind == .single, manifest.assets.count != 1 { throw .groupingMismatch }

        var assetIDs = Set<String>()
        var totalParts = 0
        for (position, asset) in manifest.assets.enumerated() {
            guard CanonicalID.isValid(asset.assetID) else { throw .invalidIdentifier }
            guard assetIDs.insert(asset.assetID).inserted else { throw .duplicateAsset(asset.assetID) }
            guard asset.ordinal == position else { throw .assetOrderInvalid(asset.assetID) }
            try validateText(asset.displayName, maximum: TransferProtocol.maximumDisplayNameLength)
            guard !asset.displayName.contains("/"), !asset.displayName.contains("\\") else {
                throw .displayNameLooksLikePath(asset.assetID)
            }
            guard isMediaType(asset.mediaType) else { throw .invalidMediaType(asset.assetID) }
            guard asset.length > 0 else { throw .zeroLengthAsset(asset.assetID) }
            guard asset.length <= TransferProtocol.maximumAssetLength else { throw .assetTooLarge(asset.assetID) }
            guard ETag.isStrong(asset.etag) else { throw .weakOrInvalidETag(asset.assetID) }
            guard Hex.isSHA256(asset.sha256) else { throw .invalidDigest(asset.assetID) }
            guard asset.partSize >= TransferProtocol.minimumPartSize,
                asset.partSize <= TransferProtocol.maximumPartSize,
                asset.partSize % TransferProtocol.mebibyte == 0
            else { throw .invalidPartSize(asset.assetID) }

            let expectedCount = PartPlan.partCount(length: asset.length, partSize: asset.partSize)
            guard asset.parts.count <= TransferProtocol.maximumPartsPerAsset,
                expectedCount <= TransferProtocol.maximumPartsPerAsset
            else { throw .tooManyParts(asset.assetID) }
            totalParts += asset.parts.count
            guard totalParts <= TransferProtocol.maximumPartsPerManifest else { throw .tooManyParts(asset.assetID) }
            try validateParts(of: asset)
        }
        if let cover = manifest.coverAssetID {
            guard assetIDs.contains(cover) else { throw .coverNotInAssets }
        }
        guard Hex.isSHA256(manifest.manifestDigest),
            constantTimeEquals(Array(manifest.manifestDigest.utf8), Array(manifest.computedDigest().utf8))
        else { throw .manifestDigestMismatch }
    }

    static func validateParts(of asset: TransferManifest.Asset) throws(ManifestError) {
        guard !asset.parts.isEmpty else { throw .missingFinalBytes(asset.assetID) }
        var seenIndexes = Set<Int>()
        var expectedOffset: Int64 = 0
        for (position, part) in asset.parts.enumerated() {
            guard seenIndexes.insert(part.index).inserted else { throw .duplicatePart(asset.assetID, part.index) }
            guard part.index == position else { throw .partOrderInvalid(asset.assetID, part.index) }
            guard Hex.isSHA256(part.sha256) else { throw .invalidDigest(asset.assetID) }
            guard part.length > 0 else { throw .emptyPart(asset.assetID, part.index) }
            guard part.offset >= 0 else { throw .overlappingParts(asset.assetID, part.index) }
            if part.offset < expectedOffset { throw .overlappingParts(asset.assetID, part.index) }
            if part.offset > expectedOffset { throw .gapBetweenParts(asset.assetID, part.index) }
            let isFinal = position == asset.parts.count - 1
            // Every part except the last is exactly part_size; the last is 1...part_size bytes.
            if isFinal {
                guard part.length <= asset.partSize else { throw .partSizeInconsistent(asset.assetID, part.index) }
            } else {
                guard part.length == asset.partSize else { throw .partSizeInconsistent(asset.assetID, part.index) }
            }
            let (end, overflow) = part.offset.addingReportingOverflow(part.length)
            guard !overflow else { throw .partsExceedLength(asset.assetID) }
            if end > asset.length { throw .partsExceedLength(asset.assetID) }
            expectedOffset = end
        }
        guard expectedOffset == asset.length else { throw .missingFinalBytes(asset.assetID) }
    }

    static func validateText(_ text: String, maximum: Int) throws(ManifestError) {
        guard !text.isEmpty, text.unicodeScalars.count <= maximum else { throw .metadataTooLarge }
        guard !text.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            throw .controlCharactersInMetadata
        }
    }

    static func isMediaType(_ text: String) -> Bool {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, text.utf8.count <= 255 else { return false }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789!#$&^_.+-")
        return parts.allSatisfy { part in
            guard let first = part.first, first.isLetter || first.isNumber else { return false }
            return part.allSatisfy { allowed.contains($0) }
        }
    }

    private struct VersionProbe: Decodable {
        var protocolVersion: ProtocolVersion?
        enum CodingKeys: String, CodingKey { case protocolVersion = "protocol_version" }
    }
}

public enum ManifestError: Error, Equatable, Sendable {
    case tooLarge
    case malformed
    case unsupportedSchemaVersion(Int)
    case unsupportedMajorVersion(Int)
    case invalidIdentifier
    case sourceMismatch
    case itemMismatch
    case metadataTooLarge
    case controlCharactersInMetadata
    case noAssets
    case tooManyAssets
    case groupingMismatch
    case duplicateAsset(String)
    case assetOrderInvalid(String)
    case invalidMediaType(String)
    case displayNameLooksLikePath(String)
    case zeroLengthAsset(String)
    case assetTooLarge(String)
    case weakOrInvalidETag(String)
    case invalidDigest(String)
    case invalidPartSize(String)
    case tooManyParts(String)
    case duplicatePart(String, Int)
    case partOrderInvalid(String, Int)
    case emptyPart(String, Int)
    case overlappingParts(String, Int)
    case gapBetweenParts(String, Int)
    case partSizeInconsistent(String, Int)
    case partsExceedLength(String)
    case missingFinalBytes(String)
    case coverNotInAssets
    case manifestDigestMismatch

    /// A short reason for diagnostics. Never includes titles or paths.
    public var reason: String {
        switch self {
        case .unsupportedMajorVersion(let major):
            "The Mac uses transfer protocol version \(major); update Sylvia on both devices."
        case .zeroLengthAsset: "The source lists an empty file."
        case .duplicatePart, .overlappingParts: "The source described overlapping parts."
        case .gapBetweenParts, .missingFinalBytes, .partsExceedLength: "The source's part list does not cover the file exactly."
        case .manifestDigestMismatch: "The transfer description is inconsistent."
        case .sourceMismatch: "The transfer description is for a different Mac."
        default: "The transfer description is invalid."
        }
    }
}
