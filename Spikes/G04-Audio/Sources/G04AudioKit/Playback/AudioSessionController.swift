import AVFoundation
import Foundation

/// The real audio session: `.playback` for spoken audio with the long-form route-sharing policy (audiobooks and
/// podcasts). Activated only by `PlaybackService.play` and preview; inspection, import, export and capture never
/// call it, so they never interrupt another app's audio (plan 10.1). Deactivated with `.notifyOthersOnDeactivation`
/// when playback stops for good (see `AudioSessionControlling.deactivateAfterPlayback`).
@MainActor
public final class SystemAudioSession: AudioSessionControlling {
    public private(set) var activationCount = 0
    public private(set) var deactivationCount = 0
    /// The error of the last failed deactivation, if the last attempt failed.
    public private(set) var lastDeactivationError: String?
    /// Optional observer of every activation and deactivation (the harness logs them for the device run).
    public var onEvent: ((String) -> Void)?
    private var configured = false
    public init() {}

    public func activateForPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            if !configured {
                try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
                configured = true
            }
            try session.setActive(true)
        } catch {
            onEvent?("activate error=\(error)")
            throw error
        }
        activationCount += 1
        onEvent?("activate ok")
    }

    public func deactivateAfterPlayback() throws {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            lastDeactivationError = "\(error)"
            onEvent?("deactivate error=\(error)")
            throw error
        }
        lastDeactivationError = nil
        deactivationCount += 1
        onEvent?("deactivate ok notifyOthersOnDeactivation=true")
    }
}

/// Translates AVAudioSession notifications into playback-service calls (plan 10.1, T19). The notification center
/// is injectable so tests can post the system's notifications with the system's userInfo keys.
@MainActor
public final class AudioSessionObserver {
    public struct Log: Equatable, Sendable {
        public var interruptionsBegan = 0
        public var interruptionsEnded = 0
        public var routeChanges: [UInt] = []
    }

    private weak var service: PlaybackService?
    private var tokens: [any NSObjectProtocol] = []
    private let center: NotificationCenter
    public private(set) var log = Log()

    public init(service: PlaybackService, center: NotificationCenter = .default, session: AVAudioSession? = .sharedInstance()) {
        self.service = service
        self.center = center
        tokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            let info = Self.parseInterruption(note.userInfo)
            MainActor.assumeIsolated { self?.handleInterruption(info) }
        })
        tokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] note in
            let reason = Self.parseRouteChange(note.userInfo)
            MainActor.assumeIsolated { self?.handleRouteChange(reason) }
        })
    }

    isolated deinit {
        tokens.forEach(center.removeObserver)
    }

    public enum Interruption: Equatable, Sendable {
        case began
        case ended(shouldResume: Bool)
        case unknown
    }

    nonisolated static func parseInterruption(_ info: [AnyHashable: Any]?) -> Interruption {
        guard let raw = info?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return .unknown }
        switch type {
        case .began: return .began
        case .ended:
            let opts = (info?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            return .ended(shouldResume: opts.contains(.shouldResume))
        @unknown default: return .unknown
        }
    }

    nonisolated static func parseRouteChange(_ info: [AnyHashable: Any]?) -> AVAudioSession.RouteChangeReason? {
        guard let raw = info?[AVAudioSessionRouteChangeReasonKey] as? UInt else { return nil }
        return AVAudioSession.RouteChangeReason(rawValue: raw)
    }

    private func handleInterruption(_ i: Interruption) {
        switch i {
        case .began:
            log.interruptionsBegan += 1
            service?.interruptionBegan()
        case let .ended(shouldResume):
            log.interruptionsEnded += 1
            service?.interruptionEnded(shouldResume: shouldResume)
        case .unknown:
            break
        }
    }

    private func handleRouteChange(_ reason: AVAudioSession.RouteChangeReason?) {
        guard let reason else { return }
        log.routeChanges.append(reason.rawValue)
        // Only the loss of the previous output (headphones unplugged, Bluetooth gone) pauses. A new device never
        // starts playback.
        if reason == .oldDeviceUnavailable { service?.outputDeviceRemoved() }
    }
}
