// G0.2 probe fix: read-only state for the logs' headers. The console session's screen-lock flag
// (CGSessionCopyCurrentDictionary) and the default keychain's lock status (SecKeychainGetStatus, which does not
// prompt). Touches no keychain item.
import CoreGraphics
import Foundation
import Security

let session = CGSessionCopyCurrentDictionary() as? [String: Any]
print("screen locked: \(session?["CGSSessionScreenIsLocked"].map { "\($0)" } ?? "no (CGSSessionScreenIsLocked absent)")")
var keychain: SecKeychain?
if SecKeychainCopyDefault(&keychain) == errSecSuccess, let keychain {
    var flags: SecKeychainStatus = 0
    let status = SecKeychainGetStatus(keychain, &flags)
    print("default keychain unlocked: \(status == errSecSuccess ? "\(flags & SecKeychainStatus(kSecUnlockStateStatus) != 0)" : "status \(status)")")
} else {
    print("default keychain: none")
}
