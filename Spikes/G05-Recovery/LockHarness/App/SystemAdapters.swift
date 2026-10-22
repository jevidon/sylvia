import BackgroundTasks
import Foundation
import UIKit

/// `UIApplication`'s protected-data flag and state, for the harness's records.
@MainActor
final class UIKitSystem: ProtectedDataSource, AppStateSource {
    var isProtectedDataAvailable: Bool { UIApplication.shared.isProtectedDataAvailable }

    var stateName: String { Self.name(of: UIApplication.shared.applicationState) }

    static func name(of state: UIApplication.State) -> String {
        switch state {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }
}

/// Asks iOS for a background refresh launch. iOS runs it when it chooses, or never (it does not run in Low Power Mode,
/// or with Background App Refresh off); the earliest time asked for is a minute from now.
@MainActor
final class BackgroundRefreshScheduler: RefreshScheduler {
    static let identifier = "com.jevidon.sylvia.spike.g05lockharness.refresh"

    func schedule() -> String {
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            return "scheduled-earliest-in-60s"
        } catch {
            return "not-scheduled:\(HarnessLog.code(error))"
        }
    }
}

extension HarnessEnvironment {
    /// The harness as installed: the app container's `Application Support`, the real clock, UIKit, the quiet tone, the
    /// unified log and BackgroundTasks.
    static func production(configuration: HarnessConfiguration) -> HarnessEnvironment {
        let (paths, layout) = HarnessPaths.applicationSupport()
        let system = UIKitSystem()
        return HarnessEnvironment(
            clock: SystemHarnessClock(), protectedData: system, bootTime: SysctlBootTime(), appState: system,
            player: TonePlayer(), store: LibraryHarnessStore(layout: layout, configuration: configuration),
            sink: FileLogSink(paths: paths, configuration: configuration), mirror: UnifiedLogMirror(),
            sessions: SessionFileStore(paths: paths, configuration: configuration), canary: ClassACanary(paths: paths),
            probe: ClassCFileProbe(paths: paths, configuration: configuration),
            inspector: FileProtectionInspector(paths: paths, layout: layout, configuration: configuration),
            scheduler: BackgroundRefreshScheduler(), platform: HarnessPlatform.name)
    }
}
