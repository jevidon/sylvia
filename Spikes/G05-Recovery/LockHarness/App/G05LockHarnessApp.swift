import BackgroundTasks
import SwiftUI
import UIKit

/// The G0.5 recovery locked-device harness (T50, device checklist step 3; PO-23 option (b), product owner,
/// 22 October 2026). Stage 0 evidence code, never shipped (ADR-0002); its chrome is exempt from the design tokens.
@main
struct G05LockHarnessApp: App {
    @UIApplicationDelegateAdaptor(HarnessAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            HarnessView(controller: delegate.controller)
        }
    }
}

/// Owns the controller for the whole process, so a launch in the background (a background refresh, before or after
/// the first unlock) is recorded even if no scene ever connects.
@MainActor
final class HarnessAppDelegate: NSObject, UIApplicationDelegate {
    private(set) lazy var controller: HarnessController = {
        // The configuration accepts class C only; its only other input is SYLVIA_AUDIBLE_PLAYBACK.
        let configuration: HarnessConfiguration
        do {
            configuration = try HarnessConfiguration(environment: ProcessInfo.processInfo.environment)
        } catch {
            preconditionFailure("the harness's default configuration is valid: \(error)")
        }
        return HarnessController(configuration: configuration, environment: .production(configuration: configuration))
    }()
    private var observers: [any NSObjectProtocol] = []

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundRefreshScheduler.identifier, using: .main) { [weak self] task in
            MainActor.assumeIsolated {
                guard let self else {
                    task.setTaskCompleted(success: false)
                    return
                }
                task.expirationHandler = { [weak self] in
                    MainActor.assumeIsolated { self?.controller.audioEvent("background-refresh-expired") }
                }
                let passed = self.controller.backgroundRefresh()
                task.setTaskCompleted(success: passed)
            }
        }
        observe()
        controller.launch(state: UIKitSystem.name(of: application.applicationState))
        return true
    }

    private func observe() {
        let center = NotificationCenter.default
        let events: [(Notification.Name, @MainActor (HarnessController) -> Void)] = [
            (UIApplication.protectedDataWillBecomeUnavailableNotification, { $0.protectedDataWillBecomeUnavailable() }),
            (UIApplication.protectedDataDidBecomeAvailableNotification, { $0.protectedDataDidBecomeAvailable() }),
            (UIApplication.didEnterBackgroundNotification, { $0.appStateChanged(to: "background") }),
            (UIApplication.willEnterForegroundNotification, { $0.appStateChanged(to: "foreground") }),
            (UIApplication.didBecomeActiveNotification, { $0.appStateChanged(to: "active") }),
            (UIApplication.willResignActiveNotification, { $0.appStateChanged(to: "resigning-active") }),
            (UIApplication.willTerminateNotification, { $0.willTerminate() }),
        ]
        for (name, handle) in events {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    handle(self.controller)
                }
            })
        }
    }
}
