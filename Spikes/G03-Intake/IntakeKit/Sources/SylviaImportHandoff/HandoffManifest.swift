import Foundation
import SylviaIntakeCore

/// `handoff.json`: the share extension's commit record (contract `import-handoff-manifest` v1,
/// Contracts/schemas/import-handoff-manifest.v1.schema.json). It is written atomically and last; a handoff
/// directory without it is incomplete by definition.
public struct HandoffManifest: Codable, Equatable, Sendable {
    public static let fileName = "handoff.json"
    public static let schemaVersion = 1
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

    public enum Representation: String, Codable, Sendable {
        /// NSItemProvider file representation of a supported content type.
        case fileRepresentation = "file_representation"
        /// A `public.file-url` item pointing at a file the extension could read.
        case fileURL = "file_url"
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

    public static func decode(_ data: Data) throws -> HandoffManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HandoffManifest.self, from: data)
    }

    /// Structural checks beyond JSON decoding. `directoryName` is the handoff directory's name.
    public func validate(directoryName: String) throws(HandoffManifestError) {
        guard schemaVersion == HandoffManifest.schemaVersion else { throw .unsupportedSchemaVersion(schemaVersion) }
        guard UUID(uuidString: directoryName) == handoffID else { throw .idDoesNotMatchDirectory }
        guard producer.kind == "share_extension" else { throw .invalidField("producer.kind") }
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
            guard !item.originalFilename.isEmpty, item.originalFilename.utf8.count <= 255,
                  !item.originalFilename.contains("/"), !item.originalFilename.contains("\u{0}") else {
                throw .invalidField("original_filename")
            }
            guard !item.contentType.isEmpty, item.contentType.utf8.count <= 128 else { throw .invalidField("content_type") }
            let (partial, overflow) = sum.addingReportingOverflow(item.byteCount)
            guard !overflow else { throw .invalidField("byte_count") }
            sum = partial
        }
        guard sum == totalBytes else { throw .totalMismatch }
    }

    /// `items/<decimal>` optionally followed by `.<1-16 lowercase alphanumerics>`. Nothing else is accepted, so a
    /// tampered manifest cannot point outside its own directory.
    public static func isValidStoredPath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "items" else { return false }
        let name = parts[1]
        let pieces = name.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 1 || pieces.count == 2 else { return false }
        let number = pieces[0]
        guard (1...4).contains(number.count), number.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        if pieces.count == 2 {
            let ext = pieces[1]
            guard (1...16).contains(ext.count),
                  ext.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber) }) else { return false }
        }
        return true
    }

    /// Stored name for the n-th item: the extension of the original name (sanitized) or of the content type.
    public static func storedPath(ordinal: Int, preferredExtension: String?) -> String {
        let ext = (preferredExtension ?? "").lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        let trimmed = String(ext.prefix(16))
        return trimmed.isEmpty ? "items/\(ordinal)" : "items/\(ordinal).\(trimmed)"
    }
}

public enum HandoffManifestError: Error, Equatable, Sendable, CustomStringConvertible {
    case unsupportedSchemaVersion(Int)
    case idDoesNotMatchDirectory
    case invalidField(String)
    case unsafeStoredPath
    case duplicateItem
    case totalMismatch

    public var description: String {
        switch self {
        case let .unsupportedSchemaVersion(v): "unsupported schema_version \(v)"
        case .idDoesNotMatchDirectory: "handoff_id does not match its directory"
        case let .invalidField(f): "invalid field \(f)"
        case .unsafeStoredPath: "stored_path is not items/<n>[.<ext>]"
        case .duplicateItem: "duplicate item id or stored_path"
        case .totalMismatch: "total_bytes is not the sum of byte_count"
        }
    }
}
