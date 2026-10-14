import Foundation

/// Decoding rules the manifest readers share so that they refuse what their contract refuses (G0.3 reviews R3-01, R4-01).
public extension KeyedDecodingContainer {
    /// Like `decodeIfPresent`, except that an explicit `null` is an error. No member of the G0.3 contracts admits
    /// null, but `decodeIfPresent` reads null as absent, so a reader built on it accepted `"title": null` and the like,
    /// which the schemas refuse.
    func decodeIfPresentRejectingNull<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
        guard contains(key) else { return nil }
        if try decodeNil(forKey: key) {
            throw DecodingError.valueNotFound(T.self, DecodingError.Context(
                codingPath: codingPath + [key], debugDescription: "explicit null: the contract admits no null here"))
        }
        return try decode(T.self, forKey: key)
    }

    /// A UUID in its canonical text form only (`CanonicalUUID`).
    func decodeCanonicalUUID(forKey key: Key) throws -> UUID {
        let text = try decode(String.self, forKey: key)
        guard let uuid = CanonicalUUID.parse(text) else {
            throw DecodingError.dataCorruptedError(
                forKey: key, in: self, debugDescription: "not a canonical UUID (8-4-4-4-12 hexadecimal digits)")
        }
        return uuid
    }
}

/// An enum value of a contract, matched byte for byte (G0.3 review R4-01).
///
/// Swift's synthesized `init(rawValue:)`, and with it JSONDecoder's decoding of a `String` enum, compares with `String`'s
/// `==`, which treats canonically equivalent text as equal: an enum value "K" also takes U+212A KELVIN SIGN, which JSON
/// Schema's `enum` (code point by code point) refuses (test "platform facts: canonical equivalence"). No enum value of
/// the G0.3 contracts holds ";", "`" or "K", the only ASCII characters a non-ASCII code point is canonically equivalent
/// to, so today this refuses nothing more; it keeps the readers exact if a value ever does.
public func decodeExactCase<T: RawRepresentable & CaseIterable>(_ type: T.Type, from decoder: any Decoder) throws -> T
    where T.RawValue == String {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    guard let match = T.allCases.first(where: { PathBytes.equal($0.rawValue, text) }) else {
        throw DecodingError.dataCorruptedError(
            in: container, debugDescription: "not one of the contract's values (compared byte for byte)")
    }
    return match
}

/// The UUID text form of RFC 4122 section 3 (and JSON Schema's `uuid` format): exactly 36 ASCII characters, hexadecimal
/// digits in groups of 8, 4, 4, 4 and 12 separated by hyphens, either case.
///
/// `UUID(uuidString:)` alone is not enough: on macOS 26.6 and the iOS 26.5 simulator it accepts a canonical UUID
/// followed by U+0000 and anything after it (it stops reading at the NUL), so the readers accepted a `pack_id` such as
/// "5E0D7C1A-2B3F-4A9C-8D7E-6F5A4B3C2D10\u0000junk", which the contract validator refuses.
public enum CanonicalUUID {
    public static func parse(_ text: String) -> UUID? {
        let bytes = Array(text.utf8)
        guard bytes.count == 36 else { return nil }
        for (position, byte) in bytes.enumerated() {
            if position == 8 || position == 13 || position == 18 || position == 23 {
                guard byte == 0x2D else { return nil }
            } else {
                guard (0x30...0x39).contains(byte) || (0x41...0x46).contains(byte) || (0x61...0x66).contains(byte) else {
                    return nil
                }
            }
        }
        return UUID(uuidString: text)
    }
}
