// G0.2 probe fix (27 October 2026): lists, and never deletes or changes, the items of the login keychain whose
// service begins with the identity probe's prefix, attributes only (never kSecReturnData). Run unsigned with
// list-login-keychain-items.sh, so it reaches the file-based keychains only (Apple, TN3137: a program without a
// keychain access group has no data protection keychain), and the query names the login keychain alone in
// kSecMatchSearchList. Items of other services are read as attributes inside this process to filter them, and
// never printed. An argument replaces the prefix (added after the first listing, which used the default; the
// default output is unchanged).
import Foundation
import Security

let prefix = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "com.jevidon.sylvia.spike.identityprobe."
let ownerRunPrefix = "com.jevidon.sylvia.spike.identityprobe.test."

/// SecKeychain is deprecated (macOS 10.10), but a SecKeychain is what kSecMatchSearchList takes.
@available(macOS, deprecated: 10.10)
func searchList() -> [(path: String, keychain: SecKeychain)] {
    var list: CFArray?
    let status = SecKeychainCopySearchList(&list)
    guard status == errSecSuccess, let list else {
        print("SecKeychainCopySearchList: status \(status)")
        return []
    }
    return (0..<CFArrayGetCount(list)).compactMap { index in
        guard let raw = CFArrayGetValueAtIndex(list, index) else { return nil }
        let keychain = Unmanaged<SecKeychain>.fromOpaque(raw).takeUnretainedValue()
        var length: UInt32 = 1024
        var buffer = [CChar](repeating: 0, count: 1025)
        let pathStatus = SecKeychainGetPath(keychain, &length, &buffer)
        let path = pathStatus == errSecSuccess
            ? String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            : "SecKeychainGetPath status \(pathStatus)"
        return (path, keychain)
    }
}

func text(_ value: Any?) -> String {
    switch value {
    case nil: return "none"
    case let date as Date: return date.ISO8601Format(.init(includingFractionalSeconds: true))
    case let number as NSNumber: return number.stringValue
    case let value?: return "\(value)"
    }
}

let keychains = searchList()
print("file-based keychains in the user's search list: \(keychains.map(\.path).joined(separator: ", "))")
guard let login = keychains.first(where: { $0.path.hasSuffix("/login.keychain-db") }) else {
    print("no login.keychain-db in the search list; nothing listed")
    exit(1)
}
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecMatchSearchList as String: [login.keychain],
    kSecReturnAttributes as String: true,
    kSecMatchLimit as String: kSecMatchLimitAll,
]
var result: CFTypeRef?
let status = SecItemCopyMatching(query as CFDictionary, &result)
let message = (SecCopyErrorMessageString(status, nil) as String?) ?? "no message"
print("query: generic passwords, kSecMatchSearchList [\(login.path)], attributes only: status \(status) (\(message))")
guard status == errSecSuccess || status == errSecItemNotFound else { exit(1) }
let items = (result as? [[String: Any]] ?? [])
    .filter { ($0[kSecAttrService as String] as? String)?.hasPrefix(prefix) == true }
    .sorted { text($0[kSecAttrCreationDate as String]) < text($1[kSecAttrCreationDate as String]) }
print("items whose service begins with \(prefix): \(items.count)")
for item in items {
    print("  service \(text(item[kSecAttrService as String])), account \(text(item[kSecAttrAccount as String])),"
        + " label \(text(item[kSecAttrLabel as String])), created \(text(item[kSecAttrCreationDate as String])),"
        + " modified \(text(item[kSecAttrModificationDate as String]))")
}
if ownerRunPrefix.hasPrefix(prefix) {
    let ownerRun = items.filter { ($0[kSecAttrService as String] as? String)?.hasPrefix(ownerRunPrefix) == true }
    print("of them, with the identity test's prefix \(ownerRunPrefix): \(ownerRun.count)")
}
