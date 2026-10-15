import SwiftUI
import SylviaTransferCore
import UIKit

/// G0.2 transfer harness (Stage 0 only; never shipped; plan 4.4.9 exemption for Spikes/): pairing from the
/// phone, manual addresses, Bonjour browsing and background-session downloads with launch reconciliation.
@main
struct HarnessApp: App {
    @UIApplicationDelegateAdaptor(HarnessAppDelegate.self) private var appDelegate
    @State private var model = HarnessModel()

    var body: some Scene {
        WindowGroup {
            HarnessRootView(model: model)
                .onOpenURL { url in model.receivePairingLink(url) }
        }
    }
}

final class HarnessAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let runtime = TransferRuntime.shared
        // UIKit reports .background here for every launch of a scene-based app (also when the person opens it), so
        // the state stays "launching" until the scene becomes active ("foreground") or the system delivers background
        // session events first ("background_relaunch", set in handleEventsForBackgroundURLSession).
        let state = application.applicationState
        runtime.appState.set("launching")
        runtime.appState.observe()
        // protected_data_available (class A, false whenever a passcode phone is locked) is recorded for the device
        // checklist; it does not gate anything (review finding R2-01).
        runtime.coordinator.log.record("app_launch", [
            "application_state": AppStateTracker.describe(state),
            "protected_data_available": String(application.isProtectedDataAvailable),
        ])
        // Evidence for the device checklist: the data protection class the system reports for the store
        // (the simulator reports none; a device must report completeUntilFirstUserAuthentication).
        var protection: [String: String] = [:]
        for name in ["", "events.jsonl", "sources.json"] {
            let url = name.isEmpty ? runtime.root : runtime.root.appendingPathComponent(name)
            let value = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.protectionKey] as? FileProtectionType
            protection[name.isEmpty ? "store_folder" : name] = value?.rawValue ?? "none_reported"
        }
        runtime.coordinator.log.record("store_protection", protection)
        runtime.start()
        // A launch before the first unlock defers (its stores cannot be read: nothing read, cancelled or written);
        // the unlock is a retry trigger. Every lock and unlock is logged, so the device run can tell "locked after
        // the first unlock" (transfers must continue) from "before the first unlock" (launch deferred).
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { _ in
            runtime.coordinator.log.record("protected_data_available", ["app_state": runtime.appState.current])
            runtime.start()
        }
        center.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main) { _ in
            runtime.coordinator.log.record("protected_data_will_become_unavailable", ["app_state": runtime.appState.current])
        }
        return true
    }

    /// The system relaunched (or woke) the app because the background session has events for it.
    func application(
        _ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        let runtime = TransferRuntime.shared
        nonisolated(unsafe) let completion = completionHandler
        guard identifier == TransferRuntime.sessionIdentifier else {
            // A session this build no longer uses (for example from hosted tests): nothing to deliver.
            runtime.coordinator.log.record("background_events_other_session", ["identifier": identifier])
            completion()
            return
        }
        if runtime.appState.current == "launching" { runtime.appState.set("background_relaunch") }
        // The completion is called after the session's events (and any full-file check they started), or at once
        // if this start defers because the stores cannot be read (review finding R2-01).
        runtime.coordinator.setBackgroundEventsCompletion { completion() }
        runtime.start()
    }
}
