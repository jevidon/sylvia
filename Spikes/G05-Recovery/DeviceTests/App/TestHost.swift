import SwiftUI

// The test runner owns execution; this app only supplies an iOS process and container.
@main
struct RecoveryTestHost: App {
    var body: some Scene {
        WindowGroup {
            Text("Recovery tests run from the Mac.")
        }
    }
}
