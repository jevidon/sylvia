import Crypto
import Foundation
import Security
import SwiftASN1
import SylviaTransferCore
import Synchronization
import X509

/// The Mac's TLS identity: a P-256 key and a self-signed X.509 certificate for it (ADR-0008).
/// Phones trust the SHA-256 of the certificate's SubjectPublicKeyInfo, learned from the pairing payload.
public struct SourceIdentity: Sendable {
    public let sourceID: String
    public let privateKey: P256.Signing.PrivateKey
    public let certificateDER: [UInt8]
    public let pin: SPKIPin

    /// Generates a new key and a certificate valid for ten years. The validity period is not what the
    /// phone checks (it pins the key), but it is set so standard tools can inspect the certificate.
    public static func generate(sourceID: String, now: Date = Date()) throws -> SourceIdentity {
        try make(sourceID: sourceID, privateKey: P256.Signing.PrivateKey(), now: now)
    }

    static func make(sourceID: String, privateKey: P256.Signing.PrivateKey, now: Date) throws -> SourceIdentity {
        let name = try DistinguishedName {
            CommonName("Sylvia source \(sourceID)")
            OrganizationName("Sylvia (self-signed, pinned by SPKI)")
        }
        let serial = Certificate.SerialNumber(bytes: ArraySlice(secureRandomBytes(count: 16).map { $0 & 0x7f }))
        let certificate = try Certificate(
            version: .v3,
            serialNumber: serial,
            publicKey: .init(privateKey.publicKey),
            notValidBefore: now.addingTimeInterval(-3600),
            notValidAfter: now.addingTimeInterval(10 * 365 * 24 * 3600),
            issuer: name,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                Critical(KeyUsage(digitalSignature: true))
                try ExtendedKeyUsage([.serverAuth])
            },
            issuerPrivateKey: .init(privateKey))
        var serializer = DER.Serializer()
        try serializer.serialize(certificate)
        let der = serializer.serializedBytes
        return SourceIdentity(sourceID: sourceID, privateKey: privateKey, certificateDER: der, pin: try SPKIPin(certificateDER: der))
    }
}

/// Where the identity lives. The private key is a secret; the certificate and source ID are not.
public protocol IdentityStore: Sendable {
    /// Returns the stored identity, creating one on first use.
    func loadOrCreate(now: Date) throws -> (identity: SourceIdentity, created: Bool)
    /// Deletes the identity. The next start creates a new key, so every phone must pair again.
    func reset() throws
}

/// Keeps the private key in the macOS Keychain and the public certificate in the state directory.
///
/// The key is a generic-password item (raw 32-byte P-256 scalar), `kSecAttrSynchronizable` false, in the
/// data protection keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (what the signed
/// companion app gets). That keychain needs a keychain access group, which only a signed app has.
///
/// The fallback to the login (file-based) keychain, where the item is protected by the keychain's lock and
/// the creating application's access control list, is opt-in (`Policy.allowLoginKeychainFallback`): only the
/// unsigned command-line tools use it, and they print which keychain they used. By default a missing
/// entitlement is an error, so a signed companion with a misconfigured access group fails loudly instead of
/// silently keeping its key in the weaker store (review finding R1-11). `lastBackend` reports the store used.
public final class KeychainIdentityStore: IdentityStore {
    public enum Backend: String, Sendable {
        case dataProtection = "data-protection keychain"
        case login = "login keychain (file-based)"
    }

    public enum Policy: Sendable {
        /// Only the data protection keychain; errSecMissingEntitlement is thrown (the companion app).
        case dataProtectionOnly
        /// The data protection keychain, else the login keychain (unsigned command-line tools and tests,
        /// which must report `lastBackend`).
        case allowLoginKeychainFallback
    }

    public let service: String
    public let stateDirectory: URL
    public let policy: Policy
    private let backend = Mutex<Backend?>(nil)

    public init(service: String = "com.jevidon.sylvia.source.identity", stateDirectory: URL, policy: Policy = .dataProtectionOnly) {
        self.service = service
        self.stateDirectory = stateDirectory
        self.policy = policy
    }

    /// The keychains this store may use, in order (true: data protection keychain).
    private var keychains: [Bool] { policy == .dataProtectionOnly ? [true] : [true, false] }

    public var lastBackend: Backend? { backend.withLock { $0 } }

    struct PublicPart: Codable {
        var sourceID: String
        var certificateDER: String
        enum CodingKeys: String, CodingKey {
            case sourceID = "source_id"
            case certificateDER = "certificate_der_base64"
        }
    }

    var publicPartURL: URL { stateDirectory.appendingPathComponent("identity.json") }

    public func loadOrCreate(now: Date) throws -> (identity: SourceIdentity, created: Bool) {
        if let stored = try DurableFile.read(PublicPart.self, from: publicPartURL),
            let der = Data(base64Encoded: stored.certificateDER),
            let keyBytes = try readKey(account: stored.sourceID)
        {
            let key = try P256.Signing.PrivateKey(rawRepresentation: keyBytes)
            let pin = try SPKIPin(certificateDER: [UInt8](der))
            // The stored certificate must belong to the stored key; otherwise start over.
            let certificate = try Certificate(derEncoded: [UInt8](der))
            if certificate.publicKey == Certificate.PublicKey(key.publicKey) {
                return (SourceIdentity(sourceID: stored.sourceID, privateKey: key, certificateDER: [UInt8](der), pin: pin), false)
            }
        }
        try reset()
        let identity = try SourceIdentity.generate(sourceID: CanonicalID.make(), now: now)
        try writeKey(identity.privateKey.rawRepresentation, account: identity.sourceID)
        try DurableFile.write(
            PublicPart(sourceID: identity.sourceID, certificateDER: Data(identity.certificateDER).base64EncodedString()),
            to: publicPartURL)
        return (identity, true)
    }

    public func reset() throws {
        for dataProtection in keychains {
            var query = baseQuery(dataProtection: dataProtection)
            query.removeValue(forKey: kSecAttrAccount as String)
            let status = SecItemDelete(query as CFDictionary)
            let tolerated = status == errSecSuccess || status == errSecItemNotFound
                || (status == errSecMissingEntitlement && policy == .allowLoginKeychainFallback)
            guard tolerated else { throw KeychainStatusError(status: status) }
        }
        try? FileManager.default.removeItem(at: publicPartURL)
    }

    private func baseQuery(dataProtection: Bool, account: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false,
        ]
        if let account { query[kSecAttrAccount as String] = account }
        if dataProtection { query[kSecUseDataProtectionKeychain as String] = true }
        return query
    }

    private func writeKey(_ key: Data, account: String) throws {
        for dataProtection in keychains {
            var attributes = baseQuery(dataProtection: dataProtection, account: account)
            attributes[kSecValueData as String] = key
            attributes[kSecAttrLabel as String] = "Sylvia source identity key"
            if dataProtection {
                attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            }
            let status = SecItemAdd(attributes as CFDictionary, nil)
            if status == errSecSuccess {
                backend.withLock { $0 = dataProtection ? .dataProtection : .login }
                return
            }
            if dataProtection, status == errSecMissingEntitlement, policy == .allowLoginKeychainFallback { continue }
            throw KeychainStatusError(status: status)
        }
        throw KeychainStatusError(status: errSecMissingEntitlement)
    }

    private func readKey(account: String) throws -> Data? {
        for dataProtection in keychains {
            var query = baseQuery(dataProtection: dataProtection, account: account)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecSuccess, let data = result as? Data {
                backend.withLock { $0 = dataProtection ? .dataProtection : .login }
                return data
            }
            if status == errSecItemNotFound { continue }
            if status == errSecMissingEntitlement, dataProtection, policy == .allowLoginKeychainFallback { continue }
            throw KeychainStatusError(status: status)
        }
        return nil
    }
}

public struct KeychainStatusError: Error, Equatable, Sendable {
    public let status: OSStatus
    public init(status: OSStatus) { self.status = status }
}

/// Keeps the identity in memory only: tests and scripted runs, so nothing touches the Keychain and no
/// Keychain access prompt can block an unattended run. It is still a real key and certificate; TLS and
/// pinning work exactly as with the Keychain store.
public final class EphemeralIdentityStore: IdentityStore {
    private let identity = Mutex<SourceIdentity?>(nil)
    /// Set by `rotateKeyKeepingSourceID`: the next load reports a newly created key.
    private let rotated = Mutex(false)
    public init() {}

    public func loadOrCreate(now: Date) throws -> (identity: SourceIdentity, created: Bool) {
        let wasRotated = rotated.withLock { value -> Bool in
            defer { value = false }
            return value
        }
        return try identity.withLock { stored in
            if let stored { return (stored, wasRotated) }
            let created = try SourceIdentity.generate(sourceID: CanonicalID.make(), now: now)
            stored = created
            return (created, true)
        }
    }

    /// Replaces the key but keeps the source ID: what a reinstalled or reset Mac looks like to a phone.
    public func rotateKeyKeepingSourceID(now: Date = Date()) throws {
        try identity.withLock { stored in
            let sourceID = stored?.sourceID ?? CanonicalID.make()
            stored = try SourceIdentity.generate(sourceID: sourceID, now: now)
        }
        rotated.withLock { $0 = true }
    }

    public func reset() throws { identity.withLock { $0 = nil } }
}
