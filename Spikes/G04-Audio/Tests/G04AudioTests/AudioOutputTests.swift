import AVFoundation
import Foundation
import Testing
@testable import G04AudioKit

/// Quiet automated runs (product-owner request): the tests and the harness play at 1 % volume unless
/// `SYLVIA_AUDIBLE_PLAYBACK=1` (muting would change what the tests measure; `MutedRenderingTests`), the quiet volume is
/// injected by them, and the product's engines stay at full volume by default.
@Suite("Quiet test and harness output; full-volume engine default")
@MainActor
struct AudioOutputTests {
    @Test("Tests and probes are quiet (1 % volume) unless SYLVIA_AUDIBLE_PLAYBACK=1")
    func testPolicy() {
        #expect(!SpikeAudioOutput.testsAreAudible(environment: [:]))
        #expect(SpikeAudioOutput.testVolume(environment: [:]) == SpikeAudioOutput.quietVolume)
        #expect(SpikeAudioOutput.quietVolume == 0.01)
        for value in ["", "0", "true", "yes", "YES", " 1", "2"] {
            #expect(!SpikeAudioOutput.testsAreAudible(environment: [SpikeAudioOutput.environmentKey: value]), "value '\(value)'")
            #expect(SpikeAudioOutput.testVolume(environment: [SpikeAudioOutput.environmentKey: value]) == 0.01, "value '\(value)'")
        }
        #expect(SpikeAudioOutput.testsAreAudible(environment: [SpikeAudioOutput.environmentKey: "1"]))
        #expect(SpikeAudioOutput.testVolume(environment: [SpikeAudioOutput.environmentKey: "1"]) == 1)
    }

    @Test("The harness is quiet unless SYLVIA_AUDIBLE_PLAYBACK=1 or its full-volume toggle is on")
    func harnessPolicy() throws {
        let suite = "g04-audio-output-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let on = [SpikeAudioOutput.environmentKey: "1"]

        var r = SpikeAudioOutput.harnessIsAudible(environment: [:], defaults: defaults)
        #expect(r.audible == false && r.reason == .default)
        #expect(SpikeAudioOutput.volume(audible: r.audible) == 0.01)
        r = SpikeAudioOutput.harnessIsAudible(environment: [SpikeAudioOutput.environmentKey: "0"], defaults: defaults)
        #expect(r.audible == false && r.reason == .default)
        r = SpikeAudioOutput.harnessIsAudible(environment: on, defaults: defaults)
        #expect(r.audible == true && r.reason == .environment)
        #expect(SpikeAudioOutput.volume(audible: r.audible) == 1)

        defaults.set(true, forKey: SpikeAudioOutput.harnessDefaultsKey)  // a person turned full volume on
        r = SpikeAudioOutput.harnessIsAudible(environment: [:], defaults: defaults)
        #expect(r.audible == true && r.reason == .toggle)
        defaults.set(false, forKey: SpikeAudioOutput.harnessDefaultsKey)  // or the CI's `-g04AudiblePlayback NO`
        r = SpikeAudioOutput.harnessIsAudible(environment: [:], defaults: defaults)
        #expect(r.audible == false && r.reason == .toggle)
        r = SpikeAudioOutput.harnessIsAudible(environment: on, defaults: defaults)
        #expect(r.audible == true && r.reason == .environment)
    }

    @Test("Every player this test process creates is quiet unless SYLVIA_AUDIBLE_PLAYBACK=1")
    func thisProcessIsQuiet() {
        let expected: Float = ProcessInfo.processInfo.environment[SpikeAudioOutput.environmentKey] == "1" ? 1 : 0.01
        #expect(TestAudio.volume == expected)
        #expect(TestAudio.engine().player.volume == expected)
        #expect(TestAudio.engine().outputVolume == expected)
        #expect(TestAudio.previewPlayer().player.volume == expected)
        #expect(TestAudio.player().volume == expected)
        // Quiet, not muted: a muted player renders differently after the time-pitch stage (MutedRenderingTests).
        #expect(TestAudio.engine().player.isMuted == false)
        #expect(TestAudio.player().isMuted == false)
        // The real-engine harness every playing suite uses.
        let real = RealPlayer()
        #expect(real.engine.player.volume == expected)
        #expect(real.preview.player.volume == expected)
        // The environment line of every result table says so.
        #expect(Results.environmentLabel().hasSuffix(TestAudio.label))
        #expect(TestAudio.label.contains(expected == 1 ? "full volume" : "1 % volume"))
    }

    @Test("A playback engine created without the test configuration plays at full volume (product default)")
    func productEnginesAreAudible() {
        let engine = AVQueuePlayerEngine()  // full-volume-by-design: the product default under test
        #expect(engine.player.isMuted == false)
        #expect(engine.player.volume == 1)
        #expect(engine.outputVolume == 1)
        let preview = AVPreviewPlayer()  // full-volume-by-design: the product default under test
        #expect(preview.player.isMuted == false)
        #expect(preview.player.volume == 1)
        #expect(preview.outputVolume == 1)
        // A service over default engines plays at full volume too: nothing in the service changes the volume.
        let service = PlaybackService(engine: engine, previewPlayer: preview, session: SpySession(), positions: InMemoryPositionStore())
        service.setRate(2)
        #expect(engine.player.volume == 1 && preview.player.volume == 1)
        #expect(engine.player.isMuted == false && preview.player.isMuted == false)
        // The quiet volume is an explicit, reversible option.
        let quiet = AVQueuePlayerEngine(outputVolume: 0.01)  // full-volume-by-design: tests the explicit option
        #expect(quiet.player.volume == 0.01)
        quiet.outputVolume = 1
        #expect(quiet.player.volume == 1)
        let quietPreview = AVPreviewPlayer(outputVolume: 0.01)  // full-volume-by-design: tests the explicit option
        #expect(quietPreview.player.volume == 0.01)
    }
}

extension RealAV {
    @Suite("Quiet output leaves what the analysis taps see unchanged; muted output does not (why the tests are quiet, not muted)", .serialized)
    @MainActor
    struct MutedRenderingTests {
        struct Config {
            var name: String
            var muted: Bool
            var volume: Float
            /// Only the configuration the tests use is asserted; the others are recorded.
            var asserted: Bool
        }

        /// Plays the 1 kHz tone (the rate-and-pitch fixture) with a tap before or after the effects (the time-pitch
        /// stage), in the configuration every test player uses and, for the record, muted and at volume 0. For the
        /// test configuration it checks that both taps see the tone at the file's own level, at 1 kHz (time-domain
        /// pitch preservation), and that media time advances at the rate: the quiet volume is applied after
        /// everything the tests measure. Nothing here is audible above 1 % volume.
        @Test("The test players' quiet volume leaves the analysis taps and the clock unchanged", .timeLimit(.minutes(3)))
        func quietPlayerRenders() async throws {
            let url = try Fixtures.url("tone-1khz-60s.m4a")
            // The tone's own level (ffmpeg's sine at -6 dB, about 0.065), decoded from the file.
            let reference = try await PCMDecoder.decode(url: url, start: 5, duration: 4)
            let referencePeak = reference.samples.map(abs).max() ?? 0
            var lines = ["# Output volume of the tests, probes and harness (quiet, 1 % volume, unless SYLVIA_AUDIBLE_PLAYBACK=1) and what the analysis taps see.",
                         "# Environment: \(Results.environmentLabel())",
                         "# reference: tone-1khz-60s.m4a decoded with AVAssetReader, peak \(String(format: "%.4f", referencePeak)). Time-domain pitch algorithm (the engine's).",
                         "# Rows 'muted' and 'volume-0' are recorded only: they show why the tests are quiet rather than muted (not asserted).",
                         "config\tplayer_muted\tplayer_volume\ttap\trate\tmedia_advance_per_wall_s\tchunks\tpeak\tpeak_over_reference\trms\tmeasured_tone_hz"]
            defer { Results.write("audio-output.txt", lines) }
            let configs = [Config(name: TestAudio.audible ? "test (full volume)" : "test (quiet)", muted: false, volume: TestAudio.volume, asserted: true),
                           Config(name: "muted", muted: true, volume: TestAudio.volume, asserted: false),
                           Config(name: "volume-0", muted: false, volume: 0, asserted: false)]
            for config in configs {
                for postEffects in config.asserted ? [false, true] : [true] {
                    for rate in [Float(1), 2, 3] {
                        let item = AVPlayerItem(asset: AssetInspector.preciseAsset(url))
                        item.audioTimePitchAlgorithm = AVQueuePlayerEngine.pitchAlgorithm
                        let collector = AudioTapCollector()
                        try await AudioTap.attach(to: item, collector: collector, postEffects: postEffects)
                        let player = TestAudio.player(item)
                        player.volume = min(config.volume, TestAudio.volume)  // never louder than the test configuration
                        player.isMuted = config.muted
                        player.automaticallyWaitsToMinimizeStalling = false
                        for _ in 0..<200 where item.status == .unknown { try await Task.sleep(for: .milliseconds(25)) }
                        try #require(item.status == .readyToPlay)
                        _ = await player.seek(to: CMTime(seconds: 5, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                        player.playImmediately(atRate: rate)
                        try await Task.sleep(for: .seconds(1))  // settle, as the rate-and-pitch test does
                        collector.reset()
                        let m0 = player.currentTime().seconds, w0 = uptime()
                        try await Task.sleep(for: .seconds(3))
                        let m1 = player.currentTime().seconds, w1 = uptime()
                        player.pause()
                        player.replaceCurrentItem(with: nil)
                        let chunks = collector.snapshot()
                        let samples = chunks.flatMap(\.samples)
                        let peak = samples.map(abs).max() ?? 0
                        let rms = samples.isEmpty ? 0 : (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
                        let advance = (m1 - m0) / (w1 - w0)
                        let freq = toneFrequency(samples, rate: collector.sampleRate)
                        let tap = postEffects ? "post-effects" : "pre-effects"
                        lines.append([config.name, "\(player.isMuted)", "\(player.volume)", tap, "\(rate)", String(format: "%.3f", advance), "\(chunks.count)",
                                      String(format: "%.4f", peak), String(format: "%.3f", peak / referencePeak), String(format: "%.4f", rms),
                                      String(format: "%.1f", freq)].joined(separator: "\t"))
                        guard config.asserted else { continue }
                        #expect(player.volume == TestAudio.volume && !player.isMuted)
                        #expect(!chunks.isEmpty, "no audio reached the \(tap) tap at \(rate)x")
                        #expect(referencePeak > 0.01 && abs(peak / referencePeak - 1) <= 0.1, "\(tap) tap peak \(peak) at \(rate)x, the file's \(referencePeak)")
                        #expect(abs(advance - Double(rate)) <= 0.1 * Double(rate), "media advance \(advance) at \(rate)x")
                        #expect(abs(freq - 1000) <= 20, "\(tap) tone \(freq) Hz at \(rate)x")
                    }
                }
            }
        }
    }
}
