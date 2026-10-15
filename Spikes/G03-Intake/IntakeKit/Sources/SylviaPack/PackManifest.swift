import Foundation
import SylviaIntakeCore

/// `sylviapack/manifest.json` (contract `sylviapack-manifest` v1,
/// Contracts/schemas/sylviapack-manifest.v1.schema.json). Format: Docs/ADRs/0010-intake-handoff-and-wired-bundles.md.
public struct PackManifest: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let format = "sylviapack"

    // The contract's enums are decoded byte for byte (`decodeExactCase`; G0.3 review R4-01), not with `init(rawValue:)`,
    // whose String comparison treats canonically equivalent text as equal.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case epub, pdf, text, markdown, audio, cover
        public init(from decoder: any Decoder) throws { self = try decodeExactCase(Self.self, from: decoder) }
    }

    public enum GroupKind: String, Codable, Sendable, CaseIterable {
        /// One logical audiobook made of ordered audio members (plan 8.3).
        case audiobook
        /// A single publication (EPUB, PDF, text or Markdown) with optional cover.
        case publication
        public init(from decoder: any Decoder) throws { self = try decodeExactCase(Self.self, from: decoder) }
    }

    public enum MemberOrderBasis: String, Codable, Sendable, CaseIterable {
        case embeddedTrack = "embedded_track"
        case filename
        case userConfirmed = "user_confirmed"
        public init(from decoder: any Decoder) throws { self = try decodeExactCase(Self.self, from: decoder) }
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

        /// The optional members refuse an explicit null, as the schema does (G0.3 review R3-01).
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            path = try container.decode(String.self, forKey: .path)
            size = try container.decode(UInt64.self, forKey: .size)
            sha256 = try container.decode(String.self, forKey: .sha256)
            mediaType = try container.decode(String.self, forKey: .mediaType)
            kind = try container.decode(Kind.self, forKey: .kind)
            groupID = try container.decodeIfPresentRejectingNull(String.self, forKey: .groupID)
            order = try container.decodeIfPresentRejectingNull(Int.self, forKey: .order)
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

        /// The optional members refuse an explicit null, as the schema does (G0.3 review R3-01).
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            groupID = try container.decode(String.self, forKey: .groupID)
            kind = try container.decode(GroupKind.self, forKey: .kind)
            title = try container.decodeIfPresentRejectingNull(String.self, forKey: .title)
            creators = try container.decodeIfPresentRejectingNull([String].self, forKey: .creators)
            language = try container.decodeIfPresentRejectingNull(String.self, forKey: .language)
            identifiers = try container.decodeIfPresentRejectingNull([Identifier].self, forKey: .identifiers)
            memberOrderBasis = try container.decodeIfPresentRejectingNull(MemberOrderBasis.self, forKey: .memberOrderBasis)
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

    /// `pack_id` must be a UUID in its canonical form (`CanonicalUUID`; G0.3 review R3-01).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        format = try container.decode(String.self, forKey: .format)
        packID = try container.decodeCanonicalUUID(forKey: .packID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        generator = try container.decode(Generator.self, forKey: .generator)
        files = try container.decode([File].self, forKey: .files)
        groups = try container.decode([Group].self, forKey: .groups)
        totalSize = try container.decode(UInt64.self, forKey: .totalSize)
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

    /// `decode(_:)` after the readers' size limit: a manifest of more than `limits.maxManifestBytes` bytes is refused
    /// (`manifest_too_large`), whatever its content (G0.3 review R4-02; the schema's description states the limit).
    /// `PackReader` checks the entry's declared size before reading it, then calls this; `sylviapack-tool
    /// check-manifest` calls it on a file, so the differential check applies the same limit.
    public static func decode(_ data: Data, limits: PackLimits) throws -> PackManifest {
        guard data.count <= limits.maxManifestBytes else {
            throw PackRejection(.manifestTooLarge, "more than \(limits.maxManifestBytes) bytes")
        }
        return try decode(data)
    }

    /// The text must be strict JSON (`StrictJSON`: no duplicate member names, trailing commas, byte order mark and so on;
    /// G0.3 review R3-01), and `created_at` is read as the schema's `date-time` format accepts it (`RFC3339`), not with
    /// Foundation's `.iso8601` strategy, which refused a lowercase `t` or `z` and accepted dates such as 30 February.
    /// Throws `StrictJSON.Violation` or `DecodingError`.
    public static func decode(_ data: Data) throws -> PackManifest {
        try StrictJSON.check(data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = RFC3339.decodingStrategy
        return try decoder.decode(PackManifest.self, from: data)
    }

    /// Semantic checks that JSON decoding cannot express. Throws the first problem found.
    ///
    /// Every string bound of the schema is checked here in code points, as the schema counts them (G0.3 review
    /// R2-04: the reader used to accept generator names, titles, creators, languages and identifiers the schema
    /// refuses). Paths are bounded in UTF-8 bytes instead (`PackPath`), which is stricter than the schema for non-ASCII
    /// paths; the schema's description says so.
    ///
    /// Text is compared byte for byte (`PathBytes.equal`) or, for dictionary and set lookups, only after the schema's
    /// pattern has proved it ASCII: Swift's `String` equality and hashing treat canonically equivalent text as equal, and
    /// two ASCII strings are canonically equivalent only when they are identical (G0.3 review R4-01). The one exception is
    /// the duplicate-path rule, which deliberately treats paths as equal after case folding and normalization and so
    /// refuses more, never less.
    public func validate(limits: PackLimits) throws(PackRejection) {
        guard schemaVersion == PackManifest.schemaVersion else {
            throw PackRejection(.unsupportedVersion, "schema_version \(schemaVersion)")
        }
        guard PathBytes.equal(format, PackManifest.format) else { throw PackRejection(.manifestInvalid, "format") }
        guard hasSchemaLength(generator.name, 1...128) else { throw PackRejection(.manifestInvalid, "generator.name length") }
        guard hasSchemaLength(generator.version, 1...64) else { throw PackRejection(.manifestInvalid, "generator.version length") }
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
            try PackManifest.checkStringBounds(of: group)
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
            guard hasSchemaLength(file.mediaType, 1...128) else { throw PackRejection(.manifestInvalid, "media_type length") }
            // The schema gives every order a minimum of 1, whatever the file's group; the audiobook rules below add
            // that each audio member has one and that they are unique.
            if let order = file.order, order < 1 { throw PackRejection(.manifestInvalid, "order below 1") }
            guard file.size <= limits.maxFileSize(for: file.kind) else {
                throw PackRejection(.limitExceeded, "\(file.kind.rawValue) file of \(file.size) bytes")
            }
            let (partial, overflow) = sum.addingReportingOverflow(file.size)
            guard !overflow else { throw PackRejection(.manifestInvalid, "size overflow") }
            sum = partial
            if let groupID = file.groupID {
                // The schema's pattern before the lookup (G0.3 review R4-01). `groupKinds` is keyed by String, whose
                // equality and hashing treat canonically equivalent text as equal, so without this a file group_id of
                // "WALDEN_" + U+212A KELVIN SIGN, which the pattern refuses, found the group "WALDEN_K" and the pack
                // was accepted, written by PackWriter and extracted by PackReader.
                guard PackManifest.isValidGroupID(groupID) else { throw PackRejection(.manifestInvalid, "files.group_id") }
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

    /// The schema's bounds on a group's optional metadata, in code points: title at most 1024, each creator at most
    /// 512, language at most 35, each identifier's scheme 1 to 64 and value 1 to 512.
    static func checkStringBounds(of group: Group) throws(PackRejection) {
        if let title = group.title, !hasSchemaLength(title, 0...1024) {
            throw PackRejection(.manifestInvalid, "groups.title length")
        }
        if let creators = group.creators, !creators.allSatisfy({ hasSchemaLength($0, 0...512) }) {
            throw PackRejection(.manifestInvalid, "groups.creators length")
        }
        if let language = group.language, !hasSchemaLength(language, 0...35) {
            throw PackRejection(.manifestInvalid, "groups.language length")
        }
        for identifier in group.identifiers ?? [] {
            guard hasSchemaLength(identifier.scheme, 1...64), hasSchemaLength(identifier.value, 1...512) else {
                throw PackRejection(.manifestInvalid, "groups.identifiers length")
            }
        }
    }

    /// The schema's `^[A-Za-z0-9_-]{1,64}$`, matched on bytes.
    static func isValidGroupID(_ id: String) -> Bool {
        (1...64).contains(id.utf8.count) && id.utf8.allSatisfy { byte in
            (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
                || byte == UInt8(ascii: "-") || byte == UInt8(ascii: "_")
        }
    }
}
