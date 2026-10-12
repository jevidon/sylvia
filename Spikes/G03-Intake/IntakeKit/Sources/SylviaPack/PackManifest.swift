import Foundation
import SylviaIntakeCore

/// `sylviapack/manifest.json` (contract `sylviapack-manifest` v1,
/// Contracts/schemas/sylviapack-manifest.v1.schema.json). Format: Docs/ADRs/0010-intake-handoff-and-wired-bundles.md.
public struct PackManifest: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let format = "sylviapack"

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case epub, pdf, text, markdown, audio, cover
    }

    public enum GroupKind: String, Codable, Sendable {
        /// One logical audiobook made of ordered audio members (plan 8.3).
        case audiobook
        /// A single publication (EPUB, PDF, text or Markdown) with optional cover.
        case publication
    }

    public enum MemberOrderBasis: String, Codable, Sendable {
        case embeddedTrack = "embedded_track"
        case filename
        case userConfirmed = "user_confirmed"
    }

    public struct Generator: Codable, Equatable, Sendable {
        public var name: String
        public var version: String
        public init(name: String, version: String) {
            self.name = name
            self.version = version
        }
    }

    public struct File: Codable, Equatable, Sendable {
        public var path: String
        public var size: UInt64
        public var sha256: String
        public var mediaType: String
        public var kind: Kind
        public var groupID: String?
        public var order: Int?

        public init(path: String, size: UInt64, sha256: String, mediaType: String, kind: Kind,
                    groupID: String? = nil, order: Int? = nil) {
            self.path = path
            self.size = size
            self.sha256 = sha256
            self.mediaType = mediaType
            self.kind = kind
            self.groupID = groupID
            self.order = order
        }

        enum CodingKeys: String, CodingKey {
            case path, size, sha256, kind, order
            case mediaType = "media_type"
            case groupID = "group_id"
        }
    }

    public struct Identifier: Codable, Equatable, Sendable {
        public var scheme: String
        public var value: String
        public init(scheme: String, value: String) {
            self.scheme = scheme
            self.value = value
        }
    }

    public struct Group: Codable, Equatable, Sendable {
        public var groupID: String
        public var kind: GroupKind
        public var title: String?
        public var creators: [String]?
        public var language: String?
        public var identifiers: [Identifier]?
        public var memberOrderBasis: MemberOrderBasis?

        public init(groupID: String, kind: GroupKind, title: String? = nil, creators: [String]? = nil,
                    language: String? = nil, identifiers: [Identifier]? = nil, memberOrderBasis: MemberOrderBasis? = nil) {
            self.groupID = groupID
            self.kind = kind
            self.title = title
            self.creators = creators
            self.language = language
            self.identifiers = identifiers
            self.memberOrderBasis = memberOrderBasis
        }

        enum CodingKeys: String, CodingKey {
            case kind, title, creators, language, identifiers
            case groupID = "group_id"
            case memberOrderBasis = "member_order_basis"
        }
    }

    public var schemaVersion: Int
    public var format: String
    public var packID: UUID
    public var createdAt: Date
    public var generator: Generator
    public var files: [File]
    public var groups: [Group]
    public var totalSize: UInt64

    public init(packID: UUID, createdAt: Date, generator: Generator, files: [File], groups: [Group]) {
        self.schemaVersion = PackManifest.schemaVersion
        self.format = PackManifest.format
        self.packID = packID
        self.createdAt = createdAt
        self.generator = generator
        self.files = files
        self.groups = groups
        self.totalSize = files.reduce(0) { $0 &+ $1.size }
    }

    enum CodingKeys: String, CodingKey {
        case format, generator, files, groups
        case schemaVersion = "schema_version"
        case packID = "pack_id"
        case createdAt = "created_at"
        case totalSize = "total_size"
    }

    /// Canonical bytes: sorted keys, RFC 3339 UTC dates, no escaped slashes.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }

    public static func decode(_ data: Data) throws -> PackManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PackManifest.self, from: data)
    }

    /// Semantic checks that JSON decoding cannot express. Throws the first problem found.
    public func validate(limits: PackLimits) throws(PackRejection) {
        guard schemaVersion == PackManifest.schemaVersion else {
            throw PackRejection(.unsupportedVersion, "schema_version \(schemaVersion)")
        }
        guard format == PackManifest.format else { throw PackRejection(.manifestInvalid, "format") }
        guard !files.isEmpty else { throw PackRejection(.manifestInvalid, "no files") }
        guard files.count + PackLayout.reservedEntryCount <= limits.maxEntries else {
            throw PackRejection(.tooManyEntries, "\(files.count) files")
        }
        var groupKinds: [String: GroupKind] = [:]
        for group in groups {
            guard PackManifest.isValidGroupID(group.groupID) else { throw PackRejection(.manifestInvalid, "group_id") }
            guard groupKinds.updateValue(group.kind, forKey: group.groupID) == nil else {
                throw PackRejection(.manifestInvalid, "duplicate group_id")
            }
        }
        var keys = Set<String>()
        var sum: UInt64 = 0
        var audioMembers: [String: Int] = [:]
        var orders: [String: Set<Int>] = [:]
        for file in files {
            try PackPath.validateManifestPath(file.path)
            guard keys.insert(PackPath.collisionKey(file.path)).inserted else {
                throw PackRejection(.duplicatePath, "manifest lists a path twice (case and Unicode normalization ignored)")
            }
            guard isLowercaseSHA256Hex(file.sha256) else { throw PackRejection(.manifestInvalid, "sha256") }
            guard !file.mediaType.isEmpty, file.mediaType.utf8.count <= 128 else {
                throw PackRejection(.manifestInvalid, "media_type")
            }
            guard file.size <= limits.maxFileSize(for: file.kind) else {
                throw PackRejection(.limitExceeded, "\(file.kind.rawValue) file of \(file.size) bytes")
            }
            let (partial, overflow) = sum.addingReportingOverflow(file.size)
            guard !overflow else { throw PackRejection(.manifestInvalid, "size overflow") }
            sum = partial
            if let groupID = file.groupID {
                guard let kind = groupKinds[groupID] else { throw PackRejection(.manifestInvalid, "unknown group_id") }
                if kind == .audiobook {
                    guard file.kind == .audio || file.kind == .cover else {
                        throw PackRejection(.manifestInvalid, "audiobook member must be audio or cover")
                    }
                    if file.kind == .audio {
                        audioMembers[groupID, default: 0] += 1
                        guard let order = file.order, order >= 1 else {
                            throw PackRejection(.manifestInvalid, "audiobook member needs order >= 1")
                        }
                        guard orders[groupID, default: []].insert(order).inserted else {
                            throw PackRejection(.manifestInvalid, "duplicate member order")
                        }
                    }
                }
            } else if file.order != nil {
                throw PackRejection(.manifestInvalid, "order without group_id")
            }
        }
        for (_, count) in audioMembers where count > limits.maxAudioMembersPerGroup {
            throw PackRejection(.limitExceeded, "\(count) audio members in one group")
        }
        try PackPath.checkNoFileDirectoryConflicts(files.map(\.path))
        guard sum == totalSize else { throw PackRejection(.manifestInvalid, "total_size is not the sum of sizes") }
        guard totalSize <= limits.maxTotalSize else { throw PackRejection(.limitExceeded, "total size \(totalSize)") }
    }

    static func isValidGroupID(_ id: String) -> Bool {
        (1...64).contains(id.utf8.count)
            && id.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_") }
    }
}
