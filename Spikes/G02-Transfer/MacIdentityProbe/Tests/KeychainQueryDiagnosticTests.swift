import Darwin
import Foundation
import Security
import SylviaSourceService
import Testing

/// Diagnosis of the identity test's failure in the product owner's signed run of 27 October 2026 (runbook 0.7, G0.2
/// checklist step 20): its "nowhere else" check, a query without kSecUseDataProtectionKeychain, counted one item for
/// the test's service, which is unique to the run and which the store (policy dataProtectionOnly) writes only with
/// kSecUseDataProtectionKeychain true. This test creates the identity through the store, as the identity test does,
/// and adds a file-based item of its own under a second service unique to the run; for each query below and each of
/// the two services it prints the query and every item the query returns, with the item's attributes and never its
/// data; then it deletes both (the store's reset, SecItemDelete) and repeats the queries. Before that it lists,
/// attributes only and without deleting them, probe items that earlier runs left in the data protection keychain.
/// Lines start with "G02-DIAG" (Docs/Stage0/evidence/G02-Transfer/probe-fix/). Stage 0 probe only; never shipped.
@Suite("Keychain queries by keychain implementation (diagnostic of the first signed run)")
struct KeychainQueryDiagnosticTests {
    static let prefix = "com.jevidon.sylvia.spike.identityprobe."

    struct Query {
        let name: String
        let keys: [String: Any]
        let text: String
        /// True when the query names only file-based keychains.
        let fileBasedOnly: Bool
    }

    @Test func whatEachQueryReturnsForTheStoresItemAndForAFileBasedItem() throws {
        let searchList = try SecKeychainSearchList.current.keychains()
        print("G02-DIAG file-based keychains in the user's search list: \(searchList.map(\.path).joined(separator: ", "))")
        let login = searchList.first { $0.path.hasSuffix("/login.keychain-db") }
        try #require(login != nil)
        Self.listItemsOfEarlierRuns()

        let run = UUID().uuidString
        let storeService = Self.prefix + "diagnostic.\(run)"
        let fileService = Self.prefix + "diagnostic-file-based.\(run)"
        let state = FileManager.default.temporaryDirectory.appendingPathComponent("g02-probe-diagnostic-\(run)")
        let store = KeychainIdentityStore(service: storeService, stateDirectory: state)
        defer {
            try? store.reset()
            Self.deleteOwnFileBasedItem(service: fileService)
            try? FileManager.default.removeItem(at: state)
        }
        print("G02-DIAG services of this run: the store's \(storeService); the test's own file-based item's \(fileService)")

        let (_, isNew) = try store.loadOrCreate(now: Date())
        #expect(isNew)
        #expect(store.policy == .dataProtectionOnly && store.lastBackend == .dataProtection)
        print("G02-DIAG store.loadOrCreate: policy dataProtectionOnly, backend \(store.lastBackend?.rawValue ?? "none")")
        let added = Self.addOwnFileBasedItem(service: fileService)
        print("G02-DIAG SecItemAdd of the test's own item, without kSecUseDataProtectionKeychain (as the store's login-keychain"
            + " fallback writes): status \(added) (\(KeychainText.message(added)))")
        try #require(added == errSecSuccess)

        let queries = Self.queries(login: login!.keychain, searchList: searchList.map(\.keychain))
        let subjects = [("store's item", storeService), ("test's file-based item", fileService)]
        var created: [String: Int] = [:]
        for (subject, service) in subjects {
            for query in queries {
                created["\(subject)/\(query.name)"] = Self.report(query, service: service, phase: "created", subject: subject)
            }
        }

        try store.reset()
        let deletedStatus = Self.deleteOwnFileBasedItem(service: fileService)
        print("G02-DIAG store.reset() returned; SecItemDelete of the test's own item: status \(deletedStatus) (\(KeychainText.message(deletedStatus)))")
        var deleted: [String: Int] = [:]
        for (subject, service) in subjects {
            for query in queries {
                deleted["\(subject)/\(query.name)"] = Self.report(query, service: service, phase: "deleted", subject: subject)
            }
        }

        print("G02-DIAG summary: items each query returned, after creation -> after deletion")
        for query in queries {
            let counts = subjects.map { subject, _ in
                "\(subject) \(created["\(subject)/\(query.name)"] ?? -1) -> \(deleted["\(subject)/\(query.name)"] ?? -1)"
            }
            print("G02-DIAG summary | \(query.name) [\(query.text)]: \(counts.joined(separator: "; "))")
        }

        // What the diagnosis rests on. The query without kSecUseDataProtectionKeychain is printed, not expected: what
        // it returns is the platform behaviour under diagnosis.
        for query in queries where query.fileBasedOnly {
            #expect(created["store's item/\(query.name)"] == 0, "\(query.name) returned the store's item")
            #expect(created["test's file-based item/\(query.name)"] == 1, "\(query.name) missed the file-based item")
        }
        #expect(created["store's item/data protection"] == 1)
        #expect(created["store's item/data protection, synchronizable any"] == 1)
        #expect(created["test's file-based item/data protection"] == 0)
        #expect(deleted.values.allSatisfy { $0 == 0 }, "an item survived its deletion: \(deleted.filter { $0.value != 0 })")
    }

    static func queries(login: SecKeychain, searchList: [SecKeychain]) -> [Query] {
        let useDataProtection = kSecUseDataProtectionKeychain as String
        let searchListKey = kSecMatchSearchList as String
        return [
            Query(name: "data protection", keys: [useDataProtection: true],
                  text: "kSecUseDataProtectionKeychain true", fileBasedOnly: false),
            Query(name: "unspecified", keys: [:],
                  text: "no kSecUseDataProtectionKeychain, as the identity test's check in the owner's run", fileBasedOnly: false),
            Query(name: "file-based", keys: [useDataProtection: false],
                  text: "kSecUseDataProtectionKeychain false", fileBasedOnly: true),
            Query(name: "login keychain", keys: [searchListKey: [login]],
                  text: "kSecMatchSearchList [login.keychain-db]", fileBasedOnly: true),
            Query(name: "search list", keys: [searchListKey: searchList],
                  text: "kSecMatchSearchList [every keychain of the user's search list]", fileBasedOnly: true),
            Query(name: "file-based, search list", keys: [useDataProtection: false, searchListKey: searchList],
                  text: "kSecUseDataProtectionKeychain false and kSecMatchSearchList [every keychain of the search list]",
                  fileBasedOnly: true),
            Query(name: "data protection, synchronizable any",
                  keys: [useDataProtection: true, kSecAttrSynchronizable as String: kSecAttrSynchronizableAny],
                  text: "kSecUseDataProtectionKeychain true, kSecAttrSynchronizable kSecAttrSynchronizableAny", fileBasedOnly: false),
        ]
    }

    /// Runs one query for one service, attributes only, and prints the query and each item it returns.
    static func report(_ query: Query, service: String, phase: String, subject: String) -> Int {
        var attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        attributes.merge(query.keys) { _, new in new }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        let items = status == errSecSuccess ? (result as? [[String: Any]] ?? []) : []
        print("G02-DIAG \(phase) | \(subject) | \(query.name) | query: kSecClass kSecClassGenericPassword, kSecAttrService"
            + " <\(subject)'s service>, kSecReturnAttributes true, kSecMatchLimit kSecMatchLimitAll, \(query.text)"
            + " | status \(status) (\(KeychainText.message(status))), items \(items.count)")
        for (index, item) in items.enumerated() {
            print("G02-DIAG \(phase) | \(subject) | \(query.name) | item \(index + 1): \(describe(item))")
        }
        return items.count
    }

    static func describe(_ item: [String: Any]) -> String {
        let fields: [(String, CFString)] = [
            ("kSecAttrAccessGroup", kSecAttrAccessGroup), ("kSecAttrAccessible", kSecAttrAccessible),
            ("kSecAttrSynchronizable", kSecAttrSynchronizable), ("kSecAttrLabel", kSecAttrLabel),
            ("kSecAttrCreationDate", kSecAttrCreationDate),
        ]
        let values = fields.map { name, key in "\(name) \(KeychainText.value(item[key as String]))" }
        return values.joined(separator: ", ") + "; attribute keys returned: \(item.keys.sorted().joined(separator: " "))"
    }

    /// Lists, never deletes, the probe's items that earlier runs left in the data protection keychain: the probe's
    /// access group holds only the probe's items, and an item created after this process started is this run's.
    static func listItemsOfEarlierRuns() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        let started = processStart()
        let earlier = (status == errSecSuccess ? (result as? [[String: Any]] ?? []) : []).filter { item in
            guard (item[kSecAttrService as String] as? String)?.hasPrefix(prefix) == true else { return false }
            guard let started, let created = item[kSecAttrCreationDate as String] as? Date else { return true }
            return created < started
        }
        print("G02-DIAG earlier runs: items of the probe's access group in the data protection keychain whose service begins"
            + " with \(prefix), created before this test process started (\(KeychainText.value(started))): \(earlier.count)"
            + " (query status \(status), \(KeychainText.message(status)))")
        for item in earlier {
            print("G02-DIAG earlier runs | service \(KeychainText.value(item[kSecAttrService as String])): \(describe(item))")
        }
    }

    static func processStart() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, u_int(name.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime  // p_starttime is a C macro for this field
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }

    /// Adds an item as the store's login-keychain fallback would write it (the store's attributes, no
    /// kSecUseDataProtectionKeychain): Apple's TN3137 says SecItemAdd then "adds the item to the default keychain",
    /// the login keychain. Its data is a fixed text, not a secret.
    static func addOwnFileBasedItem(service: String) -> OSStatus {
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

    /// Deletes the test's own item, whose service is unique to this run: once as it was added, once naming the
    /// file-based keychain. Returns the first status.
    @discardableResult
    static func deleteOwnFileBasedItem(service: String) -> OSStatus {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        let status = SecItemDelete(query as CFDictionary)
        var fileBased = query
        fileBased[kSecUseDataProtectionKeychain as String] = false
        _ = SecItemDelete(fileBased as CFDictionary)
        return status
    }
}
