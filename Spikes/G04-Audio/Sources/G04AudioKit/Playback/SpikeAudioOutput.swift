import Foundation

/// Stage 0 only: how loud the spike's automated runs and its harness play. The product's engines play at full volume
/// by default (`AVQueuePlayerEngine(outputVolume:)` and `AVPreviewPlayer(outputVolume:)` default to 1, and nothing in
/// the engines reads this policy); the tests and the harness inject the quiet volume they decide here.
///
/// Quiet is a 1 % output volume (the level the product owner accepted for automated runs if muting would undermine the
/// tests), not `AVPlayer.isMuted`: with the player muted, the audio after the time-pitch stage at 2x and 3x was not
/// what an audible player renders (a 1 kHz tone measured 684 and 351 Hz after the time-domain stage in the clean run,
/// with a lower RMS; `MutedRenderingTests`, `audio-output.txt`), which would invalidate the rate and pitch
/// measurements. At 1 % both analysis taps see the file's own level and the 1 kHz tone at 1x-3x, as the earlier
/// full-volume runs did (the volume is applied after the taps), and the media clock advances at the rate. Volume 0
/// rendered like 1 % in that comparison; 1 % is kept because it is the accepted level and leaves no measurement to a
/// silent-output path that was compared on one fixture only.
public enum SpikeAudioOutput {
    /// The only way to run the spike's automated runs at full volume (tests, probes, the CI drop-in's harness launches).
    public static let environmentKey = "SYLVIA_AUDIBLE_PLAYBACK"
    /// The harness's full-volume toggle (persisted in user defaults; the launch argument `-g04AudiblePlayback YES|NO`
    /// overrides the persisted value for one launch, which is how the CI scripts keep the harness quiet).
    public static let harnessDefaultsKey = "g04AudiblePlayback"
    /// The output volume of every test, probe and harness player unless full volume is asked for.
    public static let quietVolume: Float = 0.01

    /// Tests and probes: full volume only with `SYLVIA_AUDIBLE_PLAYBACK=1` in the test process's environment (the CI
    /// drop-in forwards it as `TEST_RUNNER_SYLVIA_AUDIBLE_PLAYBACK`). Any other value, or none, is quiet.
    public static func testsAreAudible(environment: [String: String]) -> Bool {
        environment[environmentKey] == "1"
    }

    public static func testVolume(environment: [String: String]) -> Float {
        testsAreAudible(environment: environment) ? 1 : quietVolume
    }

    public enum Reason: String, Sendable {
        /// `SYLVIA_AUDIBLE_PLAYBACK=1` in the harness's environment.
        case environment
        /// The harness's full-volume toggle, or the launch argument that overrides it.
        case toggle = "toggle_or_launch_argument"
        /// Neither: quiet.
        case `default`
    }

    /// Harness: full volume with `SYLVIA_AUDIBLE_PLAYBACK=1` in its environment, or when its full-volume toggle is on
    /// (a person's listening check on a device); quiet otherwise.
    public static func harnessIsAudible(environment: [String: String], defaults: UserDefaults) -> (audible: Bool, reason: Reason) {
        if testsAreAudible(environment: environment) { return (true, .environment) }
        if defaults.object(forKey: harnessDefaultsKey) != nil { return (defaults.bool(forKey: harnessDefaultsKey), .toggle) }
        return (false, .default)
    }

    public static func volume(audible: Bool) -> Float { audible ? 1 : quietVolume }
}
