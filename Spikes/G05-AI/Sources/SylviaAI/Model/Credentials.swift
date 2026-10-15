import Foundation
import Security

/// A provider credential in memory. It is not Codable, and every textual representation is redacted, so it
/// cannot reach a persisted model, a log line or an error message by accident (plan 14.2, 18.1).
public struct Secret: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private let value: String

    public init(_ value: String) { self.value = value }

    /// The only way to read the value. Call sites are the request builders that set an auth header.
    public func revealForAuthorizationHeader() -> String { value }

    public var description: String { "<redacted>" }
    public var debugDescription: String { "<redacted>" }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
    public var isEmpty: Bool { value.isEmpty }
}

public enum CredentialStoreError: Error, Equatable, Sendable {
    case notFound
    case unavailableWhileLocked
    case keychain(OSStatus)
}

/// Credentials live only in a Keychain-backed store (plan 14.2). Host tests use `InMemoryCredentialStore` from
/// G05TestSupport, which this module does not contain.
public protocol CredentialStore: Sendable {
    func save(_ secret: Secret, for ref: CredentialRef) throws(CredentialStoreError)
    func secret(for ref: CredentialRef) throws(CredentialStoreError) -> Secret
    func delete(_ ref: CredentialRef) throws(CredentialStoreError)
}

/// Keychain store for AI credentials.
///
/// Accessibility is `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: AI requests are foreground work in v1
/// (plan 14.4), so the key is not needed while the device is locked, never syncs to iCloud Keychain and does
/// not migrate through device backups (plan 14.2). Behaviour after reboot and lock is a device check
/// (Docs/Stage0/device-checklists/G05-AI.md).
public struct KeychainCredentialStore: CredentialStore {
    public let service: String

    public init(service: String = "com.jevidon.sylvia.spike.ai-credentials") {
        self.service = service
    }

    /// The item's account attribute: the reference's account and the origin the key was entered for. The origin is part
    /// of the item's identity (service and account), so a reference naming another origin finds no key (plan 18.1).
    public static func accountAttribute(_ ref: CredentialRef) -> String { "\(ref.account.uuidString) \(ref.origin)" }

    private func baseQuery(_ ref: CredentialRef) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.accountAttribute(ref),
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecUseDataProtectionKeychain as String: kCFBooleanTrue as Any,
        ]
    }

    public func save(_ secret: Secret, for ref: CredentialRef) throws(CredentialStoreError) {
        let data = Data(secret.revealForAuthorizationHeader().utf8)
        var query = baseQuery(ref)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            query.merge(update) { _, new in new }
            status = SecItemAdd(query as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw .keychain(status) }
    }

    public func secret(for ref: CredentialRef) throws(CredentialStoreError) -> Secret {
        var query = baseQuery(ref)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw .notFound }
            return Secret(value)
        case errSecItemNotFound: throw .notFound
        case errSecInteractionNotAllowed: throw .unavailableWhileLocked
        default: throw .keychain(status)
        }
    }

    public func delete(_ ref: CredentialRef) throws(CredentialStoreError) {
        let status = SecItemDelete(baseQuery(ref) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw .keychain(status) }
    }

    /// Reads back the accessibility class actually stored, for evidence.
    public func storedAccessibility(for ref: CredentialRef) -> String? {
        var query = baseQuery(ref)
        query[kSecReturnAttributes as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let attributes = result as? [String: Any] else { return nil }
        return attributes[kSecAttrAccessible as String] as? String
    }
}
