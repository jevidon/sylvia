import Foundation
import Security
import Synchronization
import SylviaBackgroundTransfer
import SylviaTransferClient
import SylviaTransferCore
import UIKit

/// What the app is doing right now, as the background coordinator logs it with every trust challenge,
/// verified part and launch: "launching", "foreground", "inactive", "background", or "background_relaunch" (the
/// system launched the app to deliver background session events before any scene became active).
final class AppStateTracker: Sendable {
    private let value = Mutex("launching")

    var current: String { value.withLock { $0 } }
    func set(_ state: String) { value.withLock { $0 = state } }

    @MainActor
    func observe() {
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [self] _ in set("foreground") }
        center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [self] _ in set("inactive") }
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [self] _ in set("background") }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [self] _ in set("inactive") }
    }

    static func describe(_ state: UIApplication.State) -> String {
        switch state {
        case .active: "foreground"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }
}

/// The harness's one background transfer client. Created at launch, before any scene, so a relaunch
/// by the system for background session events finds its jobs and its session (plan 6.4, 15.5).
final class TransferRuntime: Sendable {
    static let sessionIdentifier = "com.jevidon.sylvia.spike.transfer.parts"
    static let keychainService = "com.jevidon.sylvia.spike.transfer.token"
    /// Created on first use (lazily and thread-safely, as every Swift global).
    static let shared = TransferRuntime()

    let appState = AppStateTracker()
    let credentials = KeychainCredentialStore(service: TransferRuntime.keychainService)
    let coordinator: BackgroundTransferCoordinator
    let root: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = support.appendingPathComponent("Transfers", isDirectory: true)
        if ProcessInfo.processInfo.arguments.contains("-G02ResetState") {
            Self.reset(root: root, credentials: credentials)
        }
        let tracker = appState
        do {
            // Before the first unlock after a restart the store's files (class C) cannot be read; the
            // coordinator then defers its launch instead of acting on empty stores (ADR-0008). It detects that
            // from the files themselves. isProtectedDataAvailable is only logged: it is false whenever a phone
            // with a passcode is locked, also after its first unlock, when transfers must run (review finding R2-01).
            coordinator = try BackgroundTransferCoordinator(
                kind: .background(identifier: Self.sessionIdentifier), root: root, credentials: credentials,
                appState: { tracker.current },
                protectedDataAvailable: { await MainActor.run { UIApplication.shared.isProtectedDataAvailable } })
        } catch {
            fatalError("cannot create the transfer store: \(error)")  // harness only: no recovery UI for a broken container
        }
    }

    /// Starts the coordinator (launch reconciliation). Call at every launch, at a background relaunch for session
    /// events and when protected data becomes available. The coordinator runs one start at a time and ignores a
    /// call after a start succeeded, so a call after a deferred start is the retry.
    @discardableResult
    func start() -> Task<BackgroundTransferCoordinator.ReconciliationSummary, Never> {
        let coordinator = self.coordinator
        return Task { await coordinator.start() }
    }

    /// UI test isolation: forget paired sources (and their tokens) and every job. Outstanding background
    /// tasks of earlier runs are cancelled by reconciliation as tasks of unknown jobs.
    private static func reset(root: URL, credentials: KeychainCredentialStore) {
        if let data = try? Data(contentsOf: root.appendingPathComponent("sources.json")),
            let sources = try? TransferJSON.decode([PairedSource].self, from: data)
        {
            for source in sources { try? credentials.deleteToken(sourceID: source.sourceID) }
        }
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Pairing

    enum PairingError: Error, CustomStringConvertible {
        case client(ClientError)
        case keychain(OSStatus)
        case store

        var description: String {
            switch self {
            case .client(.localNetworkDenied):
                "pairing failed: local network access is off for this app. Turn on Local Network for Sylvia in Settings > "
                    + "Privacy & Security > Local Network, then pair with a new code from the Mac. Nothing was sent."
            case .client(let error): "pairing failed: \(error)"
            case .keychain(let status): "the Keychain refused the token (\(status))"
            case .store: "could not save the paired source"
            }
        }
    }

    /// Pins the payload's SPKI digest, sends the invitation only over a connection presenting that key,
    /// stores the token in the Keychain (after first unlock, this device only) and the public pairing
    /// record in the app's store.
    func pair(payload: PairingPayload, deviceName: String) async throws(PairingError) -> PairedSource {
        let deviceID = CanonicalID.make()
        let paired: PairedSource
        let token: String
        do {
            (paired, token) = try await SourceClient.pair(payload: payload, deviceID: deviceID, deviceName: deviceName)
        } catch {
            throw .client(error)
        }
        do { try credentials.saveToken(token, sourceID: paired.sourceID) } catch {
            throw .keychain((error as? KeychainError)?.status ?? errSecInternalError)
        }
        do { try coordinator.sources.upsert(paired) } catch { throw .store }
        coordinator.log.record("paired", ["source": paired.sourceID, "device": deviceID, "endpoints": String(paired.endpoints.count)])
        return paired
    }
}
