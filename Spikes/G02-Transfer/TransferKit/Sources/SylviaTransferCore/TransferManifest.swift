import CryptoKit
import Foundation

/// GET /v1/items/{item_id}/manifest: the exact byte description of one immutable item version
/// (plan 15.4, Appendix A.3, Contracts/schemas/transfer-manifest.v1.schema.json).
///
/// The manifest identifies bytes, not paths: `display_name` is a label for people and is never used
/// to build a local or remote path.
public struct TransferManifest: Codable, Hashable, Sendable {
    public struct Grouping: Codable, Hashable, Sendable {
        public var kind: ItemKind
        public var title: String
        public var creators: [String]

        public init(kind: ItemKind, title: String, creators: [String] = []) {
            self.kind = kind
            self.title = title
            self.creators = creators
        }

        enum CodingKeys: String, CodingKey {
            case kind
            case title
            case creators
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try container.decode(ItemKind.self, forKey: .kind)
            title = try container.decode(String.self, forKey: .title)
            creators = try container.decodeIfPresent([String].self, forKey: .creators) ?? []
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind, forKey: .kind)
            try container.encode(title, forKey: .title)
            if !creators.isEmpty { try container.encode(creators, forKey: .creators) }
        }
    }

    public struct Part: Codable, Hashable, Sendable {
        public var index: Int
        public var offset: Int64
        public var length: Int64
        public var sha256: String

        public init(index: Int, offset: Int64, length: Int64, sha256: String) {
            self.index = index
            self.offset = offset
            self.length = length
            self.sha256 = sha256
        }

        /// Inclusive last byte offset.
        public var lastOffset: Int64 { offset + length - 1 }
    }

    public struct Asset: Codable, Hashable, Sendable {
        public var assetID: String
        public var ordinal: Int
        public var displayName: String
        public var mediaType: String
        public var length: Int64
        public var etag: String
        public var sha256: String
        public var partSize: Int64
        public var parts: [Part]

        enum CodingKeys: String, CodingKey {
            case assetID = "asset_id"
            case ordinal
            case displayName = "display_name"
            case mediaType = "media_type"
            case length
            case etag
            case sha256
            case partSize = "part_size"
            case parts
        }

        public init(
            assetID: String, ordinal: Int, displayName: String, mediaType: String, length: Int64, etag: String,
            sha256: String, partSize: Int64, parts: [Part]
        ) {
            self.assetID = assetID
            self.ordinal = ordinal
            self.displayName = displayName
            self.mediaType = mediaType
            self.length = length
            self.etag = etag
            self.sha256 = sha256
            self.partSize = partSize
            self.parts = parts
        }
    }

    public var schemaVersion: Int
    public var protocolVersion: ProtocolVersion
    public var sourceID: String
    public var itemID: String
    public var itemVersionID: String
    public var createdAt: Date
    public var manifestDigest: String
    public var grouping: Grouping
    public var coverAssetID: String?
    public var assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case protocolVersion = "protocol_version"
        case sourceID = "source_id"
        case itemID = "item_id"
        case itemVersionID = "item_version_id"
        case createdAt = "created_at"
        case manifestDigest = "manifest_digest"
        case grouping
        case coverAssetID = "cover_asset_id"
        case assets
    }

    /// Builds a manifest and fills in `manifest_digest`.
    public init(
        sourceID: String, itemID: String, itemVersionID: String, createdAt: Date, grouping: Grouping,
        coverAssetID: String? = nil, assets: [Asset]
    ) {
        schemaVersion = 1
        protocolVersion = TransferProtocol.version
        self.sourceID = sourceID
        self.itemID = itemID
        self.itemVersionID = itemVersionID
        self.createdAt = createdAt
        manifestDigest = ""
        self.grouping = grouping
        self.coverAssetID = coverAssetID
        self.assets = assets
        manifestDigest = computedDigest()
    }

    public var totalBytes: Int64 { assets.reduce(0) { $0 + $1.length } }

    /// The digest input is a line-oriented ASCII text over the byte-identity fields only, so any
    /// implementation can reproduce it without canonical JSON (ADR-0009). Display metadata
    /// (title, creators, display names, created_at) is deliberately excluded.
    ///
    ///     sylvia-transfer-manifest-v1
    ///     protocol=<major>.<minor>
    ///     source=<source_id>
    ///     item=<item_id>
    ///     version=<item_version_id>
    ///     cover=<cover_asset_id or ->
    ///     assets=<count>
    ///     asset=<ordinal>,<asset_id>,<media_type>,<length>,<etag>,<sha256>,<part_size>,<part_count>
    ///     part=<index>,<offset>,<length>,<sha256>      (for each part, after its asset line)
    ///
    /// Each line ends with "\n". The fields are constrained to characters that cannot contain "," or "\n".
    public var digestInput: String {
        var lines = [
            "sylvia-transfer-manifest-v1",
            "protocol=\(protocolVersion.major).\(protocolVersion.minor)",
            "source=\(sourceID)",
            "item=\(itemID)",
            "version=\(itemVersionID)",
            "cover=\(coverAssetID ?? "-")",
            "assets=\(assets.count)",
        ]
        for asset in assets {
            lines.append(
                "asset=\(asset.ordinal),\(asset.assetID),\(asset.mediaType),\(asset.length),\(asset.etag),"
                    + "\(asset.sha256),\(asset.partSize),\(asset.parts.count)")
            for part in asset.parts {
                lines.append("part=\(part.index),\(part.offset),\(part.length),\(part.sha256)")
            }
        }
        return lines.map { $0 + "\n" }.joined()
    }

    public func computedDigest() -> String { SHA256Hex.digest(Data(digestInput.utf8)) }
}

/// The part layout for one asset: every part is `partSize` bytes except a shorter final part.
public enum PartPlan {
    public struct Slice: Hashable, Sendable {
        public var index: Int
        public var offset: Int64
        public var length: Int64
    }

    public static func slices(length: Int64, partSize: Int64) -> [Slice] {
        precondition(length > 0 && partSize > 0)
        var slices: [Slice] = []
        var offset: Int64 = 0
        var index = 0
        while offset < length {
            let size = min(partSize, length - offset)
            slices.append(Slice(index: index, offset: offset, length: size))
            offset += size
            index += 1
        }
        return slices
    }

    public static func partCount(length: Int64, partSize: Int64) -> Int {
        Int((length + partSize - 1) / partSize)
    }
}
