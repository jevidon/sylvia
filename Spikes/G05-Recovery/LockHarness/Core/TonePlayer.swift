import AVFoundation
import Foundation

/// The keep-alive signal: one second of a 441 Hz sine at -26 dBFS, 16-bit mono at 44.1 kHz, made in memory (no file,
/// no fixture). 441 Hz is exactly 100 samples per cycle at 44.1 kHz, so the second loops without a click.
public enum QuietTone {
    public static let sampleRate = 44_100
    public static let frequency = 441.0
    public static let amplitude = 0.05
    public static let samplesPerCycle = 100

    /// One cycle, computed once and repeated, so every cycle and the loop's seam are identical.
    public static func samples(seconds: Int = 1) -> [Int16] {
        let cycle = (0..<samplesPerCycle).map { n in
            Int16((sin(2 * .pi * Double(n) / Double(samplesPerCycle)) * amplitude * Double(Int16.max)).rounded())
        }
        let cycles = sampleRate * max(seconds, 1) / samplesPerCycle
        return Array((0..<cycles).map { _ in cycle }.joined())
    }

    /// A RIFF/WAVE file of `samples(seconds:)`.
    public static func wavData(seconds: Int = 1) -> Data {
        let pcm = samples(seconds: seconds)
        let dataBytes = UInt32(pcm.count * 2)
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + dataBytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))                     // fmt chunk size
        append(UInt16(1))                      // PCM
        append(UInt16(1))                      // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))         // byte rate
        append(UInt16(2))                      // block align
        append(UInt16(16))                     // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(dataBytes)
        for sample in pcm { append(sample) }
        return data
    }
}

/// Plays the quiet tone in a loop with the `.playback` session, so iOS keeps the harness running in the background and
/// while the phone is locked (UIBackgroundModes audio). The volume is the player's (`AVAudioPlayer.volume`), injected
/// by the configuration: 0.01 unless SYLVIA_AUDIBLE_PLAYBACK=1. It never mutes, and never touches the phone's volume.
/// Interruptions (a call, Siri, another app's audio) and route changes are reported; after an interruption ends, or
/// when a route change stops the player, it resumes.
@MainActor
public final class TonePlayer: KeepAlivePlayer {
    public var onEvent: (@MainActor (String) -> Void)?
    private var player: AVAudioPlayer?
    private var volume: Float = HarnessVolume.quiet
    private var observers: [any NSObjectProtocol] = []

    public init() {}

    public var isPlaying: Bool { player?.isPlaying ?? false }
    /// The volume the player is set to, for tests and the log.
    public var playerVolume: Float? { player?.volume }

    public func start(volume: Float) throws {
        stop()
        self.volume = volume
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
        try startPlayer()
        observe(session)
    }

    public func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        guard let player else { return }
        player.stop()
        self.player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startPlayer() throws {
        let player = try AVAudioPlayer(data: QuietTone.wavData(), fileTypeHint: AVFileType.wav.rawValue)
        player.numberOfLoops = -1
        player.volume = volume
        guard player.prepareToPlay(), player.play() else { throw HarnessError.audio("AVAudioPlayer did not start") }
        self.player = player
    }

    private func resume(_ why: String) {
        guard let player else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            let resumed = player.isPlaying || player.play()
            onEvent?("\(why) resumed=\(resumed)")
        } catch {
            onEvent?("\(why) resumed=false error=\(HarnessLog.code(error))")
        }
    }

    private func observe(_ session: AVAudioSession) {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let began = raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began
            MainActor.assumeIsolated {
                guard let self else { return }
                if began {
                    self.onEvent?("interruption-began")
                } else {
                    self.resume("interruption-ended")
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onEvent?("route-change reason=\(reason)")
                if !self.isPlaying { self.resume("route-change") }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                do {
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
                    try AVAudioSession.sharedInstance().setActive(true)
                    try self.startPlayer()
                    self.onEvent?("media-services-reset restarted=true")
                } catch {
                    self.onEvent?("media-services-reset restarted=false error=\(HarnessLog.code(error))")
                }
            }
        })
    }
}
