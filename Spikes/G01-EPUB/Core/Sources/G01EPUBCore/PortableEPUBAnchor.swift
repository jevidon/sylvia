import Foundation

/// Proposed portable EPUB anchor (plan 7.5, Appendix A.1), written from the G0.1 evidence for the later anchor
/// schema. Everything outside `reader` is Sylvia's own and portable; `reader.locator` is the Readium locator kept
/// verbatim as adapter-opaque JSON.
public struct PortableEPUBAnchor: Codable, Sendable, Equatable {
    public struct TextOffsetSpan: Codable, Sendable, Equatable {
        /// Always "unicode_scalar" for Sylvia-extracted text (Contracts/README.md units rule).
        public var unit: String
        /// What the offsets index: the extracted text of `resource_href` produced by `extraction_version`.
        public var basis: String
        public var extractionVersion: String
        /// Index of the block (paragraph-level element) inside that extraction.
        public var blockIndex: Int
        public var start: Int
        public var end: Int

        public init(unit: String, basis: String, extractionVersion: String, blockIndex: Int, start: Int, end: Int) {
            self.unit = unit
            self.basis = basis
            self.extractionVersion = extractionVersion
            self.blockIndex = blockIndex
            self.start = start
            self.end = end
        }

        enum CodingKeys: String, CodingKey {
            case unit, basis, start, end
            case extractionVersion = "extraction_version"
            case blockIndex = "block_index"
        }
    }

    public struct Segment: Codable, Sendable, Equatable {
        /// Position of this anchor in a quotation that crosses resources (0-based) and the number of anchors.
        public var index: Int
        public var count: Int

        public init(index: Int, count: Int) {
            self.index = index
            self.count = count
        }
    }

    public struct Reader: Codable, Sendable, Equatable {
        public var adapter: String
        public var adapterVersion: String
        /// The reader's locator JSON, stored verbatim. Never interpreted outside the adapter.
        public var locator: JSONValue

        public init(adapter: String, adapterVersion: String, locator: JSONValue) {
            self.adapter = adapter
            self.adapterVersion = adapterVersion
            self.locator = locator
        }

        enum CodingKeys: String, CodingKey {
            case adapter, locator
            case adapterVersion = "adapter_version"
        }
    }

    public var version: Int = 1
    public var kind: String = "epub"
    public var assetID: String
    public var assetDigest: String
    public var resourceHref: String
    public var resourceMediaType: String?
    public var exactText: String
    public var prefix: String
    public var suffix: String
    public var textOffsets: TextOffsetSpan?
    public var progression: Double?
    public var totalProgression: Double?
    public var position: Int?
    public var segment: Segment?
    public var reader: Reader

    enum CodingKeys: String, CodingKey {
        case version, kind, prefix, suffix, progression, position, segment, reader
        case assetID = "asset_id"
        case assetDigest = "asset_digest"
        case resourceHref = "resource_href"
        case resourceMediaType = "resource_media_type"
        case exactText = "exact_text"
        case textOffsets = "text_offsets"
        case totalProgression = "total_progression"
    }

    public init(assetID: String, assetDigest: String, resourceHref: String, resourceMediaType: String?, exactText: String,
                prefix: String, suffix: String, textOffsets: TextOffsetSpan?, progression: Double?, totalProgression: Double?,
                position: Int?, segment: Segment?, reader: Reader) {
        self.assetID = assetID
        self.assetDigest = assetDigest
        self.resourceHref = resourceHref
        self.resourceMediaType = resourceMediaType
        self.exactText = exactText
        self.prefix = prefix
        self.suffix = suffix
        self.textOffsets = textOffsets
        self.progression = progression
        self.totalProgression = totalProgression
        self.position = position
        self.segment = segment
        self.reader = reader
    }
}

/// Minimal JSON value so opaque reader payloads round-trip byte-for-byte in meaning.
public enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case let .bool(b): try c.encode(b)
        case let .number(n): try c.encode(n)
        case let .string(s): try c.encode(s)
        case let .array(a): try c.encode(a)
        case let .object(o): try c.encode(o)
        }
    }

    public init(jsonString: String) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: Data(jsonString.utf8))
    }

    public subscript(key: String) -> JSONValue? {
        if case let .object(o) = self { return o[key] }
        return nil
    }

    public var stringValue: String? {
        if case let .string(s) = self { return s }
        return nil
    }

    public var numberValue: Double? {
        if case let .number(n) = self { return n }
        return nil
    }
}
