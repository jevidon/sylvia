import Foundation
import SylviaIntakeCore

/// `handoff.json`: the share extension's commit record (contract `import-handoff-manifest` v1,
/// Contracts/schemas/import-handoff-manifest.v1.schema.json). It is written atomically and last; a handoff
/// directory without it is incomplete by definition.
public struct HandoffManifest: Codable, Equatable, Sendable {
    public static let fileName = "handoff.json"
    public static let schemaVersion = 1
    /// The app's scan refuses a larger `handoff.json` (`read(contentsOf:)`), and the extension refuses to commit one
    /// (`HandoffSession.commit`), so a receipt always means the app can read the manifest. The schema's description
    /// states the limit (G0.3 review R4-02). 100 items with 255-byte file names and 128-character type identifiers take
    /// 87,803 bytes, a third of it (test "handoff.json size: ...").
    public static let maxBytes = 256 * 1024
    public static let maxItems = 100

    public struct Producer: Codable, Equatable, Sendable {
        public var kind: String               // "share_extension" in v1
        public var bundleIdentifier: String
        public var buildVersion: String

        enum CodingKeys: String, CodingKey {
            case kind
            case bundleIdentifier = "bundle_identifier"
            case buildVersion = "build_version"
        }
    }

    public enum Representation: String, Codable, Sendable, CaseIterable {
        /// NSItemProvider file representation of a supported content type.
        case fileRepresentation = "file_representation"
        /// A `public.file-url` item pointing at a file the extension could read.
        case fileURL = "file_url"
        /// Matched byte for byte (`decodeExactCase`; G0.3 review R4-01).
        public init(from decoder: any Decoder) throws { self = try decodeExactCase(Self.self, from: decoder) }
    }

    public struct Item: Codable, Equatable, Sendable {
        public var itemID: UUID
        public var storedPath: String          // relative to the handoff directory: items/<n>[.<ext>]
        public var originalFilename: String     // metadata only; never used as a path
        public var contentType: String          // uniform type identifier
        public var byteCount: UInt64
        public var sha256: String
        public var representation: Representation
        public var providerTypeIdentifier: String

        enum CodingKeys: String, CodingKey {
            case itemID = "item_id"
            case storedPath = "stored_path"
            case originalFilename = "original_filename"
            case contentType = "content_type"
            case byteCount = "byte_count"
            case sha256
            case representation
            case providerTypeIdentifier = "provider_type_identifier"
        }
    }

    public var schemaVersion: Int
    public var handoffID: UUID
    public var createdAt: Date
    public var producer: Producer
    public var items: [Item]
    public var totalBytes: UInt64

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case handoffID = "handoff_id"
        case createdAt = "created_at"
        case producer
        case items
        case totalBytes = "total_bytes"
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Reads `handoff.json` as the app's scan does: a regular file (no symbolic link) of at most `maxBytes` bytes, then
    /// `decode(_:)`. A larger file is refused with `HandoffManifestError.tooLarge`, whatever its content (G0.3 review
    /// R4-02). `sylviapack-tool check-manifest` reads its inputs with this, so the differential check applies the limit.
    public static func read(contentsOf url: URL) throws -> HandoffManifest {
        let data: Data
        do {
            data = try AtomicFile.readSmall(url, limit: maxBytes)
        } catch CopyFailure.exceedsLimit {
            throw HandoffManifestError.tooLarge(limit: maxBytes)
        }
        return try decode(data)
    }

    /// The text must be strict JSON (`StrictJSON`: no duplicate member names, trailing commas, byte order mark and so on;
    /// G0.3 review R3-01), the UUIDs canonical (`CanonicalUUID`), and `created_at` is read as the schema's `date-time`
    /// format accepts it (`RFC3339`), not with Foundation's `.iso8601` strategy, which refused a lowercase `t` or `z` and
    /// accepted dates such as 30 February. Throws `StrictJSON.Violation` or `DecodingError`.
    public static func decode(_ data: Data) throws -> HandoffManifest {
        try StrictJSON.check(data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = RFC3339.decodingStrategy
        return try decoder.decode(HandoffManifest.self, from: data)
    }

    /// Structural checks beyond JSON decoding. `directoryName` is the handoff directory's name.
    ///
    /// String bounds are the schema's, counted in code points as the schema counts them (G0.3 review R2-04: the reader
    /// used to accept producer fields and provider type identifiers the schema refuses). `original_filename` is
    /// bounded in UTF-8 bytes instead (at most 255, a file-name length), which the schema's description states.
    ///
    /// Text is compared byte for byte, or kept in a set only after the schema's pattern has proved it ASCII
    /// (`stored_path`): Swift's `String` equality treats canonically equivalent text as equal (G0.3 review R4-01).
    public func validate(directoryName: String) throws(HandoffManifestError) {
        guard schemaVersion == HandoffManifest.schemaVersion else { throw .unsupportedSchemaVersion(schemaVersion) }
        guard UUID(uuidString: directoryName) == handoffID else { throw .idDoesNotMatchDirectory }
        guard PathBytes.equal(producer.kind, "share_extension") else { throw .invalidField("producer.kind") }
        guard hasSchemaLength(producer.bundleIdentifier, 1...255) else { throw .invalidField("producer.bundle_identifier") }
        guard hasSchemaLength(producer.buildVersion, 1...64) else { throw .invalidField("producer.build_version") }
        guard !items.isEmpty, items.count <= HandoffManifest.maxItems else { throw .invalidField("items") }
        var seenPaths = Set<String>()
        var seenIDs = Set<UUID>()
        var sum: UInt64 = 0
        for item in items {
            guard HandoffManifest.isValidStoredPath(item.storedPath) else { throw .unsafeStoredPath }
            guard seenPaths.insert(item.storedPath).inserted, seenIDs.insert(item.itemID).inserted else {
                throw .duplicateItem
            }
            guard isLowercaseSHA256Hex(item.sha256) else { throw .invalidField("sha256") }
            // The schema's pattern ^[^/\u0000]+$ excludes the code points "/" and U+0000 anywhere. Checked on bytes:
            // String.contains("/") misses a "/" that a combining mark follows (report finding F18).
            guard !item.originalFilename.utf8.isEmpty, item.originalFilename.utf8.count <= 255,
                  !PathBytes.containsSeparator(item.originalFilename), !item.originalFilename.utf8.contains(0) else {
                throw .invalidField("original_filename")
            }
            guard hasSchemaLength(item.contentType, 1...128) else { throw .invalidField("content_type") }
            guard hasSchemaLength(item.providerTypeIdentifier, 1...128) else { throw .invalidField("provider_type_identifier") }
            let (partial, overflow) = sum.addingReportingOverflow(item.byteCount)
            guard !overflow else { throw .invalidField("byte_count") }
            sum = partial
        }
        guard sum == totalBytes else { throw .totalMismatch }
    }

    /// `items/<1-4 ASCII digits>` optionally followed by `.<1-16 of a-z and 0-9>`: the schema's pattern
    /// `^items/[0-9]{1,4}(\.[a-z0-9]{1,16})?$`, matched byte by byte (report finding F18), so a tampered manifest cannot
    /// point outside its own directory.
    public static func isValidStoredPath(_ path: String) -> Bool {
        let bytes = Array(path.utf8)
        let prefix = Array("items/".utf8)
        guard bytes.starts(with: prefix) else { return false }
        func isDigit(_ byte: UInt8) -> Bool { (0x30...0x39).contains(byte) }
        var index = prefix.count
        let digitsStart = index
        while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        guard (1...4).contains(index - digitsStart) else { return false }
        if index == bytes.count { return true }
        guard bytes[index] == UInt8(ascii: ".") else { return false }
        index += 1
        let extensionStart = index
        while index < bytes.count, isDigit(bytes[index]) || (0x61...0x7A).contains(bytes[index]) { index += 1 }
        return index == bytes.count && (1...16).contains(index - extensionStart)
    }

    /// Stored name for the n-th item: the extension of the original name (sanitized) or of the content type.
    public static func storedPath(ordinal: Int, preferredExtension: String?) -> String {
        let ext = (preferredExtension ?? "").lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        let trimmed = String(ext.prefix(16))
        return trimmed.isEmpty ? "items/\(ordinal)" : "items/\(ordinal).\(trimmed)"
    }
}

// Decoding is written out (in extensions, so the memberwise initializers stay) only to read the UUIDs in their canonical
// form; every member is required, so JSONDecoder already refuses null for each of them.
extension HandoffManifest {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        handoffID = try container.decodeCanonicalUUID(forKey: .handoffID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        producer = try container.decode(Producer.self, forKey: .producer)
        items = try container.decode([Item].self, forKey: .items)
        totalBytes = try container.decode(UInt64.self, forKey: .totalBytes)
    }
}

extension HandoffManifest.Item {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemID = try container.decodeCanonicalUUID(forKey: .itemID)
        storedPath = try container.decode(String.self, forKey: .storedPath)
        originalFilename = try container.decode(String.self, forKey: .originalFilename)
        contentType = try container.decode(String.self, forKey: .contentType)
        byteCount = try container.decode(UInt64.self, forKey: .byteCount)
        sha256 = try container.decode(String.self, forKey: .sha256)
        representation = try container.decode(HandoffManifest.Representation.self, forKey: .representation)
        providerTypeIdentifier = try container.decode(String.self, forKey: .providerTypeIdentifier)
    }
}

public enum HandoffManifestError: Error, Equatable, Sendable, CustomStringConvertible {
    /// `handoff.json` is larger than `HandoffManifest.maxBytes` (`HandoffManifest.read(contentsOf:)`).
    case tooLarge(limit: Int)
    case unsupportedSchemaVersion(Int)
    case idDoesNotMatchDirectory
    case invalidField(String)
    case unsafeStoredPath
    case duplicateItem
    case totalMismatch

    public var description: String {
        switch self {
        case let .tooLarge(limit): "handoff.json is larger than \(limit) bytes"
        case let .unsupportedSchemaVersion(v): "unsupported schema_version \(v)"
        case .idDoesNotMatchDirectory: "handoff_id does not match its directory"
        case let .invalidField(f): "invalid field \(f)"
        case .unsafeStoredPath: "stored_path is not items/<n>[.<ext>]"
        case .duplicateItem: "duplicate item id or stored_path"
        case .totalMismatch: "total_bytes is not the sum of byte_count"
        }
    }
}
