import Foundation
import Security
import Testing
import SylviaTransferClient

/// Hosted on the iOS simulator (an app's keychain access group is required). Proves the transfer token
/// is stored with after-first-unlock, this-device-only accessibility, never synchronizable, and can be
/// replaced and deleted. Behavior across reboot and lock needs a device and is a checklist item
/// (Docs/Stage0/device-checklists/G02-Transfer.md), not inferred from this test.
@Suite("Transfer credential Keychain storage (14.2)")
struct KeychainCredentialStoreTests {
    let store = KeychainCredentialStore(service: "com.jevidon.sylvia.spike.transfer-test.\(UUID().uuidString)")

    @Test func storesTokenAfterFirstUnlockThisDeviceOnly() throws {
        let source = UUID().uuidString.lowercased()
        defer { try? store.deleteToken(sourceID: source) }
        try store.saveToken("token-for-test", sourceID: source)
        #expect(try store.token(sourceID: source) == "token-for-test")
        #expect(try store.storedAccessibility(sourceID: source) == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String))
    }

    @Test func itemIsNotSynchronizable() throws {
        let source = UUID().uuidString.lowercased()
        defer { try? store.deleteToken(sourceID: source) }
        try store.saveToken("token-for-test", sourceID: source)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: store.service,
            kSecAttrAccount as String: source,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        #expect(SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess)
        let items = try #require(result as? [[String: Any]])
        #expect(items.count == 1)
        let synchronizable = items.first?[kSecAttrSynchronizable as String] as? NSNumber
        #expect(synchronizable?.boolValue != true)
    }

    @Test func replaceAndDelete() throws {
        let source = UUID().uuidString.lowercased()
        try store.saveToken("first", sourceID: source)
        try store.saveToken("second", sourceID: source)
        #expect(try store.token(sourceID: source) == "second")
        try store.deleteToken(sourceID: source)
        #expect(try store.token(sourceID: source) == nil)
        try store.deleteToken(sourceID: source)  // deleting twice is not an error
    }
}
