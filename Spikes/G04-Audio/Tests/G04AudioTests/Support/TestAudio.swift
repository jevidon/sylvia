import AVFoundation
import Foundation
@testable import G04AudioKit

/// Every player the tests and probes create comes from here, so every test plays quietly (1 % volume,
/// `SpikeAudioOutput.quietVolume`) unless the test process has `SYLVIA_AUDIBLE_PLAYBACK=1` (the CI drop-in forwards the
/// host's value as `TEST_RUNNER_SYLVIA_AUDIBLE_PLAYBACK`). The Mac's speakers are shared, and simulator audio plays
/// through them. The volume is applied after decoding, the time-pitch stage and the analysis taps, and the player's
/// clock is unaffected, so every measurement is taken exactly as at full volume (`MutedRenderingTests` checks it; it
/// also records why `isMuted` is not used). The CI drop-in fails if a test file creates a player any other way. The
/// engines' own default stays full volume (`AudioOutputTests`).
enum TestAudio {
    static var audible: Bool { SpikeAudioOutput.testsAreAudible(environment: ProcessInfo.processInfo.environment) }
    static var volume: Float { SpikeAudioOutput.testVolume(environment: ProcessInfo.processInfo.environment) }

    /// For the result tables' environment line.
    static var label: String { audible ? "output at full volume (SYLVIA_AUDIBLE_PLAYBACK=1)" : "output at 1 % volume (quiet test runs)" }

    @MainActor static func engine() -> AVQueuePlayerEngine { AVQueuePlayerEngine(outputVolume: volume) }

    @MainActor static func previewPlayer() -> AVPreviewPlayer { AVPreviewPlayer(outputVolume: volume) }

    @MainActor static func player(_ item: AVPlayerItem? = nil) -> AVPlayer {
        let player = item.map { AVPlayer(playerItem: $0) } ?? AVPlayer()
        player.volume = volume
        return player
    }
}
