import Foundation

// Match SwiftPM's Bundle.module API for the unchanged tests compiled by Xcode.
private final class RecoveryTestBundleMarker {}

extension Bundle {
    static let module = Bundle(for: RecoveryTestBundleMarker.self)
}
