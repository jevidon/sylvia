import CryptoKit
import Foundation

/// Byte encodings and digest helpers shared by the source service and the client.
///
/// Digests are lowercase hex SHA-256 (Contracts/README.md, "Units"). Secrets and tokens travel as
/// unpadded base64url (RFC 4648 section 5).
public enum Hex {
    private static let digits: [UInt8] = Array("0123456789abcdef".utf8)

    public static func encode<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
        var out = [UInt8]()
        out.reserveCapacity(bytes.underestimatedCount * 2)
        for byte in bytes {
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 0x0F)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Decodes lowercase hex only. Uppercase, odd length or any other character returns nil.
    public static func decodeLowercase(_ text: String) -> [UInt8]? {
        let utf8 = Array(text.utf8)
        guard utf8.count % 2 == 0 else { return nil }
        var out = [UInt8]()
        out.reserveCapacity(utf8.count / 2)
        var index = 0
        while index < utf8.count {
            guard let high = nibble(utf8[index]), let low = nibble(utf8[index + 1]) else { return nil }
            out.append(high << 4 | low)
            index += 2
        }
        return out
    }

    private static func nibble(_ char: UInt8) -> UInt8? {
        switch char {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return char - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return char - UInt8(ascii: "a") + 10
        default: return nil
        }
    }

    /// True for exactly 64 lowercase hex characters (a SHA-256 digest).
    public static func isSHA256(_ text: String) -> Bool {
        text.utf8.count == 64 && decodeLowercase(text) != nil
    }
}

public enum Base64URL {
    public static func encode<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
        Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Decodes unpadded base64url. Padding, whitespace, or standard-alphabet characters return nil.
    public static func decode(_ text: String) -> [UInt8]? {
        guard !text.isEmpty else { return [] }
        for scalar in text.unicodeScalars {
            switch scalar {
            case "A"..."Z", "a"..."z", "0"..."9", "-", "_": continue
            default: return nil
            }
        }
        guard text.utf8.count % 4 != 1 else { return nil }
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.utf8.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64) else { return nil }
        // Reject non-canonical encodings (trailing bits set), so one value has one spelling.
        guard encode(data) == text else { return nil }
        return [UInt8](data)
    }
}

public enum SHA256Hex {
    public static func digest<D: DataProtocol>(_ data: D) -> String {
        Hex.encode(SHA256.hash(data: data))
    }
}

/// Compares two byte sequences in time that depends only on their lengths.
public func constantTimeEquals<A: Collection, B: Collection>(_ lhs: A, _ rhs: B) -> Bool
where A.Element == UInt8, B.Element == UInt8 {
    guard lhs.count == rhs.count else { return false }
    var difference: UInt8 = 0
    for (left, right) in zip(lhs, rhs) { difference |= left ^ right }
    return difference == 0
}

/// Cryptographically secure random bytes from the system generator.
public func secureRandomBytes(count: Int) -> [UInt8] {
    var generator = SystemRandomNumberGenerator()
    return (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
}

/// Canonical UUID text form used by every Sylvia identifier on the wire: lowercase, hyphenated.
public enum CanonicalID {
    public static func isValid(_ text: String) -> Bool {
        guard text.utf8.count == 36, let uuid = UUID(uuidString: text) else { return false }
        return uuid.uuidString.lowercased() == text
    }

    public static func make() -> String { UUID().uuidString.lowercased() }
}
