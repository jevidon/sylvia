import Foundation
import Security
import Synchronization

/// Where the phone keeps the per-device pairing token. Tokens are never written to the database,
/// logs, backups or the pasteboard (plan 14.2, 15.2).
public protocol CredentialStore: Sendable {
    func saveToken(_ token: String, sourceID: String) throws
    func token(sourceID: String) throws -> String?
    func deleteToken(sourceID: String) throws
}

/// Keychain storage for transfer credentials (ADR-0008).
///
/// Accessibility is `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: the token must be readable by
/// authorized background transfers while the phone is locked after the first unlock since boot, it
/// never syncs to iCloud Keychain and never migrates to another device through a backup (restoring
/// requires pairing again). AI provider keys use a stricter class (ADR-0008). The item lives in the
/// data protection keychain on both iOS and macOS.
public struct KeychainCredentialStore: CredentialStore {
    public static let defaultService = "com.jevidon.sylvia.transfer.token"
    public let service: String
    public let accessGroup: String?

    public init(service: String = KeychainCredentialStore.defaultService, accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    private func baseQuery(sourceID: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sourceID,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: false,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    public func saveToken(_ token: String, sourceID: String) throws {
        let query = baseQuery(sourceID: sourceID)
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = Data(token.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func token(sourceID: String) throws -> String? {
        var query = baseQuery(sourceID: sourceID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return String(decoding: data, as: UTF8.self)
    }

    public func deleteToken(sourceID: String) throws {
        let status = SecItemDelete(baseQuery(sourceID: sourceID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    /// The stored accessibility class, for verification (`kSecAttrAccessible` value as a string).
    public func storedAccessibility(sourceID: String) throws -> String? {
        var query = baseQuery(sourceID: sourceID)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let attributes = result as? [String: Any] else {
            throw KeychainError(status: status)
        }
        return attributes[kSecAttrAccessible as String] as? String
    }
}

public struct KeychainError: Error, Equatable, Sendable {
    public let status: OSStatus
}

/// For host tests and the command-line client: tokens live only in process memory.
public final class InMemoryCredentialStore: CredentialStore {
    private let tokens = Mutex<[String: String]>([:])
    public init() {}
    public func saveToken(_ token: String, sourceID: String) throws { tokens.withLock { $0[sourceID] = token } }
    public func token(sourceID: String) throws -> String? { tokens.withLock { $0[sourceID] } }
    public func deleteToken(sourceID: String) throws { tokens.withLock { _ = $0.removeValue(forKey: sourceID) } }
}
