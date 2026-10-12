import Foundation

/// The protocol version this build speaks (ADR-0009). Paths carry the major version (`/v1/...`);
/// a different major is rejected with an update message, additive minor changes are tolerated.
public enum TransferProtocol {
    public static let major = 1
    public static let minor = 0
    public static let version = ProtocolVersion(major: major, minor: minor)

    /// Part size limits (plan 15.4: 16 MiB default, negotiable through capabilities).
    public static let mebibyte: Int64 = 1_048_576
    public static let defaultPartSize: Int64 = 16 * mebibyte
    public static let minimumPartSize: Int64 = 1 * mebibyte
    public static let maximumPartSize: Int64 = 64 * mebibyte

    /// Metadata and part-count limits (A.3: "Limit metadata sizes and part counts").
    public static let maximumPartsPerAsset = 16_384
    public static let maximumPartsPerManifest = 65_536
    public static let maximumAssetsPerItem = 4_096
    /// Largest exactly representable integer in JSON consumers that use binary64 numbers.
    public static let maximumAssetLength: Int64 = 9_007_199_254_740_991
    public static let maximumTitleLength = 512
    public static let maximumDisplayNameLength = 255
    public static let maximumCreators = 16
    public static let maximumPageLimit = 200
    public static let defaultPageLimit = 50
    public static let maximumRequestBodyBytes = 65_536

    /// Token scopes (plan 15.2). There is deliberately no scope for deletion or arbitrary file access.
    public static let allScopes: [Scope] = [.catalog, .read, .download, .receipt]
}

public struct ProtocolVersion: Codable, Hashable, Sendable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }
    public var description: String { "\(major).\(minor)" }
}

public enum Scope: String, Codable, Hashable, Sendable, CaseIterable {
    case catalog
    case read
    case download
    case receipt
}

/// JSON coding shared by both ends: RFC 3339 UTC timestamps, whole seconds on output; fractional
/// seconds and numeric offsets accepted on input. Keys are spelled out in each type's CodingKeys.
public enum TransferJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(RFC3339.format(date))
        }
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = RFC3339.parse(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "not an RFC 3339 timestamp")
            }
            return date
        }
        return decoder
    }

    public static func encode<T: Encodable>(_ value: T) throws -> Data { try encoder().encode(value) }
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder().decode(type, from: data)
    }
}

public enum RFC3339 {
    public static func format(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: TimeZone(identifier: "UTC")!))
    }

    public static func parse(_ text: String) -> Date? {
        let whole = Date.ISO8601FormatStyle()
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return (try? whole.parse(text)) ?? (try? fractional.parse(text))
    }
}
