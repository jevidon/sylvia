import Foundation
import Security

/// The file-based keychains of the user's keychain search list, with their paths: what kSecMatchSearchList takes to
/// limit a query to file-based keychains (Apple, TN3137: queries "consult all keychains in the search list. Use
/// kSecMatchSearchList to override this"). The SecKeychain functions are deprecated (macOS 10.10) but still the only
/// way to name a file-based keychain; the deprecated call stays inside `SecKeychainSearchList`, reached through this
/// protocol, so the probe still builds with warnings as errors. Stage 0 probe only; never shipped.
protocol FileBasedKeychainSearchList: Sendable {
    func keychains() throws -> [(path: String, keychain: SecKeychain)]
}

struct SecKeychainSearchList: FileBasedKeychainSearchList {
    static var current: any FileBasedKeychainSearchList { SecKeychainSearchList() }

    @available(macOS, deprecated: 10.10, message: "used only to name file-based keychains in kSecMatchSearchList")
    func keychains() throws -> [(path: String, keychain: SecKeychain)] {
        var list: CFArray?
        let status = SecKeychainCopySearchList(&list)
        guard status == errSecSuccess, let list else { throw KeychainProbeError.status("SecKeychainCopySearchList", status) }
        return (0..<CFArrayGetCount(list)).compactMap { index in
            guard let raw = CFArrayGetValueAtIndex(list, index) else { return nil }
            let keychain = Unmanaged<SecKeychain>.fromOpaque(raw).takeUnretainedValue()
            var length: UInt32 = 1024
            var buffer = [CChar](repeating: 0, count: 1025)
            let pathStatus = SecKeychainGetPath(keychain, &length, &buffer)
            let path = pathStatus == errSecSuccess
                ? String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
                : "(SecKeychainGetPath status \(pathStatus))"
            return (path, keychain)
        }
    }
}

enum KeychainProbeError: Error, CustomStringConvertible {
    case status(String, OSStatus)
    var description: String {
        switch self {
        case .status(let call, let status): "\(call): \(status) (\(KeychainText.message(status)))"
        }
    }
}

/// How the probe prints keychain values: attributes only, never an item's data.
enum KeychainText {
    static func message(_ status: OSStatus) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "no message"
    }

    static func value(_ value: Any?) -> String {
        switch value {
        case nil: "none"
        case let date as Date: date.ISO8601Format(.init(includingFractionalSeconds: true))
        case let number as NSNumber:
            CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue
        case let value?: "\(value)"
        }
    }
}
