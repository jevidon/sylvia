import Foundation
import Security
import SylviaSourceService
import Testing

/// Runs inside the signed probe app (keychain access group from Config/Probe.entitlements): the Mac source's
/// identity store with its default policy must put the key in the data protection keychain with
/// kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, not synchronizable, and nowhere else (ADR-0008).
/// "Nowhere else" is looked for in the file-based keychains only, named in the query (kSecUseDataProtectionKeychain
/// false and the user's keychain search list in kSecMatchSearchList), and a control item shows that check counting a
/// file-based item. A query without kSecUseDataProtectionKeychain also returns the data protection keychain's items to
/// this signed app (macOS 26.6.2), so the first signed run counted the key itself as a login-keychain copy
/// (Docs/Stage0/evidence/G02-Transfer/probe-fix/README.md).
/// Lines starting with "G02-PROBE" are copied into the evidence by mac-identity-probe-run.sh.
@Suite("Signed Mac identity store (ADR-0008, R1-11)")
struct DataProtectionKeychainTests {
    enum Keychains {
        /// The data protection keychain, synchronizable items included (kSecAttrSynchronizableAny): without that value
        /// a query returns no synchronizable item (SecItem.h), so a synchronizable copy would go unseen.
        case dataProtection
        /// The file-based keychains only: kSecUseDataProtectionKeychain false and these keychains in kSecMatchSearchList.
        case fileBased([SecKeychain])
    }

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

        let items = try Self.items(service: service, in: .dataProtection)
        try #require(items.count == 1)
        let item = items[0]
        let accessible = item[kSecAttrAccessible as String] as? String
        let group = item[kSecAttrAccessGroup as String] as? String ?? "none"
        let synchronizable = (item[kSecAttrSynchronizable as String] as? NSNumber)?.boolValue ?? false
        #expect(accessible == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String))
        #expect(!synchronizable)
        #expect(group.hasSuffix(".com.jevidon.sylvia.spike.identityprobe"))
        // Nowhere else: no item for the service in the file-based keychains (the login keychain and the rest of the
        // user's search list). The query names them: without kSecUseDataProtectionKeychain it also returns the data
        // protection item above, which is what the first signed run counted.
        let searchList = try SecKeychainSearchList.current.keychains()
        let fileBasedKeychains = Keychains.fileBased(searchList.map(\.keychain))
        let fileBased = try Self.items(service: service, in: fileBasedKeychains)
        #expect(fileBased.isEmpty)

        // Control: the check can fail. The test adds an item of its own, under a service unique to this run, as the
        // store's login-keychain fallback writes its key (no kSecUseDataProtectionKeychain); the same check must count
        // it, the data protection query must not, and the test deletes it.
        let controlService = "com.jevidon.sylvia.spike.identityprobe.control.\(UUID().uuidString)"
        defer { Self.deleteControlItem(service: controlService) }
        try #require(Self.addControlItem(service: controlService) == errSecSuccess)
        let controlCounted = try Self.items(service: controlService, in: fileBasedKeychains).count
        let controlInDataProtection = try Self.items(service: controlService, in: .dataProtection).count
        Self.deleteControlItem(service: controlService)
        let controlAfterDeletion = try Self.items(service: controlService, in: fileBasedKeychains).count
        #expect(controlCounted == 1)
        #expect(controlInDataProtection == 0)
        #expect(controlAfterDeletion == 0)

        let (reloaded, isNewAgain) = try store.loadOrCreate(now: Date())
        #expect(!isNewAgain && reloaded.pin == created.pin && reloaded.sourceID == created.sourceID)
        #expect(store.lastBackend == .dataProtection)

        let keychainNames = searchList.map { URL(fileURLWithPath: $0.path).lastPathComponent }.joined(separator: ", ")
        print("G02-PROBE backend: \(store.lastBackend?.rawValue ?? "none")")
        print("G02-PROBE kSecAttrAccessible: \(accessible ?? "none") (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly is \(kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String))")
        print("G02-PROBE kSecAttrSynchronizable: \(synchronizable)")
        print("G02-PROBE kSecAttrAccessGroup: \(group)")
        print("G02-PROBE items for the service in the data protection keychain, synchronizable or not: \(items.count)")
        print("G02-PROBE items for the service in the file-based keychains (\(keychainNames)): \(fileBased.count)")
        print("G02-PROBE control: the test's own item added without kSecUseDataProtectionKeychain, counted by the same file-based"
            + " check: \(controlCounted), by the data protection query: \(controlInDataProtection); after the test deleted it: \(controlAfterDeletion)")
        print("G02-PROBE reloaded the same identity (same SPKI pin and source ID): \(reloaded.pin == created.pin)")
    }

    /// The service's generic-password items in the keychains named, attributes only (never the data).
    static func items(service: String, in keychains: Keychains) throws -> [[String: Any]] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        switch keychains {
        case .dataProtection:
            query[kSecUseDataProtectionKeychain as String] = true
            query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        case .fileBased(let searchList):
            query[kSecUseDataProtectionKeychain as String] = false
            query[kSecMatchSearchList as String] = searchList
        }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw KeychainStatusError(status: status) }
        return result as? [[String: Any]] ?? []
    }

    /// Adds the control item with the attributes the store's login-keychain fallback writes, without
    /// kSecUseDataProtectionKeychain: SecItemAdd then "adds the item to the default keychain" (Apple, TN3137), the
    /// login keychain. Its data is a fixed text, not a secret.
    static func addControlItem(service: String) -> OSStatus {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false,
            kSecAttrAccount as String: "probe-control",
            kSecAttrLabel as String: "Sylvia identity probe control item (not a secret)",
            kSecValueData as String: Data("G0.2 identity probe control item, not a secret".utf8),
        ]
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    /// Deletes the control item, whose service is unique to this run: as it was added, then naming the file-based
    /// keychain (a second call finds nothing once the first has deleted it).
    static func deleteControlItem(service: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        _ = SecItemDelete(query as CFDictionary)
        var fileBased = query
        fileBased[kSecUseDataProtectionKeychain as String] = false
        _ = SecItemDelete(fileBased as CFDictionary)
    }
}
