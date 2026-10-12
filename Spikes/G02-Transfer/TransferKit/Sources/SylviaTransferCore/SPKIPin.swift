import CryptoKit
import Foundation
internal import SwiftASN1

/// The trust anchor for a paired source: SHA-256 over the DER encoding of the certificate's
/// SubjectPublicKeyInfo (the same value as `openssl x509 -pubkey | openssl pkey -pubin -outform der | sha256`).
///
/// Pinning the key rather than the certificate lets the source re-issue its self-signed certificate
/// without re-pairing, while a new key always requires re-pairing (plan 15.2).
public struct SPKIPin: Hashable, Sendable, CustomStringConvertible {
    public let digest: [UInt8]

    public init(digest: [UInt8]) throws {
        guard digest.count == 32 else { throw SPKIPinError.invalidDigestLength }
        self.digest = digest
    }

    public init(hex: String) throws {
        guard Hex.isSHA256(hex), let bytes = Hex.decodeLowercase(hex) else { throw SPKIPinError.invalidHex }
        try self.init(digest: bytes)
    }

    /// Computes the pin of an X.509 certificate given as DER.
    public init(certificateDER: [UInt8]) throws {
        let spki = try SPKIPin.subjectPublicKeyInfoDER(fromCertificateDER: certificateDER)
        try self.init(digest: Array(SHA256.hash(data: spki)))
    }

    public var hex: String { Hex.encode(digest) }

    /// The fingerprint shown to people: uppercase hex in groups of four, in the Monospace face (plan 15.2).
    public var displayFingerprint: String { Fingerprint.grouped(hex) }

    public var description: String { "SPKIPin(\(hex))" }

    /// Constant-time match against a certificate presented by a peer.
    public func matches(certificateDER: [UInt8]) -> Bool {
        guard let other = try? SPKIPin(certificateDER: certificateDER) else { return false }
        return constantTimeEquals(digest, other.digest)
    }

    /// Extracts the exact DER bytes of `tbsCertificate.subjectPublicKeyInfo` (RFC 5280 section 4.1).
    public static func subjectPublicKeyInfoDER(fromCertificateDER der: [UInt8]) throws -> ArraySlice<UInt8> {
        let root: ASN1Node
        do { root = try DER.parse(der) } catch { throw SPKIPinError.malformedCertificate }
        guard root.identifier == .sequence, case .constructed(let certificateFields) = root.content else {
            throw SPKIPinError.malformedCertificate
        }
        var fields = certificateFields.makeIterator()
        guard let tbs = fields.next(), tbs.identifier == .sequence, case .constructed(let tbsFields) = tbs.content else {
            throw SPKIPinError.malformedCertificate
        }
        var iterator = tbsFields.makeIterator()
        guard var node = iterator.next() else { throw SPKIPinError.malformedCertificate }
        // Optional [0] EXPLICIT version.
        if node.identifier == ASN1Identifier(tagWithNumber: 0, tagClass: .contextSpecific) {
            guard let next = iterator.next() else { throw SPKIPinError.malformedCertificate }
            node = next
        }
        // serialNumber INTEGER, signature AlgorithmIdentifier, issuer Name, validity, subject Name.
        guard node.identifier == .integer else { throw SPKIPinError.malformedCertificate }
        for expected in [ASN1Identifier.sequence, .sequence, .sequence, .sequence] {
            guard let next = iterator.next(), next.identifier == expected else { throw SPKIPinError.malformedCertificate }
        }
        guard let spki = iterator.next(), spki.identifier == .sequence, case .constructed = spki.content else {
            throw SPKIPinError.malformedCertificate
        }
        return spki.encodedBytes
    }
}

public enum SPKIPinError: Error, Equatable, Sendable {
    case invalidDigestLength
    case invalidHex
    case malformedCertificate
}

public enum Fingerprint {
    /// "ab12cd34..." becomes "AB12 CD34 ...".
    public static func grouped(_ hex: String) -> String {
        let upper = Array(hex.uppercased())
        return stride(from: 0, to: upper.count, by: 4)
            .map { String(upper[$0..<min($0 + 4, upper.count)]) }
            .joined(separator: " ")
    }
}
