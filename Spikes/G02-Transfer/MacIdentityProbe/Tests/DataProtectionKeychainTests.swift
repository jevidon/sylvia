import Foundation
import Security
import SylviaSourceService
import Testing

/// Runs inside the signed probe app (keychain access group from Config/Probe.entitlements): the Mac source's
/// identity store with its default policy must put the key in the data protection keychain with
/// kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, not synchronizable, and nowhere else (ADR-0008).
/// Lines starting with "G02-PROBE" are copied into the evidence by mac-identity-probe-run.sh.
@Suite("Signed Mac identity store (ADR-0008, R1-11)")
struct DataProtectionKeychainTests {
    @Test func identityKeyIsInTheDataProtectionKeychainAfterFirstUnlockThisDeviceOnly() throws {
        let state = FileManager.default.temporaryDirectory.appendingPathComponent("g02-probe-\(UUID().uuidString)")
        let service = "com.jevidon.sylvia.spike.identityprobe.test.\(UUID().uuidString)"
        let store = KeychainIdentityStore(service: service, stateDirectory: state)
        #expect(store.policy == .dataProtectionOnly)
        defer {
            try? store.reset()
            try? FileManager.default.removeItem(at: state)
        }
        let (created, isNew) = try store.loadOrCreate(now: Date())
        #expect(isNew)
        #expect(store.lastBackend == .dataProtection)

        let items = try Self.items(service: service, dataProtection: true)
        try #require(items.count == 1)
        let item = items[0]
        let accessible = item[kSecAttrAccessible as String] as? String
        let group = item[kSecAttrAccessGroup as String] as? String ?? "none"
        let synchronizable = (item[kSecAttrSynchronizable as String] as? NSNumber)?.boolValue ?? false
        #expect(accessible == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String))
        #expect(!synchronizable)
        #expect(group.hasSuffix(".com.jevidon.sylvia.spike.identityprobe"))
        // Not in the file-based (login) keychain.
        let legacy = try Self.items(service: service, dataProtection: false)
        #expect(legacy.isEmpty)

        let (reloaded, isNewAgain) = try store.loadOrCreate(now: Date())
        #expect(!isNewAgain && reloaded.pin == created.pin && reloaded.sourceID == created.sourceID)
        #expect(store.lastBackend == .dataProtection)

        print("G02-PROBE backend: \(store.lastBackend?.rawValue ?? "none")")
        print("G02-PROBE kSecAttrAccessible: \(accessible ?? "none") (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly is \(kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String))")
        print("G02-PROBE kSecAttrSynchronizable: \(synchronizable)")
        print("G02-PROBE kSecAttrAccessGroup: \(group)")
        print("G02-PROBE items for the service in the login (file-based) keychain: \(legacy.count)")
        print("G02-PROBE reloaded the same identity (same SPKI pin and source ID): \(reloaded.pin == created.pin)")
    }

    static func items(service: String, dataProtection: Bool) throws -> [[String: Any]] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        if dataProtection { query[kSecUseDataProtectionKeychain as String] = true }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw KeychainStatusError(status: status) }
        return result as? [[String: Any]] ?? []
    }
}
