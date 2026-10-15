import AppKit
import SylviaSourceService

/// Host app for the identity-key probe (Stage 0 only, never shipped). It exists to carry a code signature
/// with a keychain access group; the tests it hosts do the work. It opens no window and serves nothing.
@main
@MainActor
final class ProbeAppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let application = NSApplication.shared
        let delegate = ProbeAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.prohibited)
        _ = KeychainIdentityStore.Policy.dataProtectionOnly  // links the library the tests use
        application.run()
    }
}
